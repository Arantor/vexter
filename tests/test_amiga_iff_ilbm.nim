{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/unittest
import vexterlib

const FixturePath = "tests/fixtures/amiga.ilbm/KingTut.LoRes"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc addLong(data: var seq[byte], value: int) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id:
    result.add byte(value)
  result.addLong(payload.len)
  result.add payload
  if payload.len mod 2 != 0:
    result.add 0'u8

proc form(formType: string, chunks: openArray[seq[byte]]): seq[byte] =
  for value in "FORM": result.add byte(value)
  var payload: seq[byte]
  for value in formType: payload.add byte(value)
  for value in chunks: payload.add value
  result.addLong(payload.len)
  result.add payload

proc bmhd(width, height, planes: int, masking = 0,
    compression = 0, transparentColour = 0): seq[byte] =
  result = @[byte(width shr 8), byte(width), byte(height shr 8), byte(height),
    0, 0, 0, 0, byte(planes), byte(masking), byte(compression), 0,
    byte(transparentColour shr 8), byte(transparentColour), 10, 11,
    byte(width shr 8), byte(width), byte(height shr 8),
    byte(height)]

proc planarBody(codes: openArray[byte], planes: int, width = 16): seq[byte] =
  let rowBytes = ((width + 15) div 16) * 2
  result = newSeq[byte](planes * rowBytes)
  for plane in 0 ..< planes:
    for x, code in codes:
      if (code and byte(1 shl plane)) != 0:
        result[plane * rowBytes + x div 8] =
          result[plane * rowBytes + x div 8] or (0x80'u8 shr (x mod 8))

proc rgbDigest(image: VextIndexedImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for paletteIndex in image.pixels:
    let colour = image.palette[int(paletteIndex)]
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

proc rgbDigest(image: VextTrueColourImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for colour in image.pixels:
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

suite "Amiga IFF ILBM":
  test "King Tut is detected and matches the normalized PNG control":
    let
      data = readBytes(FixturePath)
      parsed = parseAmigaIlbm(data)
      candidates = detectFormats(FixturePath, data)
      inspection = inspectSource(FixturePath, data)
      resource = inspection.resources.rasterResources[0]
      image = resource.raster.image
    check AmigaIffTypeId == "amiga.iff"
    check AmigaIlbmTypeId == "amiga.ilbm"
    check AmigaIlbmImageTypeId == "amiga.ilbm-image"
    check candidates.len == 1
    check candidates[0].typeId == AmigaIlbmTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check parsed.image.header.width == 320
    check parsed.image.header.height == 200
    check parsed.image.header.planes == 5
    check parsed.image.header.compression == 1
    check resource.path == "/image"
    check image.width == 320
    check image.height == 200
    check image.palette.len == 32
    check image.palette[1] == VextRgb(r: 85, g: 85, b: 136)
    # ImageMagick retains the legacy zero low nibbles in the supplied PNG.
    # This digest is the same control after the required 4-to-8-bit expansion.
    check rgbDigest(image) == "206D3BD0EF97E4B8DDA2564E5A96D1CAE4F149BD"

  test "six-plane EHB extends the palette with half-bright colours":
    var palette = newSeq[byte](32 * 3)
    palette[0] = 0x40
    palette[1] = 0x60
    palette[2] = 0x80
    var body = newSeq[byte](6 * 2)
    body[10] = 0x80 # Plane five makes the first pixel colour 32.
    let data = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 6)),
      chunk("CMAP", palette),
      chunk("CAMG", @[0'u8, 0, 0, 0x80]),
      chunk("BODY", body)])
    let image = decodeAmigaIlbmImage(parseAmigaIlbm(data).image)
    check image.palette.len == 64
    check image.palette[0] == VextRgb(r: 68, g: 102, b: 136)
    check image.palette[32] == VextRgb(r: 34, g: 51, b: 68)
    check image.pixelAt(0, 0) == 32

  test "eight-plane indexed images preserve all 256 palette indices":
    var palette = newSeq[byte](256 * 3)
    for index in 0 ..< 256:
      palette[index * 3] = byte(index)
      palette[index * 3 + 1] = byte(255 - index)
      palette[index * 3 + 2] = byte(index xor 0x55)
    let
      codes = @[0'u8, 1, 63, 127, 128, 192, 254, 255]
      data = form("ILBM", [
        chunk("BMHD", bmhd(16, 1, 8)),
        chunk("CMAP", palette),
        chunk("BODY", planarBody(codes, 8))])
      image = inspectSource("indexed-256.ilbm", data).resources.
        rasterResources[0].raster.image
    check image.palette.len == 256
    check image.pixels[0 ..< codes.len] == codes
    check image.palette[255] == VextRgb(r: 255, g: 0, b: 170)
    check image.colourAt(6, 0) == VextRgb(r: 254, g: 1, b: 171)

  test "HAM6 holds and modifies RGB components across a scanline":
    var palette = newSeq[byte](16 * 3)
    palette[3] = 0x10
    palette[4] = 0x20
    palette[5] = 0x30
    let
      codes = @[0x01'u8, 0x2f, 0x38, 0x14]
      data = form("ILBM", [
        chunk("BMHD", bmhd(16, 1, 6)),
        chunk("CMAP", palette),
        chunk("CAMG", @[0'u8, 0, 8, 0]),
        chunk("BODY", planarBody(codes, 6))])
      raster = inspectSource("ham.iff", data).resources.rasterResources[0].raster
    check raster.kind == vrkTrueColourImage
    check raster.archetypeName == "VextTrueColourImage"
    check raster.trueColourImage.colourAt(0, 0) ==
      VextRgb(r: 17, g: 34, b: 51)
    check raster.trueColourImage.colourAt(1, 0) ==
      VextRgb(r: 255, g: 34, b: 51)
    check raster.trueColourImage.colourAt(2, 0) ==
      VextRgb(r: 255, g: 136, b: 51)
    check raster.trueColourImage.colourAt(3, 0) ==
      VextRgb(r: 255, g: 136, b: 68)

    let png = exportResource(inspectSource("ham.iff", data).resources,
      VextExportRequest(suggestedName: "ham"))
    check png.outputFormat == "png"
    check png.artifacts.artifacts[0].data[25] == 2 # PNG true-colour type.
    expect ValueError:
      discard exportResource(inspectSource("ham.iff", data).resources,
        VextExportRequest(outputFormat: "gif", suggestedName: "ham"))

  test "HAM8 precision-extends six-bit component values":
    var palette = newSeq[byte](64 * 3)
    palette[3] = 1
    palette[4] = 2
    palette[5] = 3
    let
      codes = @[0x01'u8, 0xbf, 0xe0, 0x40]
      data = form("ILBM", [
        chunk("BMHD", bmhd(16, 1, 8)),
        chunk("CMAP", palette),
        chunk("CAMG", @[0'u8, 0, 8, 0]),
        chunk("BODY", planarBody(codes, 8))])
      image = decodeAmigaIlbmHam(parseAmigaIlbm(data).image)
    check image.colourAt(0, 0) == VextRgb(r: 1, g: 2, b: 3)
    check image.colourAt(1, 0) == VextRgb(r: 255, g: 2, b: 3)
    check image.colourAt(2, 0) == VextRgb(r: 255, g: 129, b: 3)
    check image.colourAt(3, 0) == VextRgb(r: 255, g: 129, b: 0)

  test "Deluxe Paint HAM8 samples match their PNG controls":
    let fixtures = [
      ("TutGallery.Ham", 628740'u32,
        "8C39CF0652F8131452541645FCF97F81D5311CBB"),
      ("EAWorld.Ham8", 104452'u32,
        "42E4F99DFD47F3EC68540B63FA8FC3B5398977ED")]
    for fixture in fixtures:
      let
        path = "tests/fixtures/amiga.ilbm/" & fixture[0]
        parsed = parseAmigaIlbm(readBytes(path))
        raster = inspectSource(path, readBytes(path)).resources.
          rasterResources[0].raster
      # Despite its shorter suffix, TutGallery also declares eight source
      # planes. Synthetic coverage above remains the HAM6 authority.
      check parsed.image.header.planes == 8
      check parsed.image.camg == fixture[1]
      check (parsed.image.camg and AmigaIlbmCamgHam) != 0
      check raster.kind == vrkTrueColourImage
      check raster.width == 640
      check raster.height == 400
      check rgbDigest(raster.trueColourImage) == fixture[2]

  test "Deluxe Paint Aquarium is an authentic HAM6 control":
    let
      path = "tests/fixtures/amiga.ilbm/AquariumBackground.Ham"
      parsed = parseAmigaIlbm(readBytes(path))
      raster = inspectSource(path, readBytes(path)).resources.
        rasterResources[0].raster
    check parsed.image.header.planes == 6
    check parsed.image.camg == 0x4800'u32
    check (parsed.image.camg and AmigaIlbmCamgHam) != 0
    check raster.kind == vrkTrueColourImage
    check raster.width == 320
    check raster.height == 200
    # ImageMagick's supplied PNG leaves four-bit HAM components at $x0.
    # Replicating those nibbles to $xx produces this exact RGB digest.
    check rgbDigest(raster.trueColourImage) ==
      "DE1856294087A8BD6C636DCC003C2B9B0AC10BDE"

  test "generic FORM chunks remain identifiable and padded":
    let
      data = form("TEST", [chunk("ODD!", @[1'u8, 2, 3])])
      parsed = parseAmigaIff(data)
      inspection = inspectSource("sample.iff", data)
    check parsed.formType == "TEST"
    check parsed.chunks.len == 1
    check parsed.chunks[0].data == @[1'u8, 2, 3]
    check inspection.selectedFormat.typeId == AmigaIffTypeId
    check inspection.resources.leafResources[0].kind == vrnkOpaque
    check inspection.resources.leafResources[0].metadata[0].value.stringValue ==
      "ODD!"

  test "an explicit mask plane produces per-pixel alpha":
    let masked = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, masking = 1)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[0x55'u8, 0, 0xf0, 0])])
    let image = inspectSource("masked.iff", masked).resources.
      rasterResources[0].raster.image
    check image.pixels[0 .. 7] == @[0'u8, 1, 0, 1, 0, 1, 0, 1]
    check image.alpha[0 .. 7] ==
      @[255'u8, 255, 255, 255, 0, 0, 0, 0]

  test "ByteRun1 applies independently to image and mask rows":
    let masked = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, masking = 1, compression = 1)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[1'u8, 0x55, 0, 1, 0xf0, 0])])
    let image = decodeAmigaIlbmRaster(parseAmigaIlbm(masked).image).image
    check image.alpha[0 .. 7] ==
      @[255'u8, 255, 255, 255, 0, 0, 0, 0]

  test "ByteRun1 accepts a zero IFF pad included in the BODY size":
    let includedPad = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, compression = 1)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[1'u8, 0x80, 0, 0])])
    let image = decodeAmigaIlbmImage(parseAmigaIlbm(includedPad).image)
    check image.pixelAt(0, 0) == 1

    let nonPaddingTail = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, compression = 1)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[1'u8, 0x80, 0, 1])])
    expect ValueError:
      discard decodeAmigaIlbmImage(parseAmigaIlbm(nonPaddingTail).image)

  test "transparent-colour masking makes only its palette index transparent":
    let transparent = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, masking = 2,
        transparentColour = 0)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[0x55'u8, 0])])
    let image = decodeAmigaIlbmRaster(parseAmigaIlbm(transparent).image).image
    check image.alpha[0 .. 7] == @[0'u8, 255, 0, 255, 0, 255, 0, 255]

  test "lasso masking preserves enclosed transparent-colour islands":
    let lasso = form("ILBM", [
      chunk("BMHD", bmhd(5, 5, 1, masking = 3,
        transparentColour = 0)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[
        0x00'u8, 0, 0x70, 0, 0x50, 0, 0x70, 0, 0x00, 0])])
    let image = decodeAmigaIlbmRaster(parseAmigaIlbm(lasso).image).image
    check image.alphaAt(0, 0) == 0
    check image.alphaAt(1, 1) == 255
    check image.alphaAt(2, 2) == 255

  test "unknown masks, malformed FORM lengths, and bad ByteRun1 are rejected":
    let unknownMask = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, masking = 4)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", newSeq[byte](2))])
    check not isAmigaIlbm(unknownMask)

    var badLength = form("TEST", [])
    badLength[7] = badLength[7] + 1
    check not isAmigaIff(badLength)

    let badRun = form("ILBM", [
      chunk("BMHD", bmhd(16, 1, 1, compression = 1)),
      chunk("CMAP", newSeq[byte](6)),
      chunk("BODY", @[2'u8, 0])])
    expect ValueError:
      discard inspectSource("bad-run.iff", badRun)
