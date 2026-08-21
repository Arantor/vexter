## Structural parsing and sample extraction for NetPBM P1 through P7 images.

import std/[os, strutils]

const NetpbmTypeId* = "netpbm"

type
  NetpbmVariant* = enum
    npvPlainPbm = 1
    npvPlainPgm
    npvPlainPpm
    npvRawPbm
    npvRawPgm
    npvRawPpm
    npvPam

  NetpbmImageSource* = object
    variant*: NetpbmVariant
    width*, height*, depth*, maxValue*: int
    tupleType*: string
    samples*: seq[uint16]

  NetpbmSource* = object
    images*: seq[NetpbmImageSource]

const NetpbmWhitespace = {' ', '\t', '\r', '\n', '\v', '\f'}

proc skipTrivia(data: openArray[byte], offset: var int) =
  while offset < data.len:
    if char(data[offset]) in NetpbmWhitespace:
      inc offset
    elif data[offset] == byte('#'):
      while offset < data.len and data[offset] notin [byte('\r'), byte('\n')]:
        inc offset
    else:
      break

proc decimal(data: openArray[byte], offset: var int, name: string): int =
  skipTrivia(data, offset)
  if offset >= data.len or data[offset] notin {byte('0') .. byte('9')}:
    raise newException(ValueError, "missing NetPBM " & name)
  while offset < data.len and data[offset] in {byte('0') .. byte('9')}:
    let digit = int(data[offset] - byte('0'))
    if result > (high(int) - digit) div 10:
      raise newException(ValueError, "NetPBM " & name & " is too large")
    result = result * 10 + digit
    inc offset

proc sampleCount(width, height, depth: int): int =
  if width <= 0 or height <= 0 or depth <= 0:
    raise newException(ValueError, "NetPBM dimensions and depth must be positive")
  if width > high(int) div height or width * height > high(int) div depth:
    raise newException(ValueError, "NetPBM image dimensions exceed platform capacity")
  width * height * depth

proc rawDelimiter(data: openArray[byte], offset: var int) =
  if offset >= data.len:
    raise newException(ValueError, "missing NetPBM raster delimiter")
  if data[offset] == byte('#'):
    while offset < data.len and data[offset] notin [byte('\r'), byte('\n')]:
      inc offset
    if offset >= data.len:
      raise newException(ValueError, "missing NetPBM raster delimiter")
  if char(data[offset]) notin NetpbmWhitespace:
    raise newException(ValueError, "missing NetPBM raster delimiter")
  inc offset

proc addRawSamples(image: var NetpbmImageSource, data: openArray[byte],
    offset: var int) =
  if image.variant == npvRawPbm:
    let rowBytes = (image.width + 7) div 8
    if rowBytes > high(int) div image.height or
        rowBytes * image.height > data.len - offset:
      raise newException(ValueError, "truncated raw PBM raster")
    image.samples = newSeq[uint16](image.width * image.height)
    for y in 0 ..< image.height:
      for x in 0 ..< image.width:
        image.samples[y * image.width + x] = uint16(
          (data[offset + y * rowBytes + x div 8] shr (7 - x mod 8)) and 1)
    offset += rowBytes * image.height
    return

  let count = sampleCount(image.width, image.height, image.depth)
  let bytesPerSample = if image.maxValue < 256: 1 else: 2
  if count > high(int) div bytesPerSample or
      count * bytesPerSample > data.len - offset:
    raise newException(ValueError, "truncated raw NetPBM raster")
  image.samples = newSeq[uint16](count)
  for index in 0 ..< count:
    let value = if bytesPerSample == 1:
      int(data[offset])
    else:
      (int(data[offset]) shl 8) or int(data[offset + 1])
    if value > image.maxValue:
      raise newException(ValueError, "NetPBM sample exceeds maxval")
    image.samples[index] = uint16(value)
    offset += bytesPerSample

proc parseClassicImage(data: openArray[byte], offset: var int,
    variant: NetpbmVariant): NetpbmImageSource =
  result.variant = variant
  result.width = decimal(data, offset, "width")
  result.height = decimal(data, offset, "height")
  result.depth = if variant in [npvPlainPpm, npvRawPpm]: 3 else: 1
  result.maxValue = if variant in [npvPlainPbm, npvRawPbm]: 1
    else: decimal(data, offset, "maxval")
  discard sampleCount(result.width, result.height, result.depth)
  if result.maxValue <= 0 or result.maxValue >= 65536:
    raise newException(ValueError, "NetPBM maxval must be between 1 and 65535")

  if variant in [npvRawPbm, npvRawPgm, npvRawPpm]:
    rawDelimiter(data, offset)
    result.addRawSamples(data, offset)
  else:
    let count = sampleCount(result.width, result.height, result.depth)
    result.samples = newSeq[uint16](count)
    if variant == npvPlainPbm:
      for index in 0 ..< count:
        skipTrivia(data, offset)
        if offset >= data.len or data[offset] notin [byte('0'), byte('1')]:
          raise newException(ValueError, "invalid plain PBM raster sample")
        result.samples[index] = uint16(data[offset] - byte('0'))
        inc offset
    else:
      for index in 0 ..< count:
        let value = decimal(data, offset, "plain raster sample")
        if value > result.maxValue:
          raise newException(ValueError, "NetPBM sample exceeds maxval")
        result.samples[index] = uint16(value)

