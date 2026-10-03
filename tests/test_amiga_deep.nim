import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

proc addDword(data: var seq[byte], value: int) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.addDword(payload.len)
  result.add payload
  if payload.len mod 2 != 0: result.add 0

proc form(chunks: openArray[seq[byte]]): seq[byte] =
  var payload: seq[byte]
  for value in "DEEP": payload.add byte(value)
  for value in chunks: payload.add value
  for value in "FORM": result.add byte(value)
  result.addDword(payload.len)
  result.add payload

proc global(width, height: int, compression = 0): seq[byte] =
  result.addWord(width)
  result.addWord(height)
  result.addWord(compression)
  result.add 1
  result.add 1

proc components(values: openArray[(int, int)]): seq[byte] =
  result.addDword(values.len)
  for value in values:
    result.addWord(value[0])
    result.addWord(value[1])

proc location(width, height, x, y: int): seq[byte] =
  result.addWord(width)
  result.addWord(height)
  result.addWord(x and 0xffff)
  result.addWord(y and 0xffff)

proc frameRate(milliseconds: int): seq[byte] =
  result.addDword(milliseconds)

let rgb8 = [(AmigaDeepComponentRed, 8),
  (AmigaDeepComponentGreen, 8), (AmigaDeepComponentBlue, 8)]

