## Structural parsing for Windows ICO icon and CUR cursor containers.

import std/[os, strutils]
import ./[bmp, png_container]

const
  WindowsIcoTypeId* = "windows.ico"
  WindowsCurTypeId* = "windows.cur"

type
  WindowsIconKind* = enum
    wikIcon = 1
    wikCursor = 2

  WindowsIconEncoding* = enum
    wieDib
    wiePng
    wieUnknown

  WindowsIconEntry* = object
    width*, height*: int
    colourCount*: int
    planes*, bitsPerPixel*: int
    hotspotX*, hotspotY*: int
    dataOffset*, dataLength*: int
    encoding*: WindowsIconEncoding
    data*: seq[byte]
    dib*: BmpImageSource
    png*: PngImageSource
    andMask*: seq[byte]

  WindowsIcon* = object
    kind*: WindowsIconKind
    entries*: seq[WindowsIconEntry]

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc leDword(data: openArray[byte], offset: int): int {.inline.} =
  int(uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24))

proc iconDib(data: openArray[byte]): tuple[dib: BmpImageSource, mask: seq[byte]] =
  result.dib = parseDib(data)
  if result.dib.topDown:
    raise newException(ValueError, "ICO/CUR DIB images cannot be top-down")
  if result.dib.height mod 2 != 0:
    raise newException(ValueError, "ICO/CUR DIB height must include equally sized XOR and AND images")
  result.dib.height = result.dib.height div 2
  if result.dib.height == 0:
    raise newException(ValueError, "ICO/CUR DIB image has zero logical height")
  if result.dib.compression in [1, 2]:
    if result.dib.imageSize <= 0:
      raise newException(ValueError, "RLE-compressed ICO/CUR DIB requires an XOR image size")
    if result.dib.imageSize > result.dib.pixelData.len:
      raise newException(ValueError, "truncated ICO/CUR RLE XOR image")
    let allPixels = result.dib.pixelData
    result.dib.pixelData = allPixels[0 ..< result.dib.imageSize]
    let maskBytes = ((result.dib.width + 31) div 32) * 4 * result.dib.height
    if maskBytes > allPixels.len - result.dib.imageSize:
      raise newException(ValueError, "truncated ICO/CUR AND mask")
    result.mask = allPixels[result.dib.imageSize ..<
      result.dib.imageSize + maskBytes]
  else:
    let xorRowBytes = ((result.dib.width * result.dib.bitsPerPixel + 31) div 32) * 4
    let xorBytes = xorRowBytes * result.dib.height
    if xorBytes > result.dib.pixelData.len:
      raise newException(ValueError, "truncated ICO/CUR XOR image")
    let allPixels = result.dib.pixelData
    result.dib.pixelData = allPixels[0 ..< xorBytes]
    let maskBytes = ((result.dib.width + 31) div 32) * 4 * result.dib.height
    if maskBytes > allPixels.len - xorBytes:
      raise newException(ValueError, "truncated ICO/CUR AND mask")
    result.mask = allPixels[xorBytes ..< xorBytes + maskBytes]

proc parseWindowsIcon*(data: openArray[byte]): WindowsIcon =
  if data.len < 6 or leWord(data, 0) != 0:
    raise newException(ValueError, "invalid ICO/CUR reserved header")
  let kind = leWord(data, 2)
  if kind notin [1, 2]:
    raise newException(ValueError, "ICO/CUR type must be icon or cursor")
  result.kind = WindowsIconKind(kind)
  let count = leWord(data, 4)
  if count < 1 or count > (data.len - 6) div 16:
    raise newException(ValueError, "invalid ICO/CUR directory count")
  let directoryEnd = 6 + count * 16
  for index in 0 ..< count:
    let offset = 6 + index * 16
    var entry = WindowsIconEntry(
      width: (if data[offset] == 0: 256 else: int(data[offset])),
      height: (if data[offset + 1] == 0: 256 else: int(data[offset + 1])),
      colourCount: int(data[offset + 2]),
      dataLength: leDword(data, offset + 8),
      dataOffset: leDword(data, offset + 12))
    if data[offset + 3] != 0:
      raise newException(ValueError, "ICO/CUR directory reserved byte must be zero")
    if result.kind == wikIcon:
      entry.planes = leWord(data, offset + 4)
      entry.bitsPerPixel = leWord(data, offset + 6)
    else:
      entry.hotspotX = leWord(data, offset + 4)
      entry.hotspotY = leWord(data, offset + 6)
    if entry.dataLength <= 0 or entry.dataOffset < directoryEnd or
        entry.dataOffset > data.len or entry.dataLength > data.len - entry.dataOffset:
      raise newException(ValueError, "ICO/CUR entry points outside the file")
    entry.data.add data.toOpenArray(entry.dataOffset,
      entry.dataOffset + entry.dataLength - 1)
    if isPng(entry.data):
      entry.encoding = wiePng
      entry.png = parsePng(entry.data)
    else:
      try:
        let parsed = iconDib(entry.data)
        entry.encoding = wieDib
        entry.dib = parsed.dib
        entry.andMask = parsed.mask
      except ValueError:
        entry.encoding = wieUnknown
    result.entries.add entry

proc isWindowsIcon*(data: openArray[byte]): bool =
  try: discard parseWindowsIcon(data); true
  except ValueError: false

proc windowsIconTypeId*(icon: WindowsIcon): string =
  if icon.kind == wikIcon: WindowsIcoTypeId else: WindowsCurTypeId

proc hasWindowsIconExtension*(filename: string, kind: WindowsIconKind): bool =
  let extension = filename.splitFile.ext.toLowerAscii
  if kind == wikIcon: extension == ".ico" else: extension == ".cur"
