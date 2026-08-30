{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/unittest
import vexterlib

const FixturePath = "tests/fixtures/amos.pacpic/Castle_AMOS.Abk"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc putBeWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc putBeDword(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc sixPlaneBank(): seq[byte] =
  var payload = newSeq[byte](117)
  payload[0 .. 3] = @[0x12'u8, 0x03, 0x19, 0x90]
  payload.putBeWord(4, 8)
  payload.putBeWord(6, 1)
  payload.putBeWord(22, 32)
  payload.putBeWord(24, 6)
  payload.putBeWord(26, 0x0468)
  payload[90 .. 93] = @[0x06'u8, 0x07, 0x19, 0x63]
  payload.putBeWord(98, 1)
  payload.putBeWord(100, 1)
  payload.putBeWord(102, 1)
  payload.putBeWord(104, 6)
  payload.putBeDword(106, 25)
  payload.putBeDword(110, 26)

  result = newSeq[byte](20)
  result[0 .. 3] = @[byte('A'), byte('m'), byte('B'), byte('k')]
  result.putBeDword(8, payload.len + 8)
  for index, value in AmosPackedPictureBankType:
    result[12 + index] = byte(value)
  result.add payload

proc rgbDigest(image: VextIndexedImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for paletteIndex in image.pixels:
    let colour = image.palette[int(paletteIndex)]
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

suite "AMOS packed pictures":
  test "Castle AMOS decompresses to the supplied PNG rendering":
    let
      bytes = readBytes(FixturePath)
      bank = parseAmosBank(bytes)
      packed = parseAmosPackedPicture(bank.data)
      inspection = inspectSource(FixturePath, bytes)
      resources = inspection.resources.rasterResources
      image = resources[0].raster.image

    check bank.bankType == AmosPackedPictureBankType
    check packed.hasScreenHeader
    check packed.screenWidth == 320
    check packed.screenHeight == 200
    check packed.widthBytes == 40
    check packed.lumps == 25
    check packed.lumpHeight == 8
    check packed.planes == 4
    check resources.len == 1
    check resources[0].path == AmosPackedPictureResourcePath
    check resources[0].typeId == AmosPackedPictureResourceTypeId
    check image.width == 320
    check image.height == 200
    check image.palette.len == 16
    check rgbDigest(image) == "56A1B401EA53BA116DE7FE61B49020E1692CA3FC"

    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "castle-amos"))
    check exported.outputFormat == "png"
    check exported.artifacts.artifacts[0].suggestedFilename == "castle-amos.png"

  test "Pac.Pic. banks embedded in AmBs expose the same raster":
    let bank = readBytes(FixturePath)
    var bankSet = @[byte('A'), byte('m'), byte('B'), byte('s'), 0'u8, 1]
    bankSet.add bank
    let resource = inspectSource("castle.abs", bankSet).resources.rasterResources[0]
    check resource.path == "/banks/0"
    check resource.typeId == AmosPackedPictureResourceTypeId
    check rgbDigest(resource.raster.image) ==
      "56A1B401EA53BA116DE7FE61B49020E1692CA3FC"

  test "six-plane pictures use an EHB palette":
    var palette = newSeq[uint16](32)
    palette[0] = 0x0468
    let picture = AmosPackedPicture(
      hasScreenHeader: true,
      colourCount: 32,
      paletteWords: palette,
      widthBytes: 1,
      lumps: 1,
      lumpHeight: 1,
      planes: 6,
      planeData: @[0'u8, 0, 0, 0, 0, 0x80])
    let image = decodeAmosPackedPicture(picture)

    check image.width == 8
    check image.height == 1
    check image.palette.len == 64
    check image.palette[0] == VextRgb(r: 68, g: 102, b: 136)
    check image.palette[32] == VextRgb(r: 34, g: 51, b: 68)
    check image.pixelAt(0, 0) == 32
    check image.pixelAt(1, 0) == 0

    let resources = inspectSource("ehb.abk", sixPlaneBank()).resources.rasterResources
    check resources.len == 1
    check resources[0].typeId == AmosPackedPictureResourceTypeId
    check resources[0].raster.image.palette.len == 64

  test "partial packed pictures without a palette remain unrenderable":
    var payload = newSeq[byte](24)
    payload[0] = 0x06
    payload[1] = 0x07
    payload[2] = 0x19
    payload[3] = 0x63
    payload[9] = 1             # one byte wide
    payload[11] = 1            # one lump
    payload[13] = 1            # one row per lump
    payload[15] = 1            # one plane
    payload[19] = 25           # RLE stream offset
    payload[23] = 26           # POINTS stream offset
    payload.add @[0'u8, 0'u8, 0'u8]
    let picture = parseAmosPackedPicture(payload)
    check not picture.hasScreenHeader
    check picture.planeData == @[0'u8]
    expect ValueError:
      discard decodeAmosPackedPicture(picture)
