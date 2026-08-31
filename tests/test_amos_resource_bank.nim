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

proc partialPicture(): seq[byte] =
  result = @[0x06'u8, 0x07, 0x19, 0x63]
  result.addWord(0)
  result.addWord(0)
  result.addWord(1)
  result.addWord(1)
  result.addWord(1)
  result.addWord(1)
  result.addDword(25)
  result.addDword(26)
  result.add @[0x80'u8, 0, 0]

proc resourcePayload(): seq[byte] =
  var graphic: seq[byte]
  graphic.addWord(1)
  graphic.addDword(80)
  graphic.add @[0'u8, 1, 0, 0]
  graphic.addWord(0x0123)
  for unused in 1 ..< 32: graphic.addWord(0)
  graphic.addWord(0)
  graphic.add @[0'u8, 1, 0xab, 0xcd]
  graphic.add partialPicture()

  var stringRecord: seq[byte]
  stringRecord.addWord(9)
  for value in "My String": stringRecord.add byte(value)
  stringRecord.add @[0'u8, 0xff, 0]

  result.addWord(2)
  result.addDword(18)
  result.addDword(18 + graphic.len)
  result.addDword(graphic.len)
  result.addDword(stringRecord.len)
  result.add graphic
  result.add stringRecord

proc sparseResourcePayload(): seq[byte] =
  result = resourcePayload()
  result.setLen(result.len - 2)
  result.add @[0'u8, 0, 5]
  for value in "Third": result.add byte(value)
  result.add @[0'u8, 0xff, 0]
  result[17] = 23

proc graphicOnlyPayload(): seq[byte] =
  result = resourcePayload()
  let graphicLength = int(result[13])
  result.setLen(18 + graphicLength)
  for index in 6 .. 9: result[index] = 0
  for index in 14 .. 17: result[index] = 0

proc genericBank(payload: openArray[byte]): seq[byte] =
  for value in AmosBankMagic: result.add byte(value)
  result.addWord(16)
  result.addWord(1)
  result.addDword(payload.len + AmosBankStoredLengthOverhead)
  for value in "Resource": result.add byte(value)
  result.add payload

suite "AMOS resource banks":
  test "graphics and strings become selectable resources":
    let
      payload = resourcePayload()
      parsed = parseAmosResourceBank(payload)
      inspection = inspectSource("resource.abk", genericBank(payload))
      root = inspection.resources.roots[0]
      graphics = root.children[0]
      strings = root.children[1]
      graphic = graphics.children[0]
      text = strings.children[0]

    check parsed.graphics.len == 1
    check parsed.strings == @["My String"]
    check root.typeId == AmosResourceResourceTypeId
    check root.kind == vrnkGroup
    check graphics.path == "/bank/graphics"
    check graphics.typeId == AmosResourceGraphicsTypeId
    check strings.path == "/bank/strings"
    check strings.typeId == AmosResourceStringsTypeId
    check graphic.path == "/bank/graphics/1"
    check graphic.typeId == AmosResourceGraphicTypeId
    check graphic.raster.image.width == 8
    check graphic.raster.image.height == 1
    check graphic.raster.image.pixelAt(0, 0) == 1
    check text.path == "/bank/strings/1"
    check text.typeId == AmosResourceStringTypeId
    check text.kind == vrnkText
    check text.text == "My String"

    check exportResource(inspection.resources, VextExportRequest(
      resourcePath: graphic.path, suggestedName: "graphic")).outputFormat == "png"
    check exportResource(inspection.resources, VextExportRequest(
      resourcePath: text.path, suggestedName: "string")).outputFormat == "txt"

  test "directory and string boundaries are validated":
    var badDirectory = resourcePayload()
    badDirectory[9] = badDirectory[9] + 1
    expect ValueError: discard parseAmosResourceBank(badDirectory)

    var badString = resourcePayload()
    badString[^3] = 1
    expect ValueError: discard parseAmosResourceBank(badString)

  test "empty string slots preserve later source indices":
    let
      payload = sparseResourcePayload()
      parsed = parseAmosResourceBank(payload)
      root = inspectSource("sparse.abk", genericBank(payload)).resources.roots[0]
      strings = root.children[1]
    check parsed.strings == @["My String", "", "Third"]
    check strings.children[0].path == "/bank/strings/1"
    check strings.children[1].path == "/bank/strings/3"
    check strings.children[1].text == "Third"

  test "zero offset and length represent an absent string section":
    let
      payload = graphicOnlyPayload()
      parsed = parseAmosResourceBank(payload)
      root = inspectSource("graphic.abk", genericBank(payload)).resources.roots[0]
    check parsed.graphics.len == 1
    check parsed.strings.len == 0
    check root.children.len == 1
    check root.children[0].path == "/bank/graphics"
