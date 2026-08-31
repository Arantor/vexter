{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/unittest
import vexterlib

const FixturePath = "tests/fixtures/amos.sprite-bank/DRAGON.Abk"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc rgbDigest(image: VextIndexedImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for paletteIndex in image.pixels:
    let colour = image.palette[int(paletteIndex)]
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

proc addWord(data: var seq[byte], value: int) =
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc syntheticIconBank(paletteFirst = false): seq[byte] =
  for value in AmosIconBankMagic:
    result.add byte(value)
  result.addWord(1)
  if paletteFirst:
    for index in 0 ..< AmosPaletteEntries:
      result.addWord(if index == 1: 0x0f00 else: 0)
  result.addWord(1)
  result.addWord(1)
  result.addWord(1)
  result.addWord(0xfffe)
  result.addWord(3)
  result.addWord(0x8000)
  if not paletteFirst:
    for index in 0 ..< AmosPaletteEntries:
      result.addWord(if index == 1: 0x0f00 else: 0)

proc syntheticSparseSpriteBank(): seq[byte] =
  for value in AmosSpriteBankMagic:
    result.add byte(value)
  result.addWord(3)
  # Slot zero is unused.
  for unused in 0 ..< 5:
    result.addWord(0)
  for slot in 1 .. 2:
    result.addWord(1)
    result.addWord(1)
    result.addWord(1)
    result.addWord(0)
    result.addWord(0)
    result.addWord(if slot == 1: 0x8000 else: 0)
  for index in 0 ..< AmosPaletteEntries:
    result.addWord(if index == 1: 0x0f00 else: 0)

suite "AMOS sprite and icon banks":
  test "DRAGON is detected and exposed as numbered sprite resources":
    let
      data = readBytes(FixturePath)
      candidates = detectFormats(FixturePath, data)
      inspection = inspectSource(FixturePath, data)
      resources = inspection.resources.rasterResources

    check candidates.len == 1
    check candidates[0].typeId == AmosSpriteBankTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check inspection.resources.roots.len == 1
    check inspection.resources.roots[0].path == "/sprite"
    check inspection.resources.roots[0].kind == vrnkGroup
    check resources.len == 10
    for index, resource in resources:
      check resource.path == "/sprite/" & $index
      check resource.typeId == AmosSpriteResourceTypeId
      check resource.raster.kind == vrkIndexedImage
      check resource.raster.width == 32
      check resource.raster.height == 17
      check resource.metadata.len == 2
      check resource.metadata[0].key == "hotspot.x"
      check resource.metadata[0].value.integerValue == 0
      check resource.metadata[1].key == "hotspot.y"
      check resource.metadata[1].value.integerValue == 0

  test "decoded frames match the independent GIF control":
    let resources = inspectSource(FixturePath,
      readBytes(FixturePath)).resources.rasterResources
    let expected = [
      "01A8B2779F5A84F5D7DBEB13CBF5239B9750E447",
      "B334220EDAD933CCCF67F4D9E59958D3E6D1F2A6",
      "0391C2EB2CDC158D8FCA78E8C4A321E5A385FC6C",
      "F07E4E5E8D80212BC90B7E69481223269D2C7F27",
      "4D4ED6279B75822C67418283702139A5CBCF5FDC",
      "01A8B2779F5A84F5D7DBEB13CBF5239B9750E447",
      "B334220EDAD933CCCF67F4D9E59958D3E6D1F2A6",
      "1EA5ACB748444FCCDD66CA3210526582434CBC0E",
      "B61094BCAFEE76DF2E3198EE49A3A3D7679DCE45",
      "4D4ED6279B75822C67418283702139A5CBCF5FDC"
    ]
    for index, resource in resources:
      check rgbDigest(resource.raster.image) == expected[index]

  test "icon banks retain signed hotspots and decode their palette":
    let
      data = syntheticIconBank()
      bank = parseAmosSpriteIconBank(data)
      inspection = inspectSource("pointer.aBk", data)
      resource = inspection.resources.rasterResources[0]

    check bank.kind == asibkIcon
    check bank.images[0].hotspotX == -2
    check bank.images[0].hotspotY == 3
    check inspection.selectedFormat.typeId == AmosIconBankTypeId
    check resource.path == "/icon/0"
    check resource.typeId == AmosIconResourceTypeId
    check resource.raster.image.colourAt(0, 0) == VextRgb(r: 255, g: 0, b: 0)
    check resource.metadata[0].value.integerValue == -2
    check resource.metadata[1].value.integerValue == 3

    let paletteFirst = parseAmosSpriteIconBank(syntheticIconBank(true))
    check paletteFirst.images.len == 1
    check paletteFirst.images[0].hotspotX == -2
    check paletteFirst.palette[1] == VextRgb(r: 255, g: 0, b: 0)

  test "unused slots retain the numbering of later sprite resources":
    let
      bank = parseAmosSpriteIconBank(syntheticSparseSpriteBank())
      resources = inspectSource("sparse.abk",
        syntheticSparseSpriteBank()).resources.rasterResources

    check bank.images.len == 2
    check bank.imageNumbers == @[1, 2]
    check resources.len == 2
    check resources[0].path == "/sprite/1"
    check resources[1].path == "/sprite/2"

  test "truncated and structurally inconsistent banks are rejected":
    let valid = readBytes(FixturePath)
    check not isAmosSpriteIconBank(valid[0 .. ^2])
    expect ValueError:
      discard parseAmosSpriteIconBank(valid[0 .. ^2])
    expect ValueError:
      discard inspectSource("wrong.abk", valid, AmosIconBankTypeId)
