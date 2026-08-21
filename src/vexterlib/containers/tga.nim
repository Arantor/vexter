## Structural parsing for Truevision TGA raster images.

import std/[os, strutils]

const TgaTypeId* = "tga"

type TgaImageSource* = object
  imageId*: seq[byte]
  imageType*: int
  colourMapOrigin*, colourMapLength*, colourMapEntryBits*: int
  xOrigin*, yOrigin*: int
  width*, height*, pixelBits*, attributeBits*: int
  topOrigin*: bool
  colourMap*: seq[byte]
  imageData*: seq[byte]

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc checkedProduct(left, right: int, message: string): int =
  if left < 0 or right < 0 or (left != 0 and right > high(int) div left):
    raise newException(ValueError, message)
  left * right

proc parseTga*(data: openArray[byte]): TgaImageSource =
  if data.len < 18:
    raise newException(ValueError, "TGA image is shorter than its 18-byte header")

  let idLength = int(data[0])
  let colourMapType = int(data[1])
  result.imageType = int(data[2])
  if result.imageType notin [1, 2, 3, 9, 10, 11]:
    raise newException(ValueError, "unsupported TGA image type")
  if colourMapType notin [0, 1]:
    raise newException(ValueError, "invalid TGA colour-map type")
  let mapped = result.imageType in [1, 9]
  if mapped and colourMapType != 1:
    raise newException(ValueError, "colour-mapped TGA image has no colour map")
  if result.imageType in [3, 11] and colourMapType != 0:
    raise newException(ValueError, "grayscale TGA image cannot have a colour map")

  result.colourMapOrigin = leWord(data, 3)
  result.colourMapLength = leWord(data, 5)
  result.colourMapEntryBits = int(data[7])
  result.xOrigin = leWord(data, 8)
  result.yOrigin = leWord(data, 10)
  result.width = leWord(data, 12)
  result.height = leWord(data, 14)
  result.pixelBits = int(data[16])
  result.attributeBits = int(data[17] and 0x0f)
  result.topOrigin = (data[17] and 0x20) != 0

  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "TGA dimensions must be positive")
  discard checkedProduct(result.width, result.height,
    "TGA dimensions exceed platform capacity")
  if (data[17] and 0xd0) != 0:
    raise newException(ValueError, "unsupported reserved or interleaved TGA descriptor")

  if colourMapType == 0:
    if result.colourMapLength != 0:
      raise newException(ValueError, "TGA header declares a colour map with no colour-map type")
  else:
    if result.colourMapLength <= 0 or
        result.colourMapEntryBits notin [16, 24, 32]:
      raise newException(ValueError, "unsupported TGA colour-map specification")
    if mapped and (result.colourMapLength > 256 or
        result.colourMapOrigin + result.colourMapLength > 65536):
      raise newException(ValueError, "TGA colour map exceeds indexed raster capacity")

  case result.imageType
  of 1, 9:
    if result.pixelBits notin [8, 16]:
      raise newException(ValueError, "unsupported TGA colour-map index size")
  of 2, 10:
    if result.pixelBits notin [16, 24, 32]:
      raise newException(ValueError, "unsupported TGA true-colour pixel size")
    if (result.pixelBits == 16 and result.attributeBits notin [0, 1]) or
        (result.pixelBits == 24 and result.attributeBits != 0) or
        (result.pixelBits == 32 and result.attributeBits notin [0, 8]):
      raise newException(ValueError, "invalid TGA true-colour attribute size")
  of 3, 11:
    if result.pixelBits != 8 or result.attributeBits != 0:
      raise newException(ValueError, "unsupported TGA grayscale pixel layout")
  else:
    discard

  var offset = 18
  if idLength > data.len - offset:
    raise newException(ValueError, "truncated TGA identification field")
  if idLength > 0:
    result.imageId.add data.toOpenArray(offset, offset + idLength - 1)
  offset += idLength

  if colourMapType == 1:
    let entryBytes = result.colourMapEntryBits div 8
    let mapBytes = checkedProduct(result.colourMapLength, entryBytes,
      "TGA colour map exceeds platform capacity")
    if mapBytes > data.len - offset:
      raise newException(ValueError, "truncated TGA colour map")
    if mapBytes > 0:
      result.colourMap.add data.toOpenArray(offset, offset + mapBytes - 1)
    offset += mapBytes

  let pixelBytes = result.pixelBits div 8
  let pixelCount = result.width * result.height
  let decodedBytes = checkedProduct(pixelCount, pixelBytes,
    "TGA image data exceeds platform capacity")
  let imageStart = offset
  if result.imageType in [1, 2, 3]:
    if decodedBytes > data.len - offset:
      raise newException(ValueError, "truncated uncompressed TGA image data")
    offset += decodedBytes
  else:
    var covered = 0
    while covered < pixelCount:
      if offset >= data.len:
        raise newException(ValueError, "truncated TGA RLE packet header")
      let header = data[offset]
      inc offset
      let count = int(header and 0x7f) + 1
      if count > pixelCount - covered:
        raise newException(ValueError, "TGA RLE packet exceeds the image dimensions")
      let values = if (header and 0x80) != 0: 1 else: count
      let bytes = checkedProduct(values, pixelBytes,
        "TGA RLE packet exceeds platform capacity")
      if bytes > data.len - offset:
        raise newException(ValueError, "truncated TGA RLE packet body")
      offset += bytes
      covered += count
  if offset > imageStart:
    result.imageData.add data.toOpenArray(imageStart, offset - 1)

proc isTga*(data: openArray[byte]): bool =
  try: discard parseTga(data); true
  except ValueError: false

proc hasTgaExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".tga", ".vda", ".icb", ".vst"]
