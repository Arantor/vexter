import std/unittest
import vexterlib

const SpriteFixturePath = "tests/fixtures/amos.sprite-bank/DRAGON.Abk"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc addWord(data: var seq[byte], value: int) =
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc addDword(data: var seq[byte], value: uint32) =
  data.add byte((value shr 24) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc genericBank(): seq[byte] =
  for value in AmosBankMagic:
    result.add byte(value)
  result.addWord(4)
  result.addWord(0)
  result.addDword(10)
  for value in "Data    ":
    result.add byte(value)
  result.add @[0xaa'u8, 0x55]

proc iconBank(): seq[byte] =
  for value in AmosIconBankMagic:
    result.add byte(value)
  result.addWord(1)
  result.addWord(1)
  result.addWord(1)
  result.addWord(1)
  result.addWord(2)
  result.addWord(3)
  result.addWord(0x8000)
  for index in 0 ..< AmosPaletteEntries:
    result.addWord(if index == 1: 0x00f0 else: 0)

proc bankSet(): seq[byte] =
  for value in AmosBankSetMagic:
    result.add byte(value)
  result.addWord(3)
  result.add genericBank()
  result.add readBytes(SpriteFixturePath)
  result.add iconBank()

suite "AMOS bank sets":
  test "mixed embedded banks are validated and exposed hierarchically":
    let
      data = bankSet()
      parsed = parseAmosBankSet(data)
      candidates = detectFormats("collection.Abs", data)
      inspection = inspectSource("collection.Abs", data)
      leaves = inspection.resources.leafResources
      rasters = inspection.resources.rasterResources

    check parsed.banks.len == 3
    check parsed.banks[0].kind == absekGeneric
    check parsed.banks[0].genericBank.bankType == "Data"
    check parsed.banks[1].kind == absekSprite
    check parsed.banks[1].spriteIconBank.images.len == 10
    check parsed.banks[2].kind == absekIcon
    check parsed.banks[2].spriteIconBank.images.len == 1
    check candidates.len == 1
    check candidates[0].typeId == AmosBankSetTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check inspection.resources.roots[0].path == "/banks"
    check leaves.len == 12
    check leaves[0].path == "/banks/0"
    check leaves[0].kind == vrnkOpaque
    check leaves[0].metadata[0].value.integerValue == 4
    check rasters.len == 11
    check rasters[0].path == "/banks/1/sprite/0"
    check rasters[9].path == "/banks/1/sprite/9"
    check rasters[10].path == "/banks/2/icon/0"
    check rasters[10].metadata[0].value.integerValue == 2
    check rasters[10].metadata[1].value.integerValue == 3

    let exported = exportResource(inspection.resources,
      VextExportRequest(
        resourcePath: "/banks/2/icon/0",
        suggestedName: "icon"))
    check exported.outputFormat == "png"

  test "prefix parsing reports the exact appendix length":
    let data = bankSet()
    let parsed = parseAmosBankSetPrefix(data & @[1'u8, 2, 3])
    check parsed.bytesRead == data.len
    check parsed.bankSet.banks.len == 3

  test "count, member magic, truncation, and trailing bytes are validated":
    let valid = bankSet()

    var wrongCount = valid
    wrongCount[5] = 4
    check not isAmosBankSet(wrongCount)

    var unknown = valid
    unknown[6] = byte('N')
    check not isAmosBankSet(unknown)

    check not isAmosBankSet(valid[0 .. ^2])
    check not isAmosBankSet(valid & @[0'u8])

