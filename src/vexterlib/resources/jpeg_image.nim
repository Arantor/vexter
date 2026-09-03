## Native sequential/progressive Huffman and arithmetic JPEG decoding.

import std/math
import ../archetypes/raster
import ../containers/jpeg

type
  HuffTable = object
    minimumCode, maximumCode, valueOffset: array[17, int]
    values: seq[int]

  DecodeComponent = object
    identifier, horizontal, vertical, quantization: int
    dcTable, acTable: int
    previousDc: int
    width, height, blockColumns, blockRows: int
    coefficients: seq[array[64, int16]]
    samples: seq[uint8]

  BitReader = object
    data: seq[byte]
    offset: int
    bits: uint32
    available: int

  ArithmeticDecoder = object
    data: seq[byte]
    offset, markerOffset, unreadMarker: int
    c, a: uint64
    ct: int
    dcStats: array[4, array[64, uint8]]
    acStats: array[4, array[256, uint8]]
    fixedState: uint8
    dcContext: array[4, int]

const Zigzag = [
  0, 1, 8, 16, 9, 2, 3, 10,
  17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34,
  27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36,
  29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46,
  53, 60, 61, 54, 47, 55, 62, 63]

template arithmeticState(qe, nl, nm, switchMps: untyped): uint32 =
  (uint32(qe) shl 16) or (uint32(nm) shl 8) or
    (uint32(switchMps) shl 7) or uint32(nl)

const ArithmeticStates = [
  arithmeticState(0x5a1d,1,1,1), arithmeticState(0x2586,14,2,0),
  arithmeticState(0x1114,16,3,0), arithmeticState(0x080b,18,4,0),
  arithmeticState(0x03d8,20,5,0), arithmeticState(0x01da,23,6,0),
  arithmeticState(0x00e5,25,7,0), arithmeticState(0x006f,28,8,0),
  arithmeticState(0x0036,30,9,0), arithmeticState(0x001a,33,10,0),
  arithmeticState(0x000d,35,11,0), arithmeticState(0x0006,9,12,0),
  arithmeticState(0x0003,10,13,0), arithmeticState(0x0001,12,13,0),
  arithmeticState(0x5a7f,15,15,1), arithmeticState(0x3f25,36,16,0),
  arithmeticState(0x2cf2,38,17,0), arithmeticState(0x207c,39,18,0),
  arithmeticState(0x17b9,40,19,0), arithmeticState(0x1182,42,20,0),
  arithmeticState(0x0cef,43,21,0), arithmeticState(0x09a1,45,22,0),
  arithmeticState(0x072f,46,23,0), arithmeticState(0x055c,48,24,0),
  arithmeticState(0x0406,49,25,0), arithmeticState(0x0303,51,26,0),
  arithmeticState(0x0240,52,27,0), arithmeticState(0x01b1,54,28,0),
  arithmeticState(0x0144,56,29,0), arithmeticState(0x00f5,57,30,0),
  arithmeticState(0x00b7,59,31,0), arithmeticState(0x008a,60,32,0),
  arithmeticState(0x0068,62,33,0), arithmeticState(0x004e,63,34,0),
  arithmeticState(0x003b,32,35,0), arithmeticState(0x002c,33,9,0),
  arithmeticState(0x5ae1,37,37,1), arithmeticState(0x484c,64,38,0),
  arithmeticState(0x3a0d,65,39,0), arithmeticState(0x2ef1,67,40,0),
  arithmeticState(0x261f,68,41,0), arithmeticState(0x1f33,69,42,0),
  arithmeticState(0x19a8,70,43,0), arithmeticState(0x1518,72,44,0),
  arithmeticState(0x1177,73,45,0), arithmeticState(0x0e74,74,46,0),
  arithmeticState(0x0bfb,75,47,0), arithmeticState(0x09f8,77,48,0),
  arithmeticState(0x0861,78,49,0), arithmeticState(0x0706,79,50,0),
  arithmeticState(0x05cd,48,51,0), arithmeticState(0x04de,50,52,0),
  arithmeticState(0x040f,50,53,0), arithmeticState(0x0363,51,54,0),
  arithmeticState(0x02d4,52,55,0), arithmeticState(0x025c,53,56,0),
  arithmeticState(0x01f8,54,57,0), arithmeticState(0x01a4,55,58,0),
  arithmeticState(0x0160,56,59,0), arithmeticState(0x0125,57,60,0),
  arithmeticState(0x00f6,58,61,0), arithmeticState(0x00cb,59,62,0),
  arithmeticState(0x00ab,61,63,0), arithmeticState(0x008f,61,32,0),
  arithmeticState(0x5b12,65,65,1), arithmeticState(0x4d04,80,66,0),
  arithmeticState(0x412c,81,67,0), arithmeticState(0x37d8,82,68,0),
  arithmeticState(0x2fe8,83,69,0), arithmeticState(0x293c,84,70,0),
  arithmeticState(0x2379,86,71,0), arithmeticState(0x1edf,87,72,0),
  arithmeticState(0x1aa9,87,73,0), arithmeticState(0x174e,72,74,0),
  arithmeticState(0x1424,72,75,0), arithmeticState(0x119c,74,76,0),
  arithmeticState(0x0f6b,74,77,0), arithmeticState(0x0d51,75,78,0),
  arithmeticState(0x0bb6,77,79,0), arithmeticState(0x0a40,77,48,0),
  arithmeticState(0x5832,80,81,1), arithmeticState(0x4d1c,88,82,0),
  arithmeticState(0x438e,89,83,0), arithmeticState(0x3bdd,90,84,0),
  arithmeticState(0x34ee,91,85,0), arithmeticState(0x2eae,92,86,0),
  arithmeticState(0x299a,93,87,0), arithmeticState(0x2516,86,71,0),
  arithmeticState(0x5570,88,89,1), arithmeticState(0x4ca9,95,90,0),
  arithmeticState(0x44d9,96,91,0), arithmeticState(0x3e22,97,92,0),
  arithmeticState(0x3824,99,93,0), arithmeticState(0x32b4,99,94,0),
  arithmeticState(0x2e17,93,86,0), arithmeticState(0x56a8,95,96,1),
  arithmeticState(0x4f46,101,97,0), arithmeticState(0x47e5,102,98,0),
  arithmeticState(0x41cf,103,99,0), arithmeticState(0x3c3d,104,100,0),
  arithmeticState(0x375e,99,93,0), arithmeticState(0x5231,105,102,0),
  arithmeticState(0x4c0f,106,103,0), arithmeticState(0x4639,107,104,0),
  arithmeticState(0x415e,103,99,0), arithmeticState(0x5627,105,106,1),
  arithmeticState(0x50e7,108,107,0), arithmeticState(0x4b85,109,103,0),
  arithmeticState(0x5597,110,109,0), arithmeticState(0x504f,111,107,0),
  arithmeticState(0x5a10,110,111,1), arithmeticState(0x5522,112,109,0),
  arithmeticState(0x59eb,112,111,1), arithmeticState(0x5a1d,113,113,0)]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc nextEntropyByte(reader: var BitReader): int =
  if reader.offset >= reader.data.len:
    raise newException(ValueError, "truncated JPEG entropy data")
  result = int(reader.data[reader.offset]); inc reader.offset
  if result != 0xff: return
  while reader.offset < reader.data.len and reader.data[reader.offset] == 0xff:
    inc reader.offset
  if reader.offset >= reader.data.len:
    raise newException(ValueError, "truncated JPEG entropy marker")
  let marker = int(reader.data[reader.offset]); inc reader.offset
  if marker == 0x00: return 0xff
  raise newException(ValueError,
    "unexpected JPEG marker inside entropy data: " & $marker)

