## Native JPEG/JFIF framing and bounded EXIF orientation parsing.

import std/strutils

const
  JpegTypeId* = "jpeg"
  JpegImageTypeId* = "jpeg.image"
  JpegImageResourcePath* = "/image"

type
  JpegComponent* = object
    identifier*: int
    horizontalSampling*, verticalSampling*: int
    quantizationTable*: int

  JpegSource* = object
    data*: seq[byte]
    width*, height*: int
    precision*: int
    frameMarker*: int
    components*: seq[JpegComponent]
    orientation*: int
    hasExif*: bool
    exifValid*: bool
    exifError*: string
    hasJfif*: bool
    jfifMajor*, jfifMinor*: int
    densityUnits*, xDensity*, yDensity*: int

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc tiffWord(data: openArray[byte], offset: int, little: bool): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated EXIF unsigned short")
  if little: int(data[offset]) or (int(data[offset + 1]) shl 8)
  else: (int(data[offset]) shl 8) or int(data[offset + 1])

proc tiffDword(data: openArray[byte], offset: int, little: bool): uint32 =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "truncated EXIF unsigned long")
  if little:
    uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
      (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)
  else:
    (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
      (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc parseExifOrientation(payload: openArray[byte]): int =
  if payload.len < 14:
    raise newException(ValueError, "EXIF APP1 segment is too short")
  let little = if payload[6] == byte('I') and payload[7] == byte('I'): true
    elif payload[6] == byte('M') and payload[7] == byte('M'): false
    else: raise newException(ValueError, "invalid EXIF TIFF byte order")
  if payload.tiffWord(8, little) != 42:
    raise newException(ValueError, "invalid EXIF TIFF identifier")
  let ifdRelative = payload.tiffDword(10, little)
  if ifdRelative > uint32(high(int) - 6):
    raise newException(ValueError, "EXIF IFD0 offset is too large")
  let ifd = 6 + int(ifdRelative)
  let count = payload.tiffWord(ifd, little)
  if count > 4096 or ifd + 2 > payload.len - count * 12:
    raise newException(ValueError, "invalid EXIF IFD0 bounds")
  for index in 0 ..< count:
    let entry = ifd + 2 + index * 12
    if payload.tiffWord(entry, little) != 0x0112: continue
    if payload.tiffWord(entry + 2, little) != 3 or
        payload.tiffDword(entry + 4, little) != 1:
      raise newException(ValueError, "invalid EXIF orientation field type")
    result = payload.tiffWord(entry + 8, little)
    if result notin 1 .. 8:
      raise newException(ValueError, "EXIF orientation is outside 1 through 8")
    return
  result = 1

proc parseJpeg*(data: openArray[byte]): JpegSource =
  if data.len < 4 or data[0] != 0xff or data[1] != 0xd8:
    raise newException(ValueError, "invalid JPEG start-of-image marker")
  result.data = @data
  result.orientation = 1
  var offset = 2
  var sawFrame, sawScan, sawEnd: bool
  while offset < data.len:
    if data[offset] != 0xff:
      if sawScan:
        inc offset
        continue
      raise newException(ValueError, "JPEG marker prefix was expected")
    while offset < data.len and data[offset] == 0xff: inc offset
    if offset >= data.len:
      raise newException(ValueError, "truncated JPEG marker")
    let marker = int(data[offset]); inc offset
    if marker == 0x00:
      if sawScan: continue
      raise newException(ValueError, "unexpected stuffed JPEG byte")
    if marker == 0xd9:
      sawEnd = true
      if offset != data.len:
        raise newException(ValueError, "JPEG has data after end-of-image")
      break
    if marker in 0xd0 .. 0xd8 or marker == 0x01:
      continue
    if offset + 2 > data.len:
      raise newException(ValueError, "truncated JPEG segment length")
    let length = data.beWord(offset)
    if length < 2 or offset > data.len - length:
      raise newException(ValueError, "invalid JPEG segment bounds")
    let start = offset + 2
    let finish = offset + length
    case marker
    of 0xe0:
      if length >= 16 and data[start] == byte('J') and
          data[start + 1] == byte('F') and data[start + 2] == byte('I') and
          data[start + 3] == byte('F') and data[start + 4] == 0:
        result.hasJfif = true
        result.jfifMajor = int(data[start + 5])
        result.jfifMinor = int(data[start + 6])
        result.densityUnits = int(data[start + 7])
        result.xDensity = data.beWord(start + 8)
        result.yDensity = data.beWord(start + 10)
    of 0xe1:
      if length >= 8 and data[start] == byte('E') and
          data[start + 1] == byte('x') and data[start + 2] == byte('i') and
          data[start + 3] == byte('f') and data[start + 4] == 0 and
          data[start + 5] == 0 and not result.hasExif:
        result.hasExif = true
        var payload: seq[byte]
        payload.add data.toOpenArray(start, finish - 1)
        try:
          result.orientation = parseExifOrientation(payload)
          result.exifValid = true
        except ValueError as error:
          result.exifError = error.msg
    of 0xc0, 0xc1, 0xc2:
      if sawFrame or length < 8:
        raise newException(ValueError, "invalid or duplicate JPEG frame header")
      sawFrame = true
      result.frameMarker = marker
      result.precision = int(data[start])
      result.height = data.beWord(start + 1)
      result.width = data.beWord(start + 3)
      let count = int(data[start + 5])
      if count notin [1, 3] or length != 8 + count * 3 or
          result.width <= 0 or result.height <= 0 or
          result.width > 65535 or result.height > 65535 or
          result.width > 100_000_000 div result.height:
        raise newException(ValueError, "invalid or unsupported JPEG frame dimensions")
      for index in 0 ..< count:
        let item = start + 6 + index * 3
        let sampling = int(data[item + 1])
        let horizontal = sampling shr 4
        let vertical = sampling and 0x0f
        if horizontal notin 1 .. 4 or vertical notin 1 .. 4:
          raise newException(ValueError, "invalid JPEG component sampling")
        result.components.add JpegComponent(identifier: int(data[item]),
          horizontalSampling: horizontal, verticalSampling: vertical,
          quantizationTable: int(data[item + 2]))
    of 0xda:
      sawScan = true
    else: discard
    offset = finish
  if not sawFrame or not sawScan or not sawEnd:
    raise newException(ValueError, "JPEG is missing a frame, scan, or end marker")
  if result.precision != 8 or result.frameMarker notin [0xc0, 0xc1, 0xc2]:
    raise newException(ValueError, "unsupported JPEG coding process")

proc hasJpegExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".jpg") or
    filename.toLowerAscii.endsWith(".jpeg") or
    filename.toLowerAscii.endsWith(".jpe")
