## Native baseline/extended-sequential Huffman JPEG decoding and orientation.

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
    width, height: int
    samples: seq[uint8]

  BitReader = object
    data: seq[byte]
    offset: int
    bits: uint32
    available: int

const Zigzag = [
  0, 1, 8, 16, 9, 2, 3, 10,
  17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34,
  27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36,
  29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46,
  53, 60, 61, 54, 47, 55, 62, 63]

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

proc decodeBlock(component: var DecodeComponent, blockX, blockY: int,
    quantization: array[4, array[64, int]], quantPresent: array[4, bool],
    dcTables, acTables: array[4, HuffTable],
    dcPresent, acPresent: array[4, bool], reader: var BitReader,
    basis: array[8, array[8, float]]) =
  if component.quantization notin 0 .. 3 or
      not quantPresent[component.quantization] or
      component.dcTable notin 0 .. 3 or not dcPresent[component.dcTable] or
      component.acTable notin 0 .. 3 or not acPresent[component.acTable]:
    raise newException(ValueError, "JPEG scan references a missing table")
  var coefficients: array[64, int]
  let dcLength = dcTables[component.dcTable].decode(reader)
  if dcLength > 11:
    raise newException(ValueError, "invalid JPEG DC coefficient length")
  component.previousDc += reader.extendedValue(dcLength)
  coefficients[0] = component.previousDc * quantization[component.quantization][0]
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
      continue
    zig += run
    if zig >= 64 or size > 10:
      raise newException(ValueError, "invalid JPEG AC coefficient")
    let natural = Zigzag[zig]
    coefficients[natural] = reader.extendedValue(size) *
      quantization[component.quantization][natural]
    inc zig
  let decodedBlock = inverseDct(coefficients, basis)
  for y in 0 ..< 8:
    for x in 0 ..< 8:
      let targetX = blockX * 8 + x
      let targetY = blockY * 8 + y
      if targetX < component.width and targetY < component.height:
        component.samples[targetY * component.width + targetX] =
          decodedBlock[y * 8 + x]

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
  if source.frameMarker == 0xc2:
    raise newException(ValueError,
      "progressive JPEG decoding is not implemented yet")
  var quantization: array[4, array[64, int]]
  var quantPresent: array[4, bool]
  var dcTables, acTables: array[4, HuffTable]
  var dcPresent, acPresent: array[4, bool]
  var components: seq[DecodeComponent]
  var maxHorizontal, maxVertical = 1
  for item in source.components:
    maxHorizontal = max(maxHorizontal, item.horizontalSampling)
    maxVertical = max(maxVertical, item.verticalSampling)
    components.add DecodeComponent(identifier: item.identifier,
      horizontal: item.horizontalSampling, vertical: item.verticalSampling,
      quantization: item.quantizationTable)

  var restartInterval = 0
  var entropyOffset = -1
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
    of 0xda:
      let count = int(data[start])
      if count != components.len or length != 6 + count * 2:
        raise newException(ValueError,
          "only one interleaved sequential JPEG scan is supported")
      for index in 0 ..< count:
        let identifier = int(data[start + 1 + index * 2])
        var componentIndex = -1
        for candidate, component in components:
          if component.identifier == identifier: componentIndex = candidate
        if componentIndex < 0:
          raise newException(ValueError, "JPEG scan references an unknown component")
        let tables = int(data[start + 2 + index * 2])
        components[componentIndex].dcTable = tables shr 4
        components[componentIndex].acTable = tables and 0x0f
      if data[start + 1 + count * 2] != 0 or
          data[start + 2 + count * 2] != 63 or
          data[start + 3 + count * 2] != 0:
        raise newException(ValueError, "unsupported sequential JPEG scan parameters")
      entropyOffset = finish
      break
    else: discard
    offset = finish
  if entropyOffset < 0:
    raise newException(ValueError, "JPEG scan header was not found")

  let mcuColumns = (source.width + maxHorizontal * 8 - 1) div
    (maxHorizontal * 8)
  let mcuRows = (source.height + maxVertical * 8 - 1) div (maxVertical * 8)
  for component in components.mitems:
    component.width = mcuColumns * component.horizontal * 8
    component.height = mcuRows * component.vertical * 8
    component.samples = newSeq[uint8](component.width * component.height)
  var basis: array[8, array[8, float]]
  for position in 0 ..< 8:
    for frequency in 0 ..< 8:
      let scale = if frequency == 0: 1.0 / sqrt(2.0) else: 1.0
      basis[position][frequency] = scale *
        cos((float(2 * position + 1) * float(frequency) * PI) / 16.0)
  var reader = BitReader(data: data, offset: entropyOffset)
  var mcu = 0
  var restart = 0
  for mcuY in 0 ..< mcuRows:
    for mcuX in 0 ..< mcuColumns:
      if restartInterval > 0 and mcu > 0 and mcu mod restartInterval == 0:
        reader.consumeRestart(restart)
        restart = (restart + 1) and 7
        for component in components.mitems: component.previousDc = 0
      for component in components.mitems:
        for vertical in 0 ..< component.vertical:
          for horizontal in 0 ..< component.horizontal:
            component.decodeBlock(mcuX * component.horizontal + horizontal,
              mcuY * component.vertical + vertical, quantization, quantPresent,
              dcTables, acTables, dcPresent, acPresent, reader, basis)
      inc mcu

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