proc parsePamImage(data: openArray[byte], offset: var int): NetpbmImageSource =
  result.variant = npvPam
  var haveWidth, haveHeight, haveDepth, haveMaxValue, haveEnd: bool
  while offset < data.len:
    let lineStart = offset
    while offset < data.len and data[offset] != byte('\n'): inc offset
    if offset >= data.len:
      raise newException(ValueError, "unterminated PAM header line")
    var line = newString(offset - lineStart)
    for index in 0 ..< line.len: line[index] = char(data[lineStart + index])
    inc offset
    line = line.strip(chars = NetpbmWhitespace)
    if line.len == 0 or line[0] == '#': continue
    let space = line.find({' ', '\t', '\r', '\v', '\f'})
    let key = if space < 0: line else: line[0 ..< space]
    let value = if space < 0: "" else:
      line[space + 1 .. ^1].strip(chars = NetpbmWhitespace)
    if key.len > 8:
      raise newException(ValueError, "PAM header key exceeds eight characters")
    template required(target, seen: untyped, label: string) =
      if seen or value.len == 0:
        raise newException(ValueError, "invalid PAM " & label & " header")
      var valueOffset = 0
      var valueBytes = newSeq[byte](value.len)
      for index, item in value: valueBytes[index] = byte(item)
      target = decimal(valueBytes, valueOffset, label)
      if valueOffset != valueBytes.len:
        raise newException(ValueError, "invalid PAM " & label & " value")
      seen = true
    case key
    of "WIDTH": required(result.width, haveWidth, "WIDTH")
    of "HEIGHT": required(result.height, haveHeight, "HEIGHT")
    of "DEPTH": required(result.depth, haveDepth, "DEPTH")
    of "MAXVAL": required(result.maxValue, haveMaxValue, "MAXVAL")
    of "TUPLTYPE":
      if value.len == 0:
        raise newException(ValueError, "PAM TUPLTYPE must have a value")
      if result.tupleType.len > 0: result.tupleType.add ' '
      result.tupleType.add value
    of "ENDHDR":
      if value.len > 0 or haveEnd:
        raise newException(ValueError, "invalid PAM ENDHDR line")
      haveEnd = true
      break
    else:
      raise newException(ValueError, "unknown PAM header key: " & key)
  if not (haveWidth and haveHeight and haveDepth and haveMaxValue and haveEnd):
    raise newException(ValueError, "PAM header is missing a required line")
  discard sampleCount(result.width, result.height, result.depth)
  if result.maxValue <= 0 or result.maxValue >= 65536:
    raise newException(ValueError, "PAM maxval must be between 1 and 65535")
  result.addRawSamples(data, offset)

proc parseNetpbm*(data: openArray[byte]): NetpbmSource =
  var offset = 0
  while offset < data.len:
    if data.len - offset < 2 or data[offset] != byte('P') or
        data[offset + 1] notin {byte('1') .. byte('7')}:
      raise newException(ValueError, "invalid NetPBM magic number")
    let variant = NetpbmVariant(int(data[offset + 1] - byte('0')))
    offset += 2
    if variant == npvPam:
      if offset >= data.len or data[offset] != byte('\n'):
        raise newException(ValueError, "PAM magic number must end with newline")
      inc offset
      result.images.add parsePamImage(data, offset)
    else:
      if offset >= data.len or (char(data[offset]) notin NetpbmWhitespace and
          data[offset] != byte('#')):
        raise newException(ValueError,
          "NetPBM magic number must be followed by whitespace")
      result.images.add parseClassicImage(data, offset, variant)
    if variant in [npvPlainPbm, npvPlainPgm, npvPlainPpm]:
      let trailingStart = offset
      skipTrivia(data, offset)
      if offset != data.len:
        if variant == npvPlainPbm and trailingStart < data.len and
            char(data[trailingStart]) in NetpbmWhitespace:
          offset = data.len # Plain PBM explicitly permits whitespace-led junk.
        else:
          raise newException(ValueError, "plain NetPBM has trailing data")
      break
  if result.images.len == 0:
    raise newException(ValueError, "NetPBM contains no images")

proc isNetpbm*(data: openArray[byte]): bool =
  try: discard parseNetpbm(data); true
  except ValueError: false

proc hasNetpbmExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".pbm", ".pgm", ".ppm", ".pam", ".pnm"]
