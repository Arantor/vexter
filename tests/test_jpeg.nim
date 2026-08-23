import std/unittest
import vexterlib

proc word(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

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

suite "JPEG and EXIF":
  test "baseline Huffman JPEG is detected, decoded, and exported":
    let data = constantJpeg()
    let inspection = inspectSource("extensionless", data)
    check inspection.selectedFormat.typeId == JpegTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.findRasterResource(JpegImageResourcePath)
    check resource.typeId == JpegImageTypeId
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

  test "little- and big-endian EXIF orientation normalize dimensions":
    for little in [true, false]:
      let source = parseJpeg(constantJpeg(16, 8, 6, true, little))
      check source.hasExif
      check source.exifValid
      check source.orientation == 6
      let image = decodeJpeg(source).trueColourImage
      check image.width == 8
      check image.height == 16

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

  test "invalid JPEG framing and unsupported progressive decoding are clear":
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
