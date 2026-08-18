## Structural parsing for BMP files and standalone DIB images.

import std/[os, strutils]

const
  BmpTypeId* = "windows.bmp"
  DibTypeId* = "windows.dib"

type
  BmpImageSource* = object
    typeId*: string
    headerSize*: int
    width*, height*: int
    topDown*: bool
    bitsPerPixel*: int
    compression*: int
    coloursUsed*: int
    xPixelsPerMetre*, yPixelsPerMetre*: int
    redMask*, greenMask*, blueMask*, alphaMask*: uint32
    palette*: seq[byte]
    paletteEntrySize*: int
    pixelData*: seq[byte]

proc leWord(data: openArray[byte], offset: int): uint16 {.inline.} =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc signedDword(data: openArray[byte], offset: int): int32 {.inline.} =
  cast[int32](leDword(data, offset))

proc parseBitmap(data: openArray[byte], wrapped: bool): BmpImageSource =
  let dibOffset = if wrapped: 14 else: 0
  if wrapped:
    if data.len < 18 or data[0] != byte('B') or data[1] != byte('M'):
      raise newException(ValueError, "invalid BMP file signature")
    let declaredSize = int(leDword(data, 2))
    if declaredSize != 0 and declaredSize != data.len:
      raise newException(ValueError, "BMP file size does not match its header")
    if leWord(data, 6) != 0 or leWord(data, 8) != 0:
      raise newException(ValueError, "BMP reserved fields must be zero")
    result.typeId = BmpTypeId
  else:
    if data.len < 12:
      raise newException(ValueError, "DIB image is shorter than its header")
    result.typeId = DibTypeId

  result.headerSize = int(leDword(data, dibOffset))
  var paletteOffset: int
  if result.headerSize == 12:
    if dibOffset + 12 > data.len:
      raise newException(ValueError, "truncated OS/2 DIB header")
    result.width = int(leWord(data, dibOffset + 4))
    result.height = int(leWord(data, dibOffset + 6))
    if leWord(data, dibOffset + 8) != 1:
      raise newException(ValueError, "BMP/DIB must contain one colour plane")
    result.bitsPerPixel = int(leWord(data, dibOffset + 10))
    result.paletteEntrySize = 3
    paletteOffset = dibOffset + 12
  elif result.headerSize in [40, 52, 56, 108, 124]:
    if result.headerSize > data.len - dibOffset:
      raise newException(ValueError, "truncated Windows DIB header")
    let width = signedDword(data, dibOffset + 4)
    let height = signedDword(data, dibOffset + 8)
    if width <= 0 or height == 0 or height == low(int32):
      raise newException(ValueError, "invalid BMP/DIB dimensions")
    result.width = int(width)
    result.topDown = height < 0
    result.height = abs(int(height))
    if leWord(data, dibOffset + 12) != 1:
      raise newException(ValueError, "BMP/DIB must contain one colour plane")
    result.bitsPerPixel = int(leWord(data, dibOffset + 14))
    result.compression = int(leDword(data, dibOffset + 16))
    result.xPixelsPerMetre = int(signedDword(data, dibOffset + 24))
    result.yPixelsPerMetre = int(signedDword(data, dibOffset + 28))
    result.coloursUsed = int(leDword(data, dibOffset + 32))
    result.paletteEntrySize = 4
    paletteOffset = dibOffset + result.headerSize
    if result.compression == 3:
      if result.headerSize >= 52:
        result.redMask = leDword(data, dibOffset + 40)
        result.greenMask = leDword(data, dibOffset + 44)
        result.blueMask = leDword(data, dibOffset + 48)
        if result.headerSize >= 56:
          result.alphaMask = leDword(data, dibOffset + 52)
      else:
        if paletteOffset + 12 > data.len:
          raise newException(ValueError, "truncated BMP bitfield masks")
        result.redMask = leDword(data, paletteOffset)
        result.greenMask = leDword(data, paletteOffset + 4)
        result.blueMask = leDword(data, paletteOffset + 8)
        paletteOffset += 12
  else:
    raise newException(ValueError, "unsupported BMP/DIB header size")

  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "BMP/DIB dimensions must be positive")
  if result.bitsPerPixel notin [1, 4, 8, 16, 24, 32]:
    raise newException(ValueError, "unsupported BMP/DIB bits per pixel")
  if result.compression notin [0, 1, 2, 3]:
    raise newException(ValueError, "unsupported BMP/DIB compression")
  if (result.compression == 1 and result.bitsPerPixel != 8) or
      (result.compression == 2 and result.bitsPerPixel != 4) or
      (result.compression == 3 and result.bitsPerPixel notin [16, 32]):
    raise newException(ValueError, "BMP/DIB compression does not match its depth")
  if result.topDown and result.compression in [1, 2]:
    raise newException(ValueError, "top-down BMP/DIB cannot use RLE compression")

  var paletteCount = result.coloursUsed
  if result.bitsPerPixel <= 8:
    let maximum = 1 shl result.bitsPerPixel
    if paletteCount == 0: paletteCount = maximum
    if paletteCount < 1 or paletteCount > maximum:
      raise newException(ValueError, "invalid BMP/DIB palette size")
  elif paletteCount < 0 or paletteCount > 65536:
    raise newException(ValueError, "invalid BMP/DIB colour-table size")
  let paletteBytes = paletteCount * result.paletteEntrySize
  if paletteOffset < 0 or paletteBytes > data.len - paletteOffset:
    raise newException(ValueError, "truncated BMP/DIB palette")
  if paletteBytes > 0:
    result.palette.add data.toOpenArray(paletteOffset,
      paletteOffset + paletteBytes - 1)
  let minimumPixelOffset = paletteOffset + paletteBytes
  let pixelOffset = if wrapped: int(leDword(data, 10)) else: minimumPixelOffset
  if pixelOffset < minimumPixelOffset or pixelOffset > data.len:
    raise newException(ValueError, "invalid BMP/DIB pixel-data offset")
  if pixelOffset < data.len:
    result.pixelData.add data.toOpenArray(pixelOffset, data.high)

proc parseBmp*(data: openArray[byte]): BmpImageSource = parseBitmap(data, true)
proc parseDib*(data: openArray[byte]): BmpImageSource = parseBitmap(data, false)

proc isBmp*(data: openArray[byte]): bool =
  try: discard parseBmp(data); true
  except ValueError: false

proc isDib*(data: openArray[byte]): bool =
  try: discard parseDib(data); true
  except ValueError: false

proc hasBmpExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".bmp"

proc hasDibExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".dib"