proc readBits(reader: var BitReader, count: int): int =
  while reader.available < count:
    reader.bits = (reader.bits shl 8) or uint32(reader.nextEntropyByte)
    reader.available += 8
  reader.available -= count
  result = int((reader.bits shr reader.available) and
    uint32((1 shl count) - 1))
  if reader.available == 0: reader.bits = 0
  else: reader.bits = reader.bits and uint32((1 shl reader.available) - 1)

proc decode(table: HuffTable, reader: var BitReader): int =
  var code = 0
  for length in 1 .. 16:
    code = (code shl 1) or reader.readBits(1)
    if table.maximumCode[length] >= 0 and
        code >= table.minimumCode[length] and code <= table.maximumCode[length]:
      return table.values[table.valueOffset[length] +
        code - table.minimumCode[length]]
  raise newException(ValueError, "invalid JPEG Huffman code")

proc extendedValue(reader: var BitReader, count: int): int =
  if count == 0: return 0
  result = reader.readBits(count)
  if result < (1 shl (count - 1)):
    result -= (1 shl count) - 1

proc consumeRestart(reader: var BitReader, expected: int) =
  reader.available = 0
  reader.bits = 0
  if reader.offset >= reader.data.len or reader.data[reader.offset] != 0xff:
    raise newException(ValueError, "JPEG restart marker is missing")
  while reader.offset < reader.data.len and reader.data[reader.offset] == 0xff:
    inc reader.offset
  if reader.offset >= reader.data.len or
      int(reader.data[reader.offset]) != 0xd0 + expected:
    raise newException(ValueError, "unexpected JPEG restart marker")
  inc reader.offset

proc nextArithmeticByte(decoder: var ArithmeticDecoder): int =
  if decoder.unreadMarker != 0: return 0
  if decoder.offset >= decoder.data.len:
    raise newException(ValueError, "truncated JPEG arithmetic data")
  result = int(decoder.data[decoder.offset]); inc decoder.offset
  if result != 0xff: return
  decoder.markerOffset = decoder.offset - 1
  while decoder.offset < decoder.data.len and
      decoder.data[decoder.offset] == 0xff:
    inc decoder.offset
  if decoder.offset >= decoder.data.len:
    raise newException(ValueError, "truncated JPEG arithmetic marker")
  let marker = int(decoder.data[decoder.offset]); inc decoder.offset
  if marker == 0:
    decoder.markerOffset = -1
    return 0xff
  decoder.unreadMarker = marker
  result = 0

