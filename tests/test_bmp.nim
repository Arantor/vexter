import std/unittest
import vexterlib

proc putWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)

proc putDword(data: var seq[byte], offset: int, value: uint32) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)
  data[offset + 2] = byte(value shr 16)
  data[offset + 3] = byte(value shr 24)

proc infoDib(width, height, bits: int, compression = 0,
    colours = 0): seq[byte] =
  result = newSeq[byte](40)
  result.putDword(0, 40)
  result.putDword(4, uint32(width))
  result.putDword(8, cast[uint32](int32(height)))
  result.putWord(12, 1)
  result.putWord(14, bits)
  result.putDword(16, uint32(compression))
  result.putDword(32, uint32(colours))

proc wrapBmp(dib: openArray[byte], pixelOffset: int): seq[byte] =
  result = newSeq[byte](14)
  result[0] = byte('B'); result[1] = byte('M')
  result.add dib
  result.putDword(2, uint32(result.len))
  result.putDword(10, uint32(14 + pixelOffset))

suite "BMP and DIB images":
  test "indexed BMP rows are bottom-up, padded, and use BGR palettes":
    var dib = infoDib(3, 2, 8, colours = 3)
    dib.add @[
      0'u8, 0, 0, 0,
      0, 0, 255, 0,
      0, 255, 0, 0,
      2, 1, 0, 0,
      1, 2, 0, 0]
    let data = wrapBmp(dib, 52)
    let inspection = inspectSource("colours.BMP", data)
    let image = inspection.resources.rasterResources[0].raster.image
    check inspection.selectedFormat.typeId == BmpTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check image.pixelAt(0, 0) == 1
    check image.pixelAt(1, 0) == 2
    check image.pixelAt(0, 1) == 2
    check image.colourAt(0, 0) == VextRgb(r: 255, g: 0, b: 0)

  test "standalone top-down DIB decodes 24-bit true colour":
    var data = infoDib(2, -1, 24)
    data.add @[3'u8, 2, 1, 6, 5, 4, 0, 0]
    let inspection = inspectSource("pixels.dib", data)
    let image = inspection.resources.rasterResources[0].raster.trueColourImage
    check inspection.selectedFormat.typeId == DibTypeId
    check image.colourAt(0, 0) == VextRgb(r: 1, g: 2, b: 3)
    check image.colourAt(1, 0) == VextRgb(r: 4, g: 5, b: 6)

  test "16-bit bitfields are normalized to eight-bit components":
    var data = infoDib(1, 1, 16, compression = 3)
    data.add newSeq[byte](12)
    data.putDword(40, 0xf800)
    data.putDword(44, 0x07e0)
    data.putDword(48, 0x001f)
    data.add @[0xe0'u8, 0x07, 0, 0]
    let image = decodeBmp(parseDib(data)).trueColourImage
    check image.colourAt(0, 0) == VextRgb(r: 0, g: 255, b: 0)

  test "declared BMP alpha masks populate the generic alpha channel":
    var data = newSeq[byte](56)
    data.putDword(0, 56)
    data.putDword(4, 2); data.putDword(8, 1)
    data.putWord(12, 1); data.putWord(14, 32)
    data.putDword(16, 3)
    data.putDword(40, 0x00ff0000'u32); data.putDword(44, 0x0000ff00'u32)
    data.putDword(48, 0x000000ff'u32); data.putDword(52, 0xff000000'u32)
    data.add @[3'u8, 2, 1, 0x80, 6, 5, 4, 0]
    let image = decodeBmp(parseDib(data)).trueColourImage
    check image.rgbaAt(0, 0) == VextRgba(r: 1, g: 2, b: 3, a: 128)
    check image.alphaAt(1, 0) == 0
    check image.hasAlpha
    let png = exportPng(image).artifacts[0].data
    check png[25] == 6 # PNG true-colour with alpha

    var alphaBitfields = infoDib(1, 1, 32, compression = 6)
    alphaBitfields.add newSeq[byte](16)
    alphaBitfields.putDword(40, 0x00ff0000'u32)
    alphaBitfields.putDword(44, 0x0000ff00'u32)
    alphaBitfields.putDword(48, 0x000000ff'u32)
    alphaBitfields.putDword(52, 0xff000000'u32)
    alphaBitfields.add @[9'u8, 8, 7, 6]
    check decodeBmp(parseDib(alphaBitfields)).trueColourImage.rgbaAt(0, 0) ==
      VextRgba(r: 7, g: 8, b: 9, a: 6)

  test "indexed and true-colour archetypes default to opaque alpha":
    let indexed = VextIndexedImage(width: 1, height: 1,
      palette: @[VextRgb(r: 1, g: 2, b: 3)], pixels: @[0'u8],
      alpha: @[64'u8])
    check indexed.rgbaAt(0, 0) == VextRgba(r: 1, g: 2, b: 3, a: 64)
    check exportPng(indexed).artifacts[0].data[25] == 6
    let opaque = VextTrueColourImage(width: 1, height: 1,
      pixels: @[VextRgb(r: 1, g: 2, b: 3)])
    check opaque.alphaAt(0, 0) == 255
    check not opaque.hasAlpha

  test "RLE8 absolute and encoded runs are decoded":
    var data = infoDib(6, 1, 8, compression = 1, colours = 4)
    data.add newSeq[byte](16)
    data.add @[2'u8, 1, 0, 4, 2, 3, 2, 3, 0, 0, 0, 1]
    check decodeBmp(parseDib(data)).image.pixels == @[1'u8, 1, 2, 3, 2, 3]

  test "RLE4 alternates nibbles and OS/2 palettes use three-byte entries":
    var rle = infoDib(4, 1, 4, compression = 2, colours = 3)
    rle.add newSeq[byte](12)
    rle.add @[4'u8, 0x12, 0, 1]
    check decodeBmp(parseDib(rle)).image.pixels == @[1'u8, 2, 1, 2]

    var core = newSeq[byte](12)
    core.putDword(0, 12)
    core.putWord(4, 1); core.putWord(6, 1)
    core.putWord(8, 1); core.putWord(10, 1)
    core.add @[0'u8, 0, 0, 3, 2, 1]
    core.add @[0x80'u8, 0, 0, 0]
    let image = decodeBmp(parseDib(core)).image
    check image.pixelAt(0, 0) == 1
    check image.colourAt(0, 0) == VextRgb(r: 1, g: 2, b: 3)

  test "invalid offsets, compression-depth pairs, and truncation are rejected":
    var badCompression = infoDib(1, 1, 4, compression = 1, colours = 1)
    badCompression.add @[0'u8, 0, 0, 0]
    expect ValueError: discard parseDib(badCompression)

    var truncated = infoDib(2, 1, 24)
    truncated.add @[0'u8, 0, 0]
    expect ValueError: discard decodeBmp(parseDib(truncated))
