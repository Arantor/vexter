import std/[json, sequtils, strutils, unittest]
import vexterlib

proc setText(data: var seq[byte], offset: int, value: string) =
  for index, character in value: data[offset + index] = byte(character)

proc setBeWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc syntheticMod(sampleCount = 31): seq[byte] =
  let patternOffset = if sampleCount == 31: 1084 else: 600
  result = newSeq[byte](patternOffset + 1024 + 4)
  result.setText(0, "TEST MODULE")
  result.setText(20, "LOOPED SAMPLE")
  result.setBeWord(42, 2) # Four signed eight-bit samples.
  result[44] = 15 # Fine tune -1.
  result[45] = 64
  result.setBeWord(48, 2) # Four-byte repeating region.
  let songOffset = 20 + sampleCount * 30
  result[songOffset] = 1
  result[songOffset + 1] = 127
  if sampleCount == 31: result.setText(1080, "M.K.")
  # Row 0, channel 0: sample 1, C-2 period 428, set speed 6.
  result[patternOffset] = 0x01
  result[patternOffset + 1] = 0xac
  result[patternOffset + 2] = 0x1f
  result[patternOffset + 3] = 0x06
  # Row 0, channel 1: sample 2. Internally this becomes instrument index 1;
  # tracker presentation turns it back into the source number 02.
  result[patternOffset + 4] = 0x01
  result[patternOffset + 5] = 0xac
  result[patternOffset + 6] = 0x20
  # Row 1, channel 3: jump to order zero, proving a two-row cycle.
  let jumpOffset = patternOffset + (4 + 3) * 4
  result[jumpOffset + 2] = 0x0b
  result[jumpOffset + 3] = 0
  result[^4] = 0x80
  result[^3] = 0
  result[^2] = 0x7f
  result[^1] = 0xff

proc bytesString(data: openArray[byte]): string =
  for value in data: result.add char(value)

suite "Protracker MOD":
  test "marked modules expose tracker structure and sampled instruments":
    let inspection = inspectSource("example.mod", syntheticMod())
    check inspection.selectedFormat.typeId == ProtrackerModTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.kind == vrnkTracker
    check resource.path == ProtrackerModResourcePath
    check resource.tracker.channels.len == 4
    check resource.tracker.channels[0].bias == vtcbLeft
    check resource.tracker.channels[1].bias == vtcbRight
    check resource.tracker.orders == @[0]
    check resource.tracker.patterns[0].rows.len == 64
    let cell = resource.tracker.patterns[0].rows[0].cells[0]
    check cell.noteKind == vtnkTrigger
    check cell.note == 36
    check cell.sourcePitch == 428
    check cell.instrument == 0
    check resource.tracker.patterns[0].rows[0].cells[1].instrument == 1
    check cell.effects[0].kind == vtekSetSpeed
    check resource.tracker.loopAnalysis.status == vtlsCycles
    check resource.tracker.loopAnalysis.loopLengthTransitions == 2
    let instrument = resource.tracker.instruments[0]
    check instrument.fineTuneCents == -12.5
    check instrument.sample.sound.buffer.channels[0] ==
      @[-128'i32, 0, 127, -1]
    check instrument.sample.oneShotSamples == 0
    check instrument.sample.repeatSamples == 4
    check resource.children.len == 3
    check resource.children[0].path == "/module/patterns"
    check resource.children[0].children[0].kind == vrnkTracker
    check resource.children[0].children[0].tracker.patterns[0].sourceIndex == 0
    check resource.children[1].path == "/module/samples"
    check resource.children[1].children[0].kind == vrnkAudio
    check resource.children[2].path == "/module/rendered-audio"
    check resource.children[2].kind == vrnkAudio
    check resource.children[2].soundMaterializer != nil
    let rendered = resource.children[2].audioSound
    check rendered.buffer.channels.len == 2
    check rendered.buffer.sampleCount > 0
    check rendered.buffer.channels[0].anyIt(it != 0)

    let mix = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/module/rendered-audio", outputFormat: "wav",
      suggestedName: "mix"))
    check mix.artifacts.artifacts[0].data.bytesString.startsWith("RIFF")

    let wav = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/module/samples/1", outputFormat: "wav",
      suggestedName: "sample"))
    check wav.artifacts.artifacts[0].data.bytesString.startsWith("RIFF")

  test "tracker JSON preserves patterns, raw effects, and sample references":
    let inspection = inspectSource("example.mod", syntheticMod())
    let exported = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/module", outputFormat: "tracker-json",
      suggestedName: "module"))
    let document = parseJson(exported.artifacts.artifacts[0].data.bytesString)
    check document["schema"].getStr == "vexter.tracker.v1"
    check document["instruments"][0]["resourcePath"].getStr ==
      "/module/samples/1"
    let patternExport = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/module/patterns/0", outputFormat: "tracker-json",
      suggestedName: "pattern"))
    let patternDocument = parseJson(
      patternExport.artifacts.artifacts[0].data.bytesString)
    check patternDocument["patterns"].len == 1
    check patternDocument["instruments"][0]["resourcePath"].getStr ==
      "/module/samples/1"
    let effect = document["patterns"][0]["rows"][0]["cells"][0]["effects"][0]
    check effect["kind"].getStr == "set-speed"
    check effect["rawCommand"].getInt == 15
    check effect["rawParameter"].getInt == 6

  test "structurally exact unmarked 15-sample modules are probable":
    let inspection = inspectSource("old.mod", syntheticMod(15))
    check inspection.selectedFormat.typeId == ProtrackerModTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    check inspection.resources.roots[0].tracker.instruments.len == 15

  test "invalid sample references and trailing data are rejected":
    var badReference = syntheticMod()
    badReference[1084] = 0xf1
    badReference[1084 + 2] = 0xf0
    expect ValueError: discard parseProtrackerMod(badReference)
    var trailing = syntheticMod()
    trailing.add 0
    expect ValueError: discard parseProtrackerMod(trailing)