proc decodeArithmetic(decoder: var ArithmeticDecoder,
    state: var uint8): int =
  while decoder.a < 0x8000'u64:
    dec decoder.ct
    if decoder.ct < 0:
      decoder.c = (decoder.c shl 8) or
        uint64(decoder.nextArithmeticByte)
      decoder.ct += 8
      if decoder.ct < 0:
        inc decoder.ct
        if decoder.ct == 0: decoder.a = 0x8000
    decoder.a = decoder.a shl 1
  let packed = ArithmeticStates[int(state and 0x7f)]
  let qe = uint64(packed shr 16)
  let nextLps = uint8(packed and 0xff)
  let nextMps = uint8((packed shr 8) and 0xff)
  var symbol = state
  let interval = decoder.a - qe
  decoder.a = interval
  let boundary = interval shl decoder.ct
  if decoder.c >= boundary:
    decoder.c -= boundary
    decoder.a = qe
    if interval < qe:
      state = (state and 0x80) xor nextMps
    else:
      state = (state and 0x80) xor nextLps
      symbol = symbol xor 0x80
  elif decoder.a < 0x8000:
    if decoder.a < qe:
      state = (state and 0x80) xor nextLps
      symbol = symbol xor 0x80
    else:
      state = (state and 0x80) xor nextMps
  result = int(symbol shr 7)

proc resetArithmeticCoder(decoder: var ArithmeticDecoder) =
  decoder.c = 0
  decoder.a = 0
  decoder.ct = -16
  decoder.unreadMarker = 0
  decoder.markerOffset = -1

proc arithmeticMarkerOffset(decoder: var ArithmeticDecoder): int =
  if decoder.unreadMarker != 0: return decoder.markerOffset
  var offset = decoder.offset
  while offset < decoder.data.len:
    if decoder.data[offset] != 0xff:
      inc offset
      continue
    let markerOffset = offset
    while offset < decoder.data.len and decoder.data[offset] == 0xff:
      inc offset
    if offset >= decoder.data.len:
      raise newException(ValueError, "truncated JPEG arithmetic marker")
    if decoder.data[offset] == 0:
      inc offset
      continue
    return markerOffset
  raise newException(ValueError, "JPEG arithmetic scan has no terminating marker")

proc inverseDct(coefficients: array[64, int],
    basis: array[8, array[8, float]]): array[64, uint8] =
  var nonzero: seq[int]
  for index, coefficient in coefficients:
    if coefficient != 0: nonzero.add index
  if nonzero.len == 0:
    for sample in result.mitems: sample = 128
    return
  if nonzero.len == 1 and nonzero[0] == 0:
    let sample = uint8(clamp(int(round(float(coefficients[0]) / 8.0)) +
      128, 0, 255))
    for value in result.mitems: value = sample
    return
  # Quantized JPEG blocks are normally sparse. Summing only their populated
  # coefficients avoids doing a fixed 1,024 multiply-adds for every block in
  # ordinary photographs, while dense blocks retain the separable transform.
  if nonzero.len <= 16:
    for y in 0 ..< 8:
      for x in 0 ..< 8:
        var value = 0.0
        for index in nonzero:
          let u = index mod 8
          let v = index div 8
          value += basis[x][u] * basis[y][v] * float(coefficients[index])
        result[y * 8 + x] = uint8(clamp(int(round(value / 4.0)) +
          128, 0, 255))
    return
  var intermediate: array[64, float]
  for v in 0 ..< 8:
    for x in 0 ..< 8:
      var value = 0.0
      for u in 0 ..< 8:
        value += basis[x][u] * float(coefficients[v * 8 + u])
      intermediate[v * 8 + x] = value
  for y in 0 ..< 8:
    for x in 0 ..< 8:
      var value = 0.0
      for v in 0 ..< 8:
        value += basis[y][v] * intermediate[v * 8 + x]
      let sample = int(round(value / 4.0)) + 128
      result[y * 8 + x] = uint8(clamp(sample, 0, 255))

proc decodeSequentialBlock(component: var DecodeComponent,
    coefficientBlock: var array[64, int16],
    dcTables, acTables: array[4, HuffTable],
    dcPresent, acPresent: array[4, bool], reader: var BitReader) =
  if component.dcTable notin 0 .. 3 or not dcPresent[component.dcTable] or
      component.acTable notin 0 .. 3 or not acPresent[component.acTable]:
    raise newException(ValueError, "JPEG scan references a missing table")
  let dcLength = dcTables[component.dcTable].decode(reader)
  if dcLength > 11:
    raise newException(ValueError, "invalid JPEG DC coefficient length")
  component.previousDc += reader.extendedValue(dcLength)
  coefficientBlock[0] = int16(component.previousDc)
  var zig = 1
  while zig < 64:
    let symbol = acTables[component.acTable].decode(reader)
    if symbol == 0: break
    let run = symbol shr 4
    let size = symbol and 0x0f
    if size == 0:
      if run != 15:
        raise newException(ValueError, "invalid JPEG AC run")
      zig += 16
    else:
      zig += run
      if zig >= 64 or size > 10:
        raise newException(ValueError, "invalid JPEG AC coefficient")
      coefficientBlock[Zigzag[zig]] = int16(reader.extendedValue(size))
      inc zig

