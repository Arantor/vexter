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

proc sampleBankPayload(): seq[byte] =
  result.addWord(2)
  result.addDword(10)
  result.addDword(28)
  for value in "ONE     ": result.add byte(value)
  result.addWord(8364)
  result.addDword(4)
  result.add @[0x80'u8, 0, 0x7f, 0xff]
  for value in "TWO     ": result.add byte(value)
  result.addWord(8363)
  result.addDword(3)
  result.add @[1'u8, 2, 3]

proc genericBank(payload: openArray[byte]): seq[byte] =
  for value in AmosBankMagic: result.add byte(value)
  result.addWord(5)
  result.addWord(0)
  result.addDword(payload.len + AmosBankStoredLengthOverhead)
  for value in "Samples ": result.add byte(value)
  result.add payload

suite "AMOS sample banks":
  test "records become named signed eight-bit sampled instruments":
    let
      payload = sampleBankPayload()
      parsed = parseAmosSampleBank(payload)
      inspection = inspectSource("samples.abk", genericBank(payload))
      root = inspection.resources.roots[0]
      first = root.children[0]

    check parsed.samples.len == 2
    check parsed.samples[0].name == "ONE"
    check parsed.samples[0].sampleRate == 8364
    check parsed.samples[0].data == @[0x80'u8, 0, 0x7f, 0xff]
    check root.path == "/bank"
    check root.typeId == AmosSamplesResourceTypeId
    check root.kind == vrnkGroup
    check root.children.len == 2
    check first.path == "/bank/sample/1"
    check first.typeId == AmosSampleResourceTypeId
    check first.audioKind == varkSampledInstrument
    check first.instrument.sound.buffer.channels == @[@[-128'i32, 0, 127, -1]]
    check first.instrument.sound.sampleRate == 8364
    check first.instrument.oneShotSamples == 4

    let exported = exportResource(inspection.resources,
      VextExportRequest(resourcePath: first.path, suggestedName: "one"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].suggestedFilename == "one.wav"

  test "offsets, lengths, rates, and trailing bytes are validated":
    var badOffset = sampleBankPayload()
    badOffset[5] = 11
    expect ValueError: discard parseAmosSampleBank(badOffset)

    var badRate = sampleBankPayload()
    badRate[18] = 0
    badRate[19] = 0
    expect ValueError: discard parseAmosSampleBank(badRate)

    var trailing = sampleBankPayload()
    trailing.add 0
    expect ValueError: discard parseAmosSampleBank(trailing)
