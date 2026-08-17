import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc addDword(data: var seq[byte], value: uint32) =
  data.add byte((value shr 24) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc genericBank(bankType = "Music", payload = @[1'u8, 2, 3]): seq[byte] =
  for value in AmosBankMagic:
    result.add byte(value)
  result.addWord(7)
  result.addWord(0x1234)
  result.addDword(0xd0000000'u32 or uint32(payload.len + 8))
  for index in 0 ..< 8:
    result.add byte(if index < bankType.len: bankType[index] else: ' ')
  result.add payload

suite "generic AMOS banks":
  test "header metadata is identified without decoding the payload":
    let
      data = genericBank()
      bank = parseAmosBank(data)
      candidates = detectFormats("song.aBK", data)
      inspection = inspectSource("song.aBK", data)
      resources = inspection.resources.leafResources

    check bank.number == 7
    check bank.flags == 0x1234
    check bank.bankType == "Music"
    check bank.dataLength == 3
    check candidates.len == 1
    check candidates[0].typeId == AmosBankTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check resources.len == 1
    check resources[0].path == "/bank"
    check resources[0].typeId == AmosBankResourceTypeId
    check resources[0].kind == vrnkOpaque
    check resources[0].metadata[0].value.integerValue == 7
    check resources[0].metadata[1].value.integerValue == 0x1234
    check resources[0].metadata[2].value.stringValue == "Music"
    check resources[0].metadata[3].value.integerValue == 3
    check inspection.resources.rasterResources.len == 0
    expect ValueError:
      discard exportResource(inspection.resources, VextExportRequest())

  test "all currently known type labels remain identifiable":
    for bankType in ["Music", "Tracker", "Amal", "Data", "Datas", "Work",
        "Asm", "Code", "Pac.Pic.", "Resource", "Samples"]:
      check parseAmosBank(genericBank(bankType)).bankType == bankType

  test "length and type validation reject malformed banks":
    var wrongLength = genericBank()
    wrongLength[11] = wrongLength[11] + 1
    check not isAmosBank(wrongLength)

    var shortLength = genericBank()
    shortLength[8] = 0
    shortLength[9] = 0
    shortLength[10] = 0
    shortLength[11] = 7
    check not isAmosBank(shortLength)

    var nonAsciiType = genericBank()
    nonAsciiType[12] = 0x80
    check not isAmosBank(nonAsciiType)