proc refineCoefficient(value: var int16, bit, magnitude: int) {.inline.} =
  let adjustment = int16(magnitude)
  if bit != 0 and (value and adjustment) == 0:
    if value >= 0: value += adjustment else: value -= adjustment

proc decodeArithmeticDc(decoder: var ArithmeticDecoder,
    component: var DecodeComponent, componentIndex, table, lower, upper: int): int =
  var stateIndex = decoder.dcContext[componentIndex]
  if decoder.decodeArithmetic(decoder.dcStats[table][stateIndex]) != 0:
    let sign = decoder.decodeArithmetic(decoder.dcStats[table][stateIndex + 1])
    stateIndex += 2 + sign
    var magnitude = decoder.decodeArithmetic(decoder.dcStats[table][stateIndex])
    if magnitude != 0:
      stateIndex = 20
      while decoder.decodeArithmetic(decoder.dcStats[table][stateIndex]) != 0:
        magnitude = magnitude shl 1
        if magnitude == 0x8000:
          raise newException(ValueError, "invalid JPEG arithmetic DC magnitude")
        inc stateIndex
    if magnitude < ((1 shl lower) shr 1):
      decoder.dcContext[componentIndex] = 0
    elif magnitude > ((1 shl upper) shr 1):
      decoder.dcContext[componentIndex] = 12 + sign * 4
    else:
      decoder.dcContext[componentIndex] = 4 + sign * 4
    var value = magnitude
    stateIndex += 14
    while magnitude != 0:
      magnitude = magnitude shr 1
      if magnitude != 0 and
          decoder.decodeArithmetic(decoder.dcStats[table][stateIndex]) != 0:
        value = value or magnitude
    inc value
    if sign != 0: value = -value
    component.previousDc += value
  else:
    decoder.dcContext[componentIndex] = 0
  component.previousDc

proc decodeArithmeticAcFirst(decoder: var ArithmeticDecoder,
    coefficientBlock: var array[64, int16], table, spectralStart,
    spectralEnd, successiveLow, conditioning: int) =
  var zig = spectralStart - 1
  while true:
    var stateIndex = 3 * zig
    if decoder.decodeArithmetic(decoder.acStats[table][stateIndex]) != 0:
      break
    while true:
      inc zig
      if decoder.decodeArithmetic(decoder.acStats[table][stateIndex + 1]) != 0:
        break
      stateIndex += 3
      if zig >= spectralEnd:
        raise newException(ValueError, "invalid JPEG arithmetic AC run")
    let sign = decoder.decodeArithmetic(decoder.fixedState)
    stateIndex += 2
    var magnitude = decoder.decodeArithmetic(decoder.acStats[table][stateIndex])
    if magnitude != 0 and
        decoder.decodeArithmetic(decoder.acStats[table][stateIndex]) != 0:
      magnitude = magnitude shl 1
      stateIndex = if zig <= conditioning: 189 else: 217
      while decoder.decodeArithmetic(decoder.acStats[table][stateIndex]) != 0:
        magnitude = magnitude shl 1
        if magnitude == 0x8000:
          raise newException(ValueError, "invalid JPEG arithmetic AC magnitude")
        inc stateIndex
    var value = magnitude
    stateIndex += 14
    while magnitude != 0:
      magnitude = magnitude shr 1
      if magnitude != 0 and
          decoder.decodeArithmetic(decoder.acStats[table][stateIndex]) != 0:
        value = value or magnitude
    inc value
    if sign != 0: value = -value
    coefficientBlock[Zigzag[zig]] = int16(value shl successiveLow)
    if zig >= spectralEnd: break

proc refineArithmeticAc(decoder: var ArithmeticDecoder,
    coefficientBlock: var array[64, int16], table, spectralStart,
    spectralEnd, successiveLow: int) =
  let positive = int16(1 shl successiveLow)
  let negative = -positive
  var previousEnd = spectralEnd
  while previousEnd > 0 and coefficientBlock[Zigzag[previousEnd]] == 0:
    dec previousEnd
  var zig = spectralStart - 1
  while true:
    var stateIndex = 3 * zig
    if zig >= previousEnd and
        decoder.decodeArithmetic(decoder.acStats[table][stateIndex]) != 0:
      break
    while true:
      inc zig
      let natural = Zigzag[zig]
      if coefficientBlock[natural] != 0:
        if decoder.decodeArithmetic(decoder.acStats[table][stateIndex + 2]) != 0:
          if coefficientBlock[natural] < 0:
            coefficientBlock[natural] += negative
          else:
            coefficientBlock[natural] += positive
        break
      if decoder.decodeArithmetic(decoder.acStats[table][stateIndex + 1]) != 0:
        coefficientBlock[natural] =
          if decoder.decodeArithmetic(decoder.fixedState) != 0:
            negative else: positive
        break
      stateIndex += 3
      if zig >= spectralEnd:
        raise newException(ValueError, "invalid JPEG arithmetic AC refinement")
    if zig >= spectralEnd: break

