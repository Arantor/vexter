import std/[os, unittest]
import vexterlib

proc readBytes(path: string): seq[byte] =
  for value in readFile(path): result.add byte(value)

proc word(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

proc littleWord(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc littleDword(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)
  data.add byte(value shr 16)
  data.add byte(value shr 24)

proc segment(data: var seq[byte], marker: byte, payload: openArray[byte]) =
  data.add 0xff
  data.add marker
  data.word(payload.len + 2)
  data.add payload

proc exifPayload(orientation: int, little = true): seq[byte] =
  result = @[byte('E'), byte('x'), byte('i'), byte('f'), 0'u8, 0]
  if little:
    result.add @[byte('I'), byte('I'), 42'u8, 0, 8, 0, 0, 0,
      1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0,
      byte(orientation), 0, 0, 0, 0, 0, 0, 0]
  else:
    result.add @[byte('M'), byte('M'), 0'u8, 42, 0, 0, 0, 8,
      0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1,
      0, byte(orientation), 0, 0, 0, 0, 0, 0]

proc richExifPayload(): seq[byte] =
  result = @[byte('E'), byte('x'), byte('i'), byte('f'), 0'u8, 0,
    byte('I'), byte('I'), 42, 0, 8, 0, 0, 0]
  result.littleWord(2)
  result.littleWord(0x0112); result.littleWord(3); result.littleDword(1)
  result.littleWord(1); result.littleWord(0)
  result.littleWord(0x8769); result.littleWord(4); result.littleDword(1)
  result.littleDword(38)
  result.littleDword(0)
  result.littleWord(4)
  result.littleWord(0x829a); result.littleWord(5); result.littleDword(1)
  result.littleDword(92)
  result.littleWord(0x829d); result.littleWord(5); result.littleDword(1)
  result.littleDword(100)
  result.littleWord(0x8827); result.littleWord(3); result.littleDword(1)
  result.littleWord(80); result.littleWord(0)
  result.littleWord(0x9003); result.littleWord(2); result.littleDword(20)
  result.littleDword(108)
  result.littleDword(0)
  result.littleDword(1); result.littleDword(420)
  result.littleDword(29); result.littleDword(10)
  for character in "2007:01:20 13:19:03\0": result.add byte(character)

proc withExif(data, payload: seq[byte]): seq[byte] =
  result.add data.toOpenArray(0, 1)
  result.segment(0xe1, payload)
  result.add data.toOpenArray(2, data.high)

proc exifValue(source: JpegSource, key: string): string =
  for entry in source.exifMetadata:
    if entry.key == key: return entry.value

proc metadataString(resource: VextResourceNode, key: string): string =
  for entry in resource.metadata:
    if entry.key == key and entry.value.kind == vmvkString:
      return entry.value.stringValue

proc metadataInteger(resource: VextResourceNode, key: string): int =
  for entry in resource.metadata:
    if entry.key == key and entry.value.kind == vmvkInteger:
      return entry.value.integerValue
  return -1

proc constantJpeg(width = 16, height = 8, orientation = 1,
    includeExif = false, littleExif = true): seq[byte] =
  result = @[0xff'u8, 0xd8]
  if includeExif:
    result.segment(0xe1, exifPayload(orientation, littleExif))

  var quantization = @[0'u8]
  for unused in 0 ..< 64: quantization.add 1
  result.segment(0xdb, quantization)

  var frame = @[8'u8]
  frame.word(height)
  frame.word(width)
  frame.add @[1'u8, 1, 0x11, 0]
  result.segment(0xc0, frame)

  var huffman = @[0'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  huffman.add @[0x10'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  result.segment(0xc4, huffman)

  result.segment(0xda, @[1'u8, 1, 0, 0, 63, 0])
  let blocks = ((width + 7) div 8) * ((height + 7) div 8)
  var pending = 0
  var used = 0
  for unused in 0 ..< blocks:
    pending = pending shl 2
    used += 2
    if used == 8:
      result.add byte(pending)
      pending = 0
      used = 0
  if used > 0:
    result.add byte((pending shl (8 - used)) or ((1 shl (8 - used)) - 1))
  result.add @[0xff'u8, 0xd9]

proc zeroEntropy(data: var seq[byte], blocks: int) =
  var remaining = blocks
  while remaining >= 8:
    data.add 0
    remaining -= 8
  if remaining > 0:
    data.add byte((1 shl (8 - remaining)) - 1)

proc progressiveConstantJpeg(width = 16, height = 8): seq[byte] =
  result = @[0xff'u8, 0xd8]
  var quantization = @[0'u8]
  for unused in 0 ..< 64: quantization.add 1
  result.segment(0xdb, quantization)
  var frame = @[8'u8]
  frame.word(height); frame.word(width)
  frame.add @[1'u8, 1, 0x11, 0]
  result.segment(0xc2, frame)
  var huffman = @[0'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  huffman.add @[0x10'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  result.segment(0xc4, huffman)
  let blocks = ((width + 7) div 8) * ((height + 7) div 8)
  result.segment(0xda, @[1'u8, 1, 0, 0, 0, 0])
  result.zeroEntropy(blocks)
  result.segment(0xda, @[1'u8, 1, 0, 1, 63, 0])
  result.zeroEntropy(blocks)
  result.add @[0xff'u8, 0xd9]

proc separateComponentConstantJpeg(): seq[byte] =
  result = @[0xff'u8, 0xd8]
  var quantization = @[0'u8]
  for unused in 0 ..< 64: quantization.add 1
  result.segment(0xdb, quantization)
  var frame = @[8'u8]
  frame.word(8); frame.word(8)
  frame.add @[3'u8, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0]
  result.segment(0xc1, frame)
  var huffman = @[0'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  huffman.add @[0x10'u8, 1]
  for unused in 1 ..< 16: huffman.add 0
  huffman.add 0
  result.segment(0xc4, huffman)
  for identifier in 1 .. 3:
    result.segment(0xda, @[1'u8, byte(identifier), 0, 0, 63, 0])
    result.zeroEntropy(2)
  result.add @[0xff'u8, 0xd9]

suite "JPEG and EXIF":
  test "baseline Huffman JPEG is detected, decoded, and exported":
    let data = constantJpeg()
    let inspection = inspectSource("extensionless", data)
    check inspection.selectedFormat.typeId == JpegTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.findRasterResource(JpegImageResourcePath)
    check resource.typeId == JpegImageTypeId
    check resource.metadataString("jpeg.process") == "baseline-dct"
    check resource.metadataString("jpeg.coding") == "huffman"
    check resource.metadataInteger("jpeg.progressive") == 0
    check resource.raster.trueColourImage.width == 16
    check resource.raster.trueColourImage.height == 8
    for pixel in resource.raster.trueColourImage.pixels:
      check pixel == VextRgb(r: 128, g: 128, b: 128)
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "constant"))
    check exported.outputFormat == "png"
    let png = decodePng(parsePng(exported.artifacts.artifacts[0].data))
    check png.trueColourImage.width == 16
    check png.trueColourImage.height == 8

  test "colour conversion scales without copying component planes per pixel":
    let image = decodeJpeg(parseJpeg(constantJpeg(320, 184))).trueColourImage
    check image.width == 320
    check image.height == 184
    check image.pixels[0] == VextRgb(r: 128, g: 128, b: 128)
    check image.pixels[^1] == VextRgb(r: 128, g: 128, b: 128)

  test "progressive DC and AC scans assemble before reconstruction":
    let data = progressiveConstantJpeg()
    let resource = inspectSource("progressive.jpg", data).resources.
      findRasterResource(JpegImageResourcePath)
    check resource.metadataString("jpeg.process") == "progressive-dct"
    check resource.metadataString("jpeg.coding") == "huffman"
    check resource.metadataInteger("jpeg.progressive") == 1
    let image = resource.raster.trueColourImage
    check image.width == 16
    check image.height == 8
    for pixel in image.pixels:
      check pixel == VextRgb(r: 128, g: 128, b: 128)

  test "extended sequential components can occupy separate scans":
    let image = decodeJpeg(parseJpeg(
      separateComponentConstantJpeg())).trueColourImage
    check image.width == 8
    check image.height == 8
    for pixel in image.pixels:
      check pixel == VextRgb(r: 128, g: 128, b: 128)

  test "little- and big-endian EXIF orientation normalize dimensions":
    for little in [true, false]:
      let source = parseJpeg(constantJpeg(16, 8, 6, true, little))
      check source.hasExif
      check source.exifValid
      check source.orientation == 6
      let image = decodeJpeg(source).trueColourImage
      check image.width == 8
      check image.height == 16

  test "photographic EXIF sub-IFD values become readable metadata":
    let data = constantJpeg().withExif(richExifPayload())
    let source = parseJpeg(data)
    check source.exifValid
    check source.exifValue("exif.ifd0.orientation") == "1 (top-left)"
    check source.exifValue("exif.photo.exposure-time") == "1/420 s"
    check source.exifValue("exif.photo.f-number") == "f/2.9"
    check source.exifValue("exif.photo.iso-speed") == "80"
    check source.exifValue("exif.photo.date-time-original") ==
      "2007:01:20 13:19:03"
    let resource = inspectSource("metadata.jpg", data).resources.
      findRasterResource(JpegImageResourcePath)
    var exposed = false
    for entry in resource.metadata:
      if entry.key == "exif.photo.iso-speed":
        check entry.value.stringValue == "80"
        exposed = true
    check exposed

  test "all eight orientation transforms use the defined coordinates":
    let image = VextTrueColourImage(width: 2, height: 3, pixels: @[
      VextRgb(r: 1), VextRgb(r: 2),
      VextRgb(r: 3), VextRgb(r: 4),
      VextRgb(r: 5), VextRgb(r: 6)])
    let expected = [
      @[1, 2, 3, 4, 5, 6], @[2, 1, 4, 3, 6, 5],
      @[6, 5, 4, 3, 2, 1], @[5, 6, 3, 4, 1, 2],
      @[1, 3, 5, 2, 4, 6], @[5, 3, 1, 6, 4, 2],
      @[6, 4, 2, 5, 3, 1], @[2, 4, 6, 1, 3, 5]]
    for orientation in 1 .. 8:
      let transformed = image.applyJpegOrientation(orientation)
      var values: seq[int]
      for pixel in transformed.pixels: values.add int(pixel.r)
      check values == expected[orientation - 1]

  test "malformed EXIF does not invalidate an otherwise valid image":
    var data = constantJpeg(includeExif = true)
    data[12] = byte('X')
    let source = parseJpeg(data)
    check source.hasExif
    check not source.exifValid
    check source.orientation == 1
    check source.exifError.len > 0
    check decodeJpeg(source).trueColourImage.width == 16

  test "invalid JPEG framing and invalid progressive scans are clear":
    var truncated = constantJpeg()
    truncated.setLen(truncated.len - 2)
    expect ValueError: discard parseJpeg(truncated)
    var progressive = constantJpeg()
    for index in 2 ..< progressive.len - 1:
      if progressive[index] == 0xff and progressive[index + 1] == 0xc0:
        progressive[index + 1] = 0xc2
        break
    let source = parseJpeg(progressive)
    expect ValueError: discard decodeJpeg(source)

  test "local IJG progressive compatibility control decodes":
    if fileExists("jpeg-10/testimg.jpg") and
        fileExists("jpeg-10/testprog.jpg"):
      let progressive = decodeJpeg(parseJpeg(
        readBytes("jpeg-10/testprog.jpg"))).trueColourImage
      check progressive.width == 227
      check progressive.height == 149
      check progressive.pixels.len == 227 * 149

  test "local real-world progressive compatibility control decodes":
    if fileExists("1775669464381.jpeg"):
      let image = decodeJpeg(parseJpeg(
        readBytes("1775669464381.jpeg"))).trueColourImage
      check image.width == 800
      check image.height == 800
    if fileExists("dice-progressive-nonarithmetic.jpeg"):
      let image = decodeJpeg(parseJpeg(
        readBytes("dice-progressive-nonarithmetic.jpeg"))).trueColourImage
      check image.width == 800
      check image.height == 600

  test "local sequential and progressive arithmetic controls decode":
    var decoded: seq[VextTrueColourImage]
    for (path, progressive) in [("dice-arithmetic.jpeg", 0),
        ("dice-progressive-arithmetic.jpeg", 1)]:
      if fileExists(path):
        let inspection = inspectSource(path, readBytes(path))
        check inspection.selectedFormat.typeId == JpegTypeId
        let resource = inspection.resources.roots[0]
        check resource.kind == vrnkRaster
        check resource.metadataString("jpeg.coding") == "arithmetic"
        check resource.metadataInteger("jpeg.progressive") == progressive
        check resource.raster.width == 800
        check resource.raster.height == 600
        decoded.add resource.raster.trueColourImage
    if decoded.len == 2:
      check decoded[0].pixels == decoded[1].pixels
      if fileExists("dice-progressive-nonarithmetic.jpeg"):
        let huffman = decodeJpeg(parseJpeg(readBytes(
          "dice-progressive-nonarithmetic.jpeg"))).trueColourImage
        check decoded[0].pixels == huffman.pixels

  test "local four-component control is identified but remains unsupported":
    if fileExists("dice-cymk.jpeg"):
      let inspection = inspectSource("dice-cymk.jpeg",
        readBytes("dice-cymk.jpeg"))
      check inspection.selectedFormat.typeId == JpegTypeId
      let resource = inspection.resources.roots[0]
      check resource.kind == vrnkOpaque
      check resource.metadataString("jpeg.coding") == "huffman"
      check resource.metadataString("jpeg.component-interpretation") ==
        "cmyk-or-ycck"
      check resource.metadataString("decode.warning").len > 0
