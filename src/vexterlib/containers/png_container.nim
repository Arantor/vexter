## Structural parsing for PNG images, retaining all chunks for metadata.

import std/[os, strutils]

const
  PngTypeId* = "png"
  PngSignature* = [137'u8, 80, 78, 71, 13, 10, 26, 10]

type
  PngChunk* = object
    kind*: string
    data*: seq[byte]

  PngImageSource* = object
    width*, height*: int
    bitDepth*, colourType*: int
    compressionMethod*, filterMethod*, interlaceMethod*: int
    chunks*: seq[PngChunk]
    palette*: seq[byte]
    transparency*: seq[byte]
    imageData*: seq[byte]

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for unused in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

proc parsePng*(data: openArray[byte]): PngImageSource =
  if data.len < 33 or data.toOpenArray(0, 7) != PngSignature:
    raise newException(ValueError, "invalid PNG signature")
  var offset = 8
  var seenHeader = false
  var seenPalette = false
  var seenTransparency = false
  var seenImageData = false
  var imageDataEnded = false
  var seenEnd = false
  while offset < data.len:
    if data.len - offset < 12:
      raise newException(ValueError, "truncated PNG chunk header")
    let length = int(beDword(data, offset))
    if length > data.len - offset - 12:
      raise newException(ValueError, "truncated PNG chunk data")
    var kind = newString(4)
    for index in 0 ..< 4:
      let value = data[offset + 4 + index]
      if value notin {byte('A') .. byte('Z'), byte('a') .. byte('z')}:
        raise newException(ValueError, "invalid PNG chunk type")
      kind[index] = char(value)
    var checked: seq[byte]
    checked.add data.toOpenArray(offset + 4, offset + 7 + length)
    if crc32(checked) != beDword(data, offset + 8 + length):
      raise newException(ValueError, "PNG chunk CRC-32 does not match: " & kind)
    var payload: seq[byte]
    if length > 0:
      payload.add data.toOpenArray(offset + 8, offset + 7 + length)
    result.chunks.add PngChunk(kind: kind, data: payload)

    if not seenHeader and kind != "IHDR":
      raise newException(ValueError, "PNG IHDR must be the first chunk")
    case kind
    of "IHDR":
      if seenHeader or length != 13:
        raise newException(ValueError, "PNG must contain one 13-byte IHDR")
      seenHeader = true
      result.width = int(beDword(payload, 0))
      result.height = int(beDword(payload, 4))
      result.bitDepth = int(payload[8])
      result.colourType = int(payload[9])
      result.compressionMethod = int(payload[10])
      result.filterMethod = int(payload[11])
      result.interlaceMethod = int(payload[12])
      if result.width <= 0 or result.height <= 0:
        raise newException(ValueError, "PNG dimensions must be positive")
      if result.compressionMethod != 0 or result.filterMethod != 0 or
          result.interlaceMethod notin [0, 1]:
        raise newException(ValueError, "unsupported PNG image method")
      let legalDepths = case result.colourType
        of 0: result.bitDepth in [1, 2, 4, 8, 16]
        of 2, 4, 6: result.bitDepth in [8, 16]
        of 3: result.bitDepth in [1, 2, 4, 8]
        else: false
      if not legalDepths:
        raise newException(ValueError, "invalid PNG colour type or bit depth")
    of "PLTE":
      if seenPalette or seenImageData or length == 0 or length mod 3 != 0 or
          length > 768 or result.colourType in [0, 4]:
        raise newException(ValueError, "invalid PNG PLTE chunk")
      seenPalette = true
      result.palette = payload
    of "tRNS":
      if seenImageData or seenTransparency or
          result.colourType in [4, 6]:
        raise newException(ValueError, "invalid PNG tRNS chunk")
      seenTransparency = true
      result.transparency = payload
    of "IDAT":
      if imageDataEnded:
        raise newException(ValueError, "PNG IDAT chunks must be consecutive")
      seenImageData = true
      result.imageData.add payload
    of "IEND":
      if length != 0 or seenEnd or not seenImageData:
        raise newException(ValueError, "invalid PNG IEND chunk")
      seenEnd = true
      offset += 12 + length
      if offset != data.len:
        raise newException(ValueError, "PNG has data after IEND")
      break
    else:
      if seenImageData: imageDataEnded = true
      # Unknown ancillary or private chunks, including APNG chunks, are
      # retained above and deliberately ignored for static image decoding.
    offset += 12 + length
  if not seenHeader or not seenImageData or not seenEnd:
    raise newException(ValueError, "PNG is missing a required chunk")
  if result.colourType == 3 and not seenPalette:
    raise newException(ValueError, "indexed PNG requires PLTE")
  if result.colourType == 3 and result.palette.len div 3 >
      (1 shl result.bitDepth):
    raise newException(ValueError, "PNG palette exceeds its bit-depth capacity")
  if result.transparency.len > 0:
    case result.colourType
    of 0:
      if result.transparency.len != 2:
        raise newException(ValueError, "grayscale PNG tRNS must contain one sample")
      let transparent = (uint16(result.transparency[0]) shl 8) or
        uint16(result.transparency[1])
      if uint32(transparent) >= (1'u32 shl result.bitDepth):
        raise newException(ValueError, "PNG grayscale tRNS sample is out of range")
    of 2:
      if result.transparency.len != 6:
        raise newException(ValueError, "true-colour PNG tRNS must contain three samples")
      if result.bitDepth == 8 and (result.transparency[0] != 0 or
          result.transparency[2] != 0 or result.transparency[4] != 0):
        raise newException(ValueError, "PNG true-colour tRNS sample is out of range")
    of 3:
      if result.transparency.len > result.palette.len div 3:
        raise newException(ValueError, "indexed PNG tRNS exceeds its palette")
    else: discard

proc isPng*(data: openArray[byte]): bool =
  try: discard parsePng(data); true
  except ValueError: false

proc hasPngExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".png"
