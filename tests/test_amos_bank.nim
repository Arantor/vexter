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

proc empty15SampleMod(): seq[byte] =
  result = newSeq[byte](600 + 1024)
  for index, value in "BANKED MODULE":
    result[index] = byte(value)
  result[470] = 1
  result[471] = 127

suite "generic AMOS banks":
  test "header metadata is identified without decoding the payload":
    let
      data = genericBank("Mystery")
      bank = parseAmosBank(data)
      candidates = detectFormats("song.aBK", data)
      inspection = inspectSource("song.aBK", data)
      resources = inspection.resources.leafResources

    check bank.number == 7
    check bank.flags == 0x1234
    check bank.bankType == "Mystery"
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
    check resources[0].metadata[2].value.stringValue == "Mystery"
    check resources[0].metadata[3].value.integerValue == 3
    check inspection.resources.rasterResources.len == 0
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "song"))
    check exported.outputFormat == "bin"
    check exported.artifacts.artifacts[0].suggestedFilename == "song.bin"
    check exported.artifacts.artifacts[0].data == @[1'u8, 2, 3]

  test "all currently known type labels remain identifiable":
    for bankType in ["Music", "Tracker", "Amal", "Data", "Datas", "Work",
        "Asm", "Code", "Menu", "Pac.Pic.", "Resource", "Samples"]:
      check parseAmosBank(genericBank(bankType)).bankType == bankType

  test "Asm and Code banks are exportable 680x0 assembly resources":
    for bankType in ["Asm", "Code"]:
      let
        payload = @[0x4e'u8, 0x75]
        inspection = inspectSource(bankType & ".abk",
          genericBank(bankType, payload))
        resources = inspection.resources.leafResources

      check resources.len == 1
      check resources[0].path == "/bank"
      check resources[0].typeId == AmosAssemblyResourceTypeId
      check resources[0].kind == vrnkOpaque
      check resources[0].rawDataAvailable
      check resources[0].metadata[2].value.stringValue == bankType

      let exported = exportResource(inspection.resources,
        VextExportRequest(suggestedName: bankType))
      check exported.outputFormat == "bin"
      check exported.artifacts.artifacts[0].data == payload

  test "Data, Datas, and Work banks are exportable opaque binary data":
    for bankType in ["Data", "Datas", "Work"]:
      let
        payload = @[0xde'u8, 0xad, 0xbe, 0xef]
        inspection = inspectSource(bankType & ".abk",
          genericBank(bankType, payload))
        resource = inspection.resources.leafResources[0]

      check resource.path == "/bank"
      check resource.typeId == AmosDataResourceTypeId
      check resource.kind == vrnkOpaque
      check resource.rawDataAvailable
      check resource.metadata[2].value.stringValue == bankType

      let exported = exportResource(inspection.resources,
        VextExportRequest(suggestedName: bankType))
      check exported.outputFormat == "bin"
      check exported.artifacts.artifacts[0].data == payload

  test "reserved AMOS banks have distinct exportable opaque types":
    for (bankType, resourceType) in [
        ("Music", AmosMusicResourceTypeId),
        ("Amal", AmosAmalResourceTypeId),
        ("Menu", AmosMenuResourceTypeId)]:
      let
        payload = @[1'u8, 3, 3, 7]
        inspection = inspectSource(bankType & ".abk",
          genericBank(bankType, payload))
        resource = inspection.resources.leafResources[0]

      check resource.path == "/bank"
      check resource.typeId == resourceType
      check resource.kind == vrnkOpaque
      check resource.rawDataAvailable
      check resource.metadata[2].value.stringValue == bankType

      let exported = exportResource(inspection.resources,
        VextExportRequest(suggestedName: bankType))
      check exported.outputFormat == "bin"
      check exported.artifacts.artifacts[0].data == payload

  test "Tracker banks expose exact and AMOS-padded Protracker modules":
    let moduleData = empty15SampleMod()
    for paddingLength in [0, 32]:
      let inspection = inspectSource("tracker.abk",
        genericBank("Tracker", moduleData & newSeq[byte](paddingLength)))
      let resource = inspection.resources.roots[0]

      check resource.path == "/bank"
      check resource.typeId == ProtrackerModTypeId
      check resource.kind == vrnkTracker
      check resource.tracker.title == "BANKED MODULE"
      check resource.tracker.channels.len == 4
      check resource.tracker.patterns.len == 1
      check resource.tracker.orders == @[0]
      check resource.trackerSampleResourcePath == "/bank/samples"
      check resource.children[0].path == "/bank/patterns"
      check resource.children[1].path == "/bank/samples"
      check resource.children[2].path == "/bank/rendered-audio"

      let exported = exportResource(inspection.resources,
        VextExportRequest(outputFormat: "tracker-json",
          suggestedName: "tracker"))
      check exported.outputFormat == "tracker-json"

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