proc applyJpegOrientation*(image: VextTrueColourImage,
    orientation: int): VextTrueColourImage =
  if orientation == 1: return image
  let swapped = orientation in 5 .. 8
  result.width = if swapped: image.height else: image.width
  result.height = if swapped: image.width else: image.height
  result.pixels = newSeq[VextRgb](result.width * result.height)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let (targetX, targetY) = case orientation
        of 2: (image.width - 1 - x, y)
        of 3: (image.width - 1 - x, image.height - 1 - y)
        of 4: (x, image.height - 1 - y)
        of 5: (y, x)
        of 6: (image.height - 1 - y, x)
        of 7: (image.height - 1 - y, image.width - 1 - x)
        of 8: (y, image.width - 1 - x)
        else: (x, y)
      result.pixels[targetY * result.width + targetX] =
        image.pixels[y * image.width + x]

proc decodeJpeg*(source: JpegSource): VextRaster =
  let supportError = source.jpegDecodeSupportError
  if supportError.len > 0:
    raise newException(ValueError, supportError)
  var quantization: array[4, array[64, int]]
  var quantPresent: array[4, bool]
  var dcTables, acTables: array[4, HuffTable]
  var dcPresent, acPresent: array[4, bool]
  var arithmeticDcLower = [0, 0, 0, 0]
  var arithmeticDcUpper = [1, 1, 1, 1]
  var arithmeticAcConditioning = [5, 5, 5, 5]
  var arithmeticDecoder = ArithmeticDecoder(data: source.data,
    markerOffset: -1, fixedState: 113)
  var components: seq[DecodeComponent]
  var maxHorizontal, maxVertical = 1
  for item in source.components:
    maxHorizontal = max(maxHorizontal, item.horizontalSampling)
    maxVertical = max(maxVertical, item.verticalSampling)
    components.add DecodeComponent(identifier: item.identifier,
      horizontal: item.horizontalSampling, vertical: item.verticalSampling,
      quantization: item.quantizationTable)

  let mcuColumns = (source.width + maxHorizontal * 8 - 1) div
    (maxHorizontal * 8)
  let mcuRows = (source.height + maxVertical * 8 - 1) div (maxVertical * 8)
  for component in components.mitems:
    component.blockColumns = mcuColumns * component.horizontal
    component.blockRows = mcuRows * component.vertical
    component.width = component.blockColumns * 8
    component.height = component.blockRows * 8
    component.coefficients = newSeq[array[64, int16]](
      component.blockColumns * component.blockRows)

  var restartInterval = 0
  var sawScan = false
  let data = source.data
  var offset = 2
  while offset < data.len:
    if data[offset] != 0xff:
      raise newException(ValueError, "JPEG marker prefix was expected")
    while offset < data.len and data[offset] == 0xff: inc offset
    if offset >= data.len: break
    let marker = int(data[offset]); inc offset
    if marker == 0xd9: break
    if marker in 0xd0 .. 0xd8 or marker == 0x01: continue
    if offset + 2 > data.len:
      raise newException(ValueError, "truncated JPEG segment")
    let length = data.beWord(offset)
    if length < 2 or offset > data.len - length:
      raise newException(ValueError, "invalid JPEG segment length")
    let start = offset + 2
    let finish = offset + length
    case marker
    of 0xdb:
      var item = start
      while item < finish:
        let precision = int(data[item]) shr 4
        let table = int(data[item]) and 0x0f
        inc item
        if table notin 0 .. 3 or precision notin 0 .. 1:
          raise newException(ValueError, "unsupported JPEG quantization table")
        let bytes = if precision == 0: 64 else: 128
        if item > finish - bytes:
          raise newException(ValueError, "truncated JPEG quantization table")
        for zig in 0 ..< 64:
          let value = if precision == 0: int(data[item + zig])
            else: data.beWord(item + zig * 2)
          quantization[table][Zigzag[zig]] = value
        quantPresent[table] = true
        item += bytes
    of 0xc4:
      var item = start
      while item < finish:
        let kind = int(data[item]) shr 4
        let table = int(data[item]) and 0x0f
        inc item
        if kind notin 0 .. 1 or table notin 0 .. 3 or item > finish - 16:
          raise newException(ValueError, "invalid JPEG Huffman table")
        var counts: array[16, int]
        var total = 0
        for index in 0 ..< 16:
          counts[index] = int(data[item + index]); total += counts[index]
        item += 16
        if total > 256 or item > finish - total:
          raise newException(ValueError, "truncated JPEG Huffman values")
        if total == 0:
          raise newException(ValueError, "empty JPEG Huffman table")
        var tableValue: HuffTable
        for length in 0 .. 16: tableValue.maximumCode[length] = -1
        var code = 0
        var valueIndex = 0
        for length in 1 .. 16:
          if code + counts[length - 1] > (1 shl length):
            raise newException(ValueError, "oversubscribed JPEG Huffman table")
          if counts[length - 1] > 0:
            tableValue.minimumCode[length] = code
            tableValue.maximumCode[length] = code + counts[length - 1] - 1
            tableValue.valueOffset[length] = valueIndex
            for unused in 0 ..< counts[length - 1]:
              tableValue.values.add int(data[item + valueIndex])
              inc code; inc valueIndex
          code = code shl 1
        if kind == 0:
          dcTables[table] = tableValue; dcPresent[table] = true
        else:
          acTables[table] = tableValue; acPresent[table] = true
        item += total
    of 0xdd:
      if length != 4:
        raise newException(ValueError, "invalid JPEG restart interval")
      restartInterval = data.beWord(start)
    of 0xcc:
      if (length - 2) mod 2 != 0:
        raise newException(ValueError, "invalid JPEG arithmetic conditioning table")
      var item = start
      while item < finish:
        let table = int(data[item])
        let value = int(data[item + 1])
        if table in 0 .. 3:
          arithmeticDcLower[table] = value and 0x0f
          arithmeticDcUpper[table] = value shr 4
          if arithmeticDcLower[table] > arithmeticDcUpper[table]:
            raise newException(ValueError,
              "invalid JPEG arithmetic DC conditioning")
        elif table in 0x10 .. 0x13:
          if value > 63:
            raise newException(ValueError,
              "invalid JPEG arithmetic AC conditioning")
          arithmeticAcConditioning[table - 0x10] = value
        else:
          raise newException(ValueError,
            "invalid JPEG arithmetic conditioning table index")
        item += 2
    of 0xda:
      let count = int(data[start])
      if count < 1 or count > components.len or length != 6 + count * 2:
        raise newException(ValueError, "invalid JPEG scan header")
      var scanComponents: seq[int]
      for index in 0 ..< count:
        let identifier = int(data[start + 1 + index * 2])
        var componentIndex = -1
        for candidate, component in components:
          if component.identifier == identifier: componentIndex = candidate
        if componentIndex < 0:
          raise newException(ValueError, "JPEG scan references an unknown component")
        if componentIndex in scanComponents:
          raise newException(ValueError, "duplicate JPEG scan component")
        scanComponents.add componentIndex
        let tables = int(data[start + 2 + index * 2])
        if (tables shr 4) notin 0 .. 3 or (tables and 0x0f) notin 0 .. 3:
          raise newException(ValueError, "invalid JPEG scan table selector")
        components[componentIndex].dcTable = tables shr 4
        components[componentIndex].acTable = tables and 0x0f
      let spectralStart = int(data[start + 1 + count * 2])
      let spectralEnd = int(data[start + 2 + count * 2])
      let approximation = int(data[start + 3 + count * 2])
      let successiveHigh = approximation shr 4
      let successiveLow = approximation and 0x0f
      let arithmetic = source.jpegCodingName == "arithmetic"
      let progressive = source.isProgressive
      if not progressive and (spectralStart != 0 or spectralEnd != 63 or
          successiveHigh != 0 or successiveLow != 0):
        raise newException(ValueError, "unsupported sequential JPEG scan parameters")
      if progressive:
        if spectralStart == 0:
          if spectralEnd != 0:
            raise newException(ValueError, "invalid progressive JPEG DC scan")
        elif spectralStart > spectralEnd or spectralEnd > 63 or count != 1:
          raise newException(ValueError, "invalid progressive JPEG AC scan")
        if successiveHigh != 0 and successiveLow != successiveHigh - 1:
          raise newException(ValueError,
            "invalid progressive JPEG successive approximation")
        if successiveLow > 13:
          raise newException(ValueError, "invalid progressive JPEG bit position")

      var reader = BitReader(data: data, offset: finish)
      if arithmetic:
        arithmeticDecoder.offset = finish
        arithmeticDecoder.resetArithmeticCoder
        for componentIndex in scanComponents:
          let component = components[componentIndex]
          if not progressive or (spectralStart == 0 and successiveHigh == 0):
            arithmeticDecoder.dcStats[component.dcTable] = default(
              array[64, uint8])
            arithmeticDecoder.dcContext[componentIndex] = 0
            components[componentIndex].previousDc = 0
          if (not progressive and spectralEnd != 0) or
              (progressive and spectralStart != 0):
            arithmeticDecoder.acStats[component.acTable] = default(
              array[256, uint8])
      var scanMcuColumns, scanMcuRows: int
      if count > 1:
        scanMcuColumns = mcuColumns
        scanMcuRows = mcuRows
      else:
        let component = components[scanComponents[0]]
        scanMcuColumns = (source.width * component.horizontal +
          maxHorizontal * 8 - 1) div (maxHorizontal * 8)
        scanMcuRows = (source.height * component.vertical +
          maxVertical * 8 - 1) div (maxVertical * 8)
      var eobRun = 0
      var restart = 0
      var mcu = 0
      for scanY in 0 ..< scanMcuRows:
        for scanX in 0 ..< scanMcuColumns:
          if restartInterval > 0 and mcu > 0 and mcu mod restartInterval == 0:
            if arithmetic:
              let restartOffset = arithmeticDecoder.arithmeticMarkerOffset
              if restartOffset + 1 >= data.len or
                  int(data[restartOffset + 1]) != 0xd0 + restart:
                raise newException(ValueError,
                  "unexpected JPEG arithmetic restart marker")
              arithmeticDecoder.offset = restartOffset + 2
              arithmeticDecoder.resetArithmeticCoder
              for componentIndex in scanComponents:
                let component = components[componentIndex]
                if not progressive or
                    (spectralStart == 0 and successiveHigh == 0):
                  arithmeticDecoder.dcStats[component.dcTable] = default(
                    array[64, uint8])
                  arithmeticDecoder.dcContext[componentIndex] = 0
                if (not progressive and spectralEnd != 0) or
                    (progressive and spectralStart != 0):
                  arithmeticDecoder.acStats[component.acTable] = default(
                    array[256, uint8])
            else:
              reader.consumeRestart(restart)
            restart = (restart + 1) and 7
            eobRun = 0
            for component in components.mitems: component.previousDc = 0
          for componentIndex in scanComponents:
            var component = addr components[componentIndex]
            let verticalBlocks = if count > 1: component[].vertical else: 1
            let horizontalBlocks = if count > 1: component[].horizontal else: 1
            for vertical in 0 ..< verticalBlocks:
              for horizontal in 0 ..< horizontalBlocks:
                let blockX = scanX * horizontalBlocks + horizontal
                let blockY = scanY * verticalBlocks + vertical
                if blockX >= component[].blockColumns or
                    blockY >= component[].blockRows:
                  raise newException(ValueError, "JPEG scan block is outside frame")
                var coefficientBlock = addr component[].coefficients[
                  blockY * component[].blockColumns + blockX]
                if arithmetic and not progressive:
                  let dc = arithmeticDecoder.decodeArithmeticDc(component[],
                    componentIndex, component[].dcTable,
                    arithmeticDcLower[component[].dcTable],
                    arithmeticDcUpper[component[].dcTable])
                  coefficientBlock[][0] = int16(dc)
                  arithmeticDecoder.decodeArithmeticAcFirst(coefficientBlock[],
                    component[].acTable, 1, 63, 0,
                    arithmeticAcConditioning[component[].acTable])
                elif not progressive:
                  component[].decodeSequentialBlock(coefficientBlock[], dcTables, acTables,
                    dcPresent, acPresent, reader)
                elif spectralStart == 0:
                  if successiveHigh == 0:
                    if arithmetic:
                      coefficientBlock[][0] = int16(
                        arithmeticDecoder.decodeArithmeticDc(component[],
                          componentIndex, component[].dcTable,
                          arithmeticDcLower[component[].dcTable],
                          arithmeticDcUpper[component[].dcTable]) shl
                        successiveLow)
                    else:
                      if component[].dcTable notin 0 .. 3 or
                          not dcPresent[component[].dcTable]:
                        raise newException(ValueError,
                          "JPEG scan references a missing DC table")
                      let size = dcTables[component[].dcTable].decode(reader)
                      if size > 11:
                        raise newException(ValueError,
                          "invalid JPEG DC coefficient length")
                      component[].previousDc += reader.extendedValue(size)
                      coefficientBlock[][0] = int16(
                        component[].previousDc shl successiveLow)
                  elif arithmetic:
                    if arithmeticDecoder.decodeArithmetic(
                        arithmeticDecoder.fixedState) != 0:
                      coefficientBlock[][0] = coefficientBlock[][0] or
                        int16(1 shl successiveLow)
                  elif reader.readBits(1) != 0:
                    coefficientBlock[][0] = coefficientBlock[][0] or
                      int16(1 shl successiveLow)
                else:
                  if arithmetic:
                    if successiveHigh == 0:
                      arithmeticDecoder.decodeArithmeticAcFirst(
                        coefficientBlock[], component[].acTable, spectralStart,
                        spectralEnd, successiveLow,
                        arithmeticAcConditioning[component[].acTable])
                    else:
                      arithmeticDecoder.refineArithmeticAc(coefficientBlock[],
                        component[].acTable, spectralStart, spectralEnd,
                        successiveLow)
                    continue
                  elif component[].acTable notin 0 .. 3 or
                      not acPresent[component[].acTable]:
                    raise newException(ValueError,
                      "JPEG scan references a missing AC table")
                  let table = acTables[component[].acTable]
                  let magnitude = 1 shl successiveLow
                  if successiveHigh == 0:
                    if eobRun > 0:
                      dec eobRun
                    else:
                      var zig = spectralStart
                      while zig <= spectralEnd:
                        let symbol = table.decode(reader)
                        let run = symbol shr 4
                        let size = symbol and 0x0f
                        if size != 0:
                          if size > 10:
                            raise newException(ValueError,
                              "invalid progressive JPEG AC coefficient")
                          zig += run
                          if zig > spectralEnd:
                            raise newException(ValueError,
                              "progressive JPEG AC run exceeds scan band " &
                              $spectralStart & ".." & $spectralEnd & " at MCU " &
                              $mcu)
                          coefficientBlock[][Zigzag[zig]] =
                            int16(reader.extendedValue(size) * magnitude)
                        elif run != 15:
                          eobRun = (1 shl run) + reader.readBits(run) - 1
                          break
                        else:
                          zig += 15
                        inc zig
                  else:
                    var zig = spectralStart
                    if eobRun == 0:
                      while zig <= spectralEnd:
                        let symbol = table.decode(reader)
                        var run = symbol shr 4
                        let size = symbol and 0x0f
                        var newValue = 0'i16
                        if size != 0:
                          if size != 1:
                            raise newException(ValueError,
                              "invalid progressive JPEG AC refinement")
                          newValue = if reader.readBits(1) != 0:
                            int16(magnitude) else: -int16(magnitude)
                        elif run != 15:
                          eobRun = (1 shl run) + reader.readBits(run)
                          break
                        while zig <= spectralEnd:
                          let natural = Zigzag[zig]
                          if coefficientBlock[][natural] != 0:
                            coefficientBlock[][natural].refineCoefficient(
                              reader.readBits(1), magnitude)
                          else:
                            dec run
                            if run < 0: break
                          inc zig
                        if newValue != 0:
                          if zig > spectralEnd:
                            raise newException(ValueError,
                              "progressive JPEG AC refinement run exceeds scan band " &
                              $spectralStart & ".." & $spectralEnd & " at MCU " &
                              $mcu & " with run " & $run)
                          coefficientBlock[][Zigzag[zig]] = newValue
                        inc zig
                    if eobRun > 0:
                      while zig <= spectralEnd:
                        let natural = Zigzag[zig]
                        if coefficientBlock[][natural] != 0:
                          coefficientBlock[][natural].refineCoefficient(
                            reader.readBits(1), magnitude)
                        inc zig
                      dec eobRun
          inc mcu
      if arithmetic:
        offset = arithmeticDecoder.arithmeticMarkerOffset
      else:
        reader.available = 0
        reader.bits = 0
        offset = reader.offset
      sawScan = true
      continue
    else: discard
    offset = finish
  if not sawScan:
    raise newException(ValueError, "JPEG scan header was not found")

  for component in components.mitems:
    component.samples = newSeq[uint8](component.width * component.height)
  var basis: array[8, array[8, float]]
  for position in 0 ..< 8:
    for frequency in 0 ..< 8:
      let scale = if frequency == 0: 1.0 / sqrt(2.0) else: 1.0
      basis[position][frequency] = scale *
        cos((float(2 * position + 1) * float(frequency) * PI) / 16.0)
  for component in components.mitems:
    if component.quantization notin 0 .. 3 or
        not quantPresent[component.quantization]:
      raise newException(ValueError, "JPEG component references a missing table")
    for blockY in 0 ..< component.blockRows:
      for blockX in 0 ..< component.blockColumns:
        var dequantized: array[64, int]
        let coefficients = component.coefficients[
          blockY * component.blockColumns + blockX]
        for index in 0 ..< 64:
          dequantized[index] = int(coefficients[index]) *
            quantization[component.quantization][index]
        let decoded = inverseDct(dequantized, basis)
        for y in 0 ..< 8:
          for x in 0 ..< 8:
            component.samples[(blockY * 8 + y) * component.width +
              blockX * 8 + x] = decoded[y * 8 + x]

  var image = VextTrueColourImage(width: source.width, height: source.height,
    pixels: newSeq[VextRgb](source.width * source.height))
  for y in 0 ..< source.height:
    for x in 0 ..< source.width:
      if components.len == 1:
        let sampleX = x * components[0].horizontal div maxHorizontal
        let sampleY = y * components[0].vertical div maxVertical
        let value = components[0].samples[
          sampleY * components[0].width + sampleX]
        image.pixels[y * source.width + x] = VextRgb(r: value, g: value, b: value)
      else:
        var samples: array[3, int]
        for index in 0 ..< 3:
          let sampleX = x * components[index].horizontal div maxHorizontal
          let sampleY = y * components[index].vertical div maxVertical
          samples[index] = int(components[index].samples[
            sampleY * components[index].width + sampleX])
        let luminance = float(samples[0])
        let blueDifference = float(samples[1] - 128)
        let redDifference = float(samples[2] - 128)
        image.pixels[y * source.width + x] = VextRgb(
          r: uint8(clamp(int(round(luminance + 1.402 * redDifference)), 0, 255)),
          g: uint8(clamp(int(round(luminance - 0.344136 * blueDifference -
            0.714136 * redDifference)), 0, 255)),
          b: uint8(clamp(int(round(luminance + 1.772 * blueDifference)), 0, 255)))
  VextRaster(kind: vrkTrueColourImage,
    trueColourImage: image.applyJpegOrientation(source.orientation))
