import std/[strutils, unittest]
import vexterlib

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

proc addDword(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24); data.add byte(value shr 16)
  data.add byte(value shr 8); data.add byte(value)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for unused in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

proc chunk(kind: string, payload: openArray[byte]): seq[byte] =
  result.addDword(uint32(payload.len))
  var checked: seq[byte]
  for value in kind: result.add byte(value); checked.add byte(value)
  result.add payload; checked.add payload
  result.addDword(crc32(checked))

proc adler32(data: openArray[byte]): uint32 =
  var a = 1'u32; var b = 0'u32
  for value in data:
    a = (a + uint32(value)) mod 65521
    b = (b + a) mod 65521
  (b shl 16) or a

proc storedZlib(data: openArray[byte]): seq[byte] =
  result = @[0x78'u8, 0x01, 0x01]
  let length = uint16(data.len)
  let inverse = not length
  result.add byte(length); result.add byte(length shr 8)
  result.add byte(inverse); result.add byte(inverse shr 8)
  result.add data
  result.addDword(adler32(data))

proc png(width, height, depth, colourType, interlace: int,
    scanlines: openArray[byte], extras: openArray[seq[byte]] = []): seq[byte] =
  result = @PngSignature
  var header: seq[byte]
  header.addDword(uint32(width)); header.addDword(uint32(height))
  header.add byte(depth); header.add byte(colourType)
  header.add 0; header.add 0; header.add byte(interlace)
  result.add chunk("IHDR", header)
  for extra in extras: result.add extra
  result.add chunk("IDAT", storedZlib(scanlines))
  result.add chunk("IEND", [])

suite "PNG images":
  test "existing independent PNG controls complete the import pipeline":
    for path in [
        "tests/fixtures/zx-spectrum.screen/colours.png",
        "tests/fixtures/amos.pacpic/Castle_AMOS.png",
        "tests/fixtures/amiga.ilbm/AquariumBackground.png",
        "tests/fixtures/amiga.ilbm/EAWorld.png",
        "tests/fixtures/amiga.ilbm/KingTut.png",
        "tests/fixtures/amiga.ilbm/TutGallery.png"]:
      let raster = inspectSource(path, readBytes(path)).resources.
        rasterResources[0].raster
      check raster.width > 0
      check raster.height > 0

  test "RGBA PNG is fully decoded and retains alpha":
    let original = VextTrueColourImage(width: 2, height: 1,
      pixels: @[VextRgb(r: 1, g: 2, b: 3), VextRgb(r: 4, g: 5, b: 6)],
      alpha: @[7'u8, 255])
    let data = exportPng(original).artifacts[0].data
    let inspection = inspectSource("alpha.png", data)
    let image = inspection.resources.rasterResources[0].raster.trueColourImage
    check inspection.selectedFormat.typeId == PngTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check image.rgbaAt(0, 0) == VextRgba(r: 1, g: 2, b: 3, a: 7)
    check image.rgbaAt(1, 0) == VextRgba(r: 4, g: 5, b: 6, a: 255)

  test "indexed pixels and tRNS remain indexed with per-pixel alpha":
    let palette = chunk("PLTE", @[255'u8, 0, 0, 0, 255, 0])
    let transparency = chunk("tRNS", @[0'u8, 128])
    let data = png(2, 1, 1, 3, 0, @[0'u8, 0x40],
      [palette, transparency])
    let image = decodePng(parsePng(data)).image
    check image.pixels == @[0'u8, 1]
    check image.alpha == @[0'u8, 128]
    check image.colourAt(1, 0) == VextRgb(r: 0, g: 255, b: 0)

  test "grayscale, sixteen-bit samples, and filters are expanded":
    # First pixel is 0x1234; Sub reconstructs the second as 0xffff.
    let data = png(2, 1, 16, 0, 0, @[1'u8, 0x12, 0x34, 0xed, 0xcb])
    let image = decodePng(parsePng(data)).trueColourImage
    check image.colourAt(0, 0) == VextRgb(r: 18, g: 18, b: 18)
    check image.colourAt(1, 0) == VextRgb(r: 255, g: 255, b: 255)

    let filtered = png(2, 4, 8, 0, 0, @[
      0'u8, 10, 20,
      2, 5, 5,
      3, 13, 8,
      4, 5, 5])
    let rows = decodePng(parsePng(filtered)).trueColourImage
    for y in 0 ..< 4:
      check rows.colourAt(0, y).r == uint8(10 + y * 5)
      check rows.colourAt(1, y).r == uint8(20 + y * 5)

  test "Adam7 passes reconstruct their natural coordinates":
    # A 3x3 8-bit grayscale image. Passes 1, 4, 5, 6, and 7 are non-empty.
    let scanlines = @[
      0'u8, 0,
      0, 2,
      0, 20, 22,
      0, 1,
      0, 21,
      0, 10, 11, 12]
    let image = decodePng(parsePng(png(3, 3, 8, 0, 1, scanlines))).
      trueColourImage
    for y in 0 ..< 3:
      for x in 0 ..< 3:
        check image.colourAt(x, y).r == uint8(y * 10 + x)

  test "APNG and unknown chunks are ignored but reported as metadata":
    var data = png(1, 1, 8, 2, 0, @[0'u8, 1, 2, 3], [
      chunk("acTL", @[0'u8, 0, 0, 1, 0, 0, 0, 0]),
      chunk("fcTL", newSeq[byte](26))])
    data.setLen(data.len - 12) # replace IEND with later APNG/private chunks
    data.add chunk("fcTL", newSeq[byte](26))
    data.add chunk("fdAT", @[0'u8, 0, 0, 1, 9])
    data.add chunk("vpAg", @[9'u8, 8, 7])
    data.add chunk("IEND", [])
    let inspection = inspectSource("animated.png", data)
    let metadata = inspection.resources.roots[0].metadata
    check inspection.resources.rasterResources[0].raster.trueColourImage.
      colourAt(0, 0) == VextRgb(r: 1, g: 2, b: 3)
    var chunkTypes: seq[string]
    for entry in metadata:
      if entry.key.endsWith(".type"):
        chunkTypes.add entry.value.stringValue
    check chunkTypes == @["IHDR", "acTL", "fcTL", "IDAT", "fcTL", "fdAT",
      "vpAg", "IEND"]

  test "bad CRCs and malformed required chunks fail":
    var data = png(1, 1, 8, 0, 0, @[0'u8, 1])
    data[^5] = data[^5] xor 1
    check not isPng(data)
