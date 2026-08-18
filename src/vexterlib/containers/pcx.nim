## Structural parsing for ZSoft PCX images.

import std/[os, strutils]

const PcxTypeId* = "pcx"

type
  PcxImageSource* = object
    version*: int
    encoding*: int
    bitsPerPixel*: int
    width*, height*: int
    xMin*, yMin*: int
    horizontalDpi*, verticalDpi*: int
    planes*: int
    bytesPerLine*: int
    paletteInfo*: int
    headerPalette*: seq[byte]
    imageData*: seq[byte]

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc parsePcx*(data: openArray[byte]): PcxImageSource =
  if data.len < 128:
    raise newException(ValueError, "PCX image is shorter than its 128-byte header")
  if data[0] != 0x0a:
    raise newException(ValueError, "invalid PCX manufacturer identifier")
  result.version = int(data[1])
  result.encoding = int(data[2])
  result.bitsPerPixel = int(data[3])
  if result.version notin [0, 2, 3, 4, 5]:
    raise newException(ValueError, "unsupported PCX version")
  if result.encoding notin [0, 1]:
    raise newException(ValueError, "unsupported PCX image encoding")
  if result.bitsPerPixel notin [1, 2, 4, 8]:
    raise newException(ValueError, "unsupported PCX bits per pixel")
  result.xMin = leWord(data, 4)
  result.yMin = leWord(data, 6)
  let xMax = leWord(data, 8)
  let yMax = leWord(data, 10)
  if xMax < result.xMin or yMax < result.yMin:
    raise newException(ValueError, "invalid PCX image bounds")
  result.width = xMax - result.xMin + 1
  result.height = yMax - result.yMin + 1
  result.horizontalDpi = leWord(data, 12)
  result.verticalDpi = leWord(data, 14)
  result.headerPalette.add data.toOpenArray(16, 63)
  if data[64] != 0:
    raise newException(ValueError, "invalid PCX reserved header byte")
  result.planes = int(data[65])
  result.bytesPerLine = leWord(data, 66)
  result.paletteInfo = leWord(data, 68)
  if result.planes <= 0 or result.planes > 4:
    raise newException(ValueError, "unsupported PCX plane count")
  let minimumBytes = (result.width * result.bitsPerPixel + 7) div 8
  if result.bytesPerLine < minimumBytes or result.bytesPerLine mod 2 != 0:
    raise newException(ValueError, "invalid PCX bytes-per-line value")
  if result.bitsPerPixel == 8 and result.planes notin [1, 3]:
    raise newException(ValueError, "eight-bit PCX requires one or three planes")
  if result.bitsPerPixel < 8 and
      result.bitsPerPixel * result.planes > 4:
    raise newException(ValueError, "indexed PCX supports at most four colour bits")
  if data.len > 128:
    result.imageData.add data.toOpenArray(128, data.high)

proc isPcx*(data: openArray[byte]): bool =
  try:
    discard parsePcx(data)
    true
  except ValueError:
    false

proc hasPcxExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".pcx"
