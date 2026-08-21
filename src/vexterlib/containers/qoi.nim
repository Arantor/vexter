## Structural parsing for Quite OK Image (QOI) files.

import std/[os, strutils]

const
  QoiTypeId* = "qoi"
  QoiMagic* = [byte('q'), byte('o'), byte('i'), byte('f')]
  QoiEndMarker* = [0'u8, 0, 0, 0, 0, 0, 0, 1]

type
  QoiImageSource* = object
    width*, height*: int
    channels*, colourSpace*: int
    chunks*: seq[byte]

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc parseQoi*(data: openArray[byte]): QoiImageSource =
  if data.len < 22 or data.toOpenArray(0, 3) != QoiMagic:
    raise newException(ValueError, "invalid QOI signature")
  let width = beDword(data, 4)
  let height = beDword(data, 8)
  if width == 0 or height == 0:
    raise newException(ValueError, "QOI dimensions must be positive")
  let pixelCount = uint64(width) * uint64(height)
  if pixelCount > uint64(high(int)):
    raise newException(ValueError, "QOI dimensions exceed platform capacity")
  result.width = int(width)
  result.height = int(height)
  result.channels = int(data[12])
  result.colourSpace = int(data[13])
  if result.channels notin [3, 4]:
    raise newException(ValueError, "QOI channels must be RGB or RGBA")
  if result.colourSpace notin [0, 1]:
    raise newException(ValueError, "invalid QOI colour space")

  let markerOffset = data.len - QoiEndMarker.len
  if data.toOpenArray(markerOffset, data.high) != QoiEndMarker:
    raise newException(ValueError, "invalid QOI end marker")
  var offset = 14
  var covered = 0'u64
  while offset < markerOffset:
    if covered >= pixelCount:
      raise newException(ValueError, "QOI has data after its final pixel")
    let tag = data[offset]
    var chunkLength = 1
    var produced = 1'u64
    if tag == 0xfe:
      chunkLength = 4
    elif tag == 0xff:
      chunkLength = 5
    elif (tag and 0xc0) == 0x80:
      chunkLength = 2
    elif (tag and 0xc0) == 0xc0:
      produced = uint64(tag and 0x3f) + 1
    if chunkLength > markerOffset - offset:
      raise newException(ValueError, "truncated QOI data chunk")
    if produced > pixelCount - covered:
      raise newException(ValueError, "QOI data exceeds its declared dimensions")
    covered += produced
    offset += chunkLength
  if covered != pixelCount:
    raise newException(ValueError, "QOI data does not cover its declared dimensions")
  if markerOffset > 14:
    result.chunks.add data.toOpenArray(14, markerOffset - 1)

proc isQoi*(data: openArray[byte]): bool =
  try: discard parseQoi(data); true
  except ValueError: false

proc hasQoiExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".qoi"
