import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc tgaHeader(imageType, width, height, pixelBits: int,
    colourMapType = 0, colourMapOrigin = 0, colourMapLength = 0,
    colourMapBits = 0, descriptor = 0, idLength = 0): seq[byte] =
  result.add byte(idLength)
  result.add byte(colourMapType)
  result.add byte(imageType)
  result.addWord(colourMapOrigin)
  result.addWord(colourMapLength)
  result.add byte(colourMapBits)
  result.addWord(0)
  result.addWord(0)
  result.addWord(width)
  result.addWord(height)
  result.add byte(pixelBits)
  result.add byte(descriptor)

suite "TGA images":
  test "colour-mapped images normalize palette origins and retain identification":
    var data = tgaHeader(1, 3, 1, 8, colourMapType = 1,
      colourMapOrigin = 5, colourMapLength = 3, colourMapBits = 24,
      descriptor = 0x20, idLength = 3)
    data.add @[byte('i'), byte('d'), byte('!')]
    data.add @[
      0'u8, 0, 255,
      0, 255, 0,
      255, 0, 0]
    data[16] = 16
    data.add @[5'u8, 0, 7, 0, 6, 0]

    let source = parseTga(data)
    check source.imageId == @[byte('i'), byte('d'), byte('!')]
    let inspection = inspectSource("palette.tga", data)
    check inspection.selectedFormat.typeId == TgaTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    let resource = inspection.resources.rasterResources[0]
    check resource.path == TgaImageResourcePath
    check resource.typeId == TgaImageTypeId
    check resource.raster.image.pixels == @[0'u8, 2, 1]
    check resource.raster.image.palette == @[
      VextRgb(r: 255, g: 0, b: 0),
      VextRgb(r: 0, g: 255, b: 0),
      VextRgb(r: 0, g: 0, b: 255)]

  test "bottom-origin true-colour rows are normalized to top-down order":
    var data = tgaHeader(2, 2, 2, 24)
    data.add @[
      0'u8, 0, 255, 0, 255, 0,
      255, 0, 0, 255, 255, 255]
    let image = decodeTga(parseTga(data)).trueColourImage
    check image.pixels == @[
      VextRgb(r: 0, g: 0, b: 255), VextRgb(r: 255, g: 255, b: 255),
      VextRgb(r: 255, g: 0, b: 0), VextRgb(r: 0, g: 255, b: 0)]
    check image.alpha.len == 0

  test "sixteen-bit colours use five-bit components and binary alpha":
    var data = tgaHeader(2, 2, 1, 16, descriptor = 0x21)
    data.add @[0x00'u8, 0xfc, 0xe0, 0x03]
    let image = decodeTga(parseTga(data)).trueColourImage
    check image.pixels == @[
      VextRgb(r: 248, g: 0, b: 0), VextRgb(r: 0, g: 248, b: 0)]
    check image.alpha == @[255'u8, 0]

  test "colour-map attributes become indexed per-pixel alpha":
    var data = tgaHeader(1, 2, 1, 8, colourMapType = 1,
      colourMapLength = 2, colourMapBits = 16, descriptor = 0x20)
    data.add @[0x00'u8, 0xfc, 0xe0, 0x03]
    data.add @[0'u8, 1]
    let image = decodeTga(parseTga(data)).image
    check image.palette == @[
      VextRgb(r: 248, g: 0, b: 0), VextRgb(r: 0, g: 248, b: 0)]
    check image.alpha == @[255'u8, 0]

  test "RLE packets cross rows and preserve 32-bit attributes":
    var data = tgaHeader(10, 2, 2, 32, descriptor = 0x28)
    data.add @[
      1'u8,
      0, 0, 255, 255,
      0, 255, 0, 128,
      0x81,
      255, 0, 0, 0]
    let image = decodeTga(parseTga(data)).trueColourImage
    check image.pixels == @[
      VextRgb(r: 255, g: 0, b: 0), VextRgb(r: 0, g: 255, b: 0),
      VextRgb(r: 0, g: 0, b: 255), VextRgb(r: 0, g: 0, b: 255)]
    check image.alpha == @[255'u8, 128, 0, 0]

  test "raw and RLE grayscale images produce true-colour intensity":
    var raw = tgaHeader(3, 2, 1, 8, descriptor = 0x20)
    raw.add @[0'u8, 200]
    check decodeTga(parseTga(raw)).trueColourImage.pixels == @[
      VextRgb(r: 0, g: 0, b: 0), VextRgb(r: 200, g: 200, b: 200)]

    var compressed = tgaHeader(11, 3, 1, 8, descriptor = 0x20)
    compressed.add @[0x82'u8, 77]
    check decodeTga(parseTga(compressed)).trueColourImage.pixels == @[
      VextRgb(r: 77, g: 77, b: 77), VextRgb(r: 77, g: 77, b: 77),
      VextRgb(r: 77, g: 77, b: 77)]

  test "unsupported layouts and malformed streams are rejected":
    expect ValueError:
      discard parseTga(tgaHeader(32, 1, 1, 8))
    expect ValueError:
      discard parseTga(tgaHeader(2, 1, 1, 24, descriptor = 0x10))
    expect ValueError:
      discard parseTga(tgaHeader(2, 1, 1, 24, descriptor = 0x40))
    expect ValueError:
      discard parseTga(tgaHeader(2, 1, 1, 32, descriptor = 0x22))
    expect ValueError:
      discard parseTga(tgaHeader(1, 1, 1, 8))

    var truncated = tgaHeader(10, 2, 1, 24, descriptor = 0x20)
    truncated.add @[0x81'u8, 1, 2]
    expect ValueError:
      discard parseTga(truncated)

    var excess = tgaHeader(10, 1, 1, 24, descriptor = 0x20)
    excess.add @[0x81'u8, 1, 2, 3]
    expect ValueError:
      discard parseTga(excess)

    var badIndex = tgaHeader(1, 1, 1, 8, colourMapType = 1,
      colourMapOrigin = 4, colourMapLength = 1, colourMapBits = 24,
      descriptor = 0x20)
    badIndex.add @[0'u8, 0, 0, 5]
    expect ValueError:
      discard decodeTga(parseTga(badIndex))