suite "IFF DEEP images":
  test "uncompressed RGB pixels decode and use longword body padding":
    let data = form(@[
      chunk("DGBL", global(2, 1)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[255'u8, 0, 0, 0, 128, 255, 0xaa, 0xbb])])
    let inspection = inspectSource("colours.deep", data)
    check inspection.selectedFormat.typeId == AmigaDeepTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.rasterResources[0]
    check resource.path == AmigaDeepImageResourcePath
    check resource.typeId == AmigaDeepImageTypeId
    check resource.raster.kind == vrkTrueColourImage
    check resource.raster.trueColourImage.pixels == @[
      VextRgb(r: 255, g: 0, b: 0), VextRgb(r: 0, g: 128, b: 255)]
    check resource.defaultExportFormat == "png"

  test "non-byte-aligned RGB and opacity components scale to eight bits":
    let data = form(@[
      chunk("DGBL", global(2, 1)),
      chunk("DPEL", components(@[(AmigaDeepComponentRed, 5),
        (AmigaDeepComponentGreen, 6), (AmigaDeepComponentBlue, 5)])),
      chunk("DBOD", @[0xf8'u8, 0x00, 0x07, 0xe0])])
    let image = inspectSource("rgb565.iff", data).resources.
      rasterResources[0].raster.trueColourImage
    check image.pixels == @[
      VextRgb(r: 255, g: 0, b: 0), VextRgb(r: 0, g: 255, b: 0)]

    let rgba = form(@[
      chunk("DGBL", global(1, 1)),
      chunk("DPEL", components(@[(AmigaDeepComponentRed, 8),
        (AmigaDeepComponentGreen, 8), (AmigaDeepComponentBlue, 8),
        (AmigaDeepComponentOpacity, 4)])),
      chunk("DBOD", @[0x12'u8, 0x34, 0x56, 0xa0])])
    let alphaImage = inspectSource("opacity.deep", rgba).resources.
      rasterResources[0].raster.trueColourImage
    check alphaImage.pixels == @[VextRgb(r: 0x12, g: 0x34, b: 0x56)]
    check alphaImage.alpha == @[170'u8]

  test "unknown components are skipped and positioned bodies compose in order":
    let data = form(@[
      chunk("DGBL", global(2, 1)),
      chunk("DPEL", components(@[(AmigaDeepComponentRed, 8),
        (AmigaDeepComponentGreen, 8), (AmigaDeepComponentBlue, 8),
        (AmigaDeepComponentZBuffer, 8)])),
      chunk("DLOC", location(1, 1, 0, 0)),
      chunk("DBOD", @[255'u8, 0, 0, 99]),
      chunk("DLOC", location(1, 1, 1, 0)),
      chunk("DBOD", @[0'u8, 0, 255, 42])])
    let image = decodeAmigaDeep(parseAmigaDeep(data)).trueColourImage
    check image.pixels == @[
      VextRgb(r: 255, g: 0, b: 0), VextRgb(r: 0, g: 0, b: 255)]

  test "positive DCHG durations produce a true-colour animation":
    let data = form(@[
      chunk("DGBL", global(1, 1)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[255'u8, 0, 0, 0]),
      chunk("DCHG", frameRate(40)),
      chunk("DBOD", @[0'u8, 255, 0, 0]),
      chunk("DCHG", frameRate(90))])
    let resource = inspectSource("cells.deep", data).resources.rasterResources[0]
    check resource.raster.kind == vrkTrueColourAnimation
    check resource.defaultExportFormat == "apng"
    check resource.raster.trueColourAnimation.frames.len == 2
    check resource.raster.trueColourAnimation.frames[0].durationMs == 40
    check resource.raster.trueColourAnimation.frames[1].durationMs == 90
    check resource.raster.trueColourAnimation.frames[1].image.pixels[0] ==
      VextRgb(r: 0, g: 255, b: 0)

  test "run-length packets operate on complete pixels within each row":
    let data = form(@[
      chunk("DGBL", global(4, 2,
        compression = AmigaDeepCompressionRunLength)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[
        0'u8, 255, 0, 0,       # One literal red pixel.
        0xfe, 0, 255, 0,       # Three repeated green pixels.
        0x80,                   # No-op at the next row boundary.
        0xfd, 0, 0, 255,       # Four repeated blue pixels.
        0, 0, 0])])            # DBOD longword padding.
    let image = decodeAmigaDeep(parseAmigaDeep(data)).trueColourImage
    check image.pixels == @[
      VextRgb(r: 255, g: 0, b: 0),
      VextRgb(r: 0, g: 255, b: 0),
      VextRgb(r: 0, g: 255, b: 0),
      VextRgb(r: 0, g: 255, b: 0),
      VextRgb(r: 0, g: 0, b: 255),
      VextRgb(r: 0, g: 0, b: 255),
      VextRgb(r: 0, g: 0, b: 255),
      VextRgb(r: 0, g: 0, b: 255)]

  test "unsupported and malformed structures remain bounded":
    expect ValueError:
      discard parseAmigaDeep(form(@[
        chunk("DPEL", components(rgb8)),
        chunk("DGBL", global(1, 1)),
        chunk("DBOD", @[0'u8, 0, 0, 0])]))
    expect ValueError:
      discard inspectSource("short.deep", form(@[
        chunk("DGBL", global(1, 1)),
        chunk("DPEL", components(rgb8)),
        chunk("DBOD", @[0'u8, 0, 0])]))
    expect ValueError:
      discard parseAmigaDeep(form(@[
        chunk("DGBL", global(1, 1)),
        chunk("DPEL", components(rgb8)),
        chunk("DBOD", @[0'u8, 0, 0, 0]),
        chunk("DCHG", frameRate(0))]))
    let compressed = parseAmigaDeep(form(@[
      chunk("DGBL", global(1, 1, compression = 2)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[0'u8, 0, 0, 0])]))
    expect ValueError:
      discard decodeAmigaDeep(compressed)
    let crossedRow = parseAmigaDeep(form(@[
      chunk("DGBL", global(2, 1,
        compression = AmigaDeepCompressionRunLength)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[2'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0])]))
    expect ValueError:
      discard decodeAmigaDeep(crossedRow)
    let trailingPacket = parseAmigaDeep(form(@[
      chunk("DGBL", global(1, 1,
        compression = AmigaDeepCompressionRunLength)),
      chunk("DPEL", components(rgb8)),
      chunk("DBOD", @[0'u8, 1, 2, 3, 0, 0, 0, 0])]))
    expect ValueError:
      discard decodeAmigaDeep(trailingPacket)
