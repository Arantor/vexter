import std/[json, sequtils, strutils, unittest]
import vexterlib

proc setText(data: var seq[byte], offset: int, value: string) =
  for index, character in value: data[offset + index] = byte(character)

proc setBeWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc setPatternCell(data: var seq[byte], row, channel, instrument, period,
    command, parameter: int) =
  let offset = 1084 + (row * 4 + channel) * 4
  data[offset] = byte(instrument and 0xf0 or period shr 8 and 0x0f)
  data[offset + 1] = byte(period)
  data[offset + 2] = byte((instrument and 0x0f) shl 4 or command and 0x0f)
  data[offset + 3] = byte(parameter)

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

  test "replay reserves mixer headroom and obeys filter switching":
    let filtered = renderProtracker(parseProtrackerMod(syntheticMod()).module)
    var filterOffData = syntheticMod()
    # Row 0, channel 2: E01 disables the hardware-filter approximation.
    filterOffData[1084 + 8 + 2] = 0x0e
    filterOffData[1084 + 8 + 3] = 0x01
    let unfiltered = renderProtracker(parseProtrackerMod(filterOffData).module)
    check abs(unfiltered.sound.buffer.channels[0][0]) >
      abs(filtered.sound.buffer.channels[0][0])
    check unfiltered.sound.buffer.channels[0][0] == -16_384

  test "tremolo modulates tick volume without changing base volume":
    var plainData = syntheticMod()
    plainData[45] = 32
    var tremoloData = plainData
    # Replace F06 on row 0/channel 0 with 744: speed 4, depth 4.
    tremoloData[1084 + 2] = 0x17
    tremoloData[1084 + 3] = 0x44
    let plainModule = parseProtrackerMod(plainData).module
    let tremoloModule = parseProtrackerMod(tremoloData).module
    let plain = renderProtracker(plainModule)
    let tremolo = renderProtracker(tremoloModule)
    check tremolo.sound.buffer.channels[0] != plain.sound.buffer.channels[0]
    # Replay state modulation must not rewrite the imported instrument volume.
    check tremoloModule.instruments[0].sample.volume == 0.5

  test "E7 selects the tremolo waveform":
    var sineData = syntheticMod()
    sineData[45] = 32
    # Row 1/channel 0 applies tremolo after the row-0 note has begun.
    sineData[1084 + 16 + 2] = 0x07
    sineData[1084 + 16 + 3] = 0x44
    var squareData = sineData
    # Row 0/channel 0 selects retriggered square wave for later tremolo.
    squareData[1084 + 2] = 0x1e
    squareData[1084 + 3] = 0x72
    let sine = renderProtracker(parseProtrackerMod(sineData).module)
    let square = renderProtracker(parseProtrackerMod(squareData).module)
    check square.sound.buffer.channels[0] != sine.sound.buffer.channels[0]

  test "E4 selects the vibrato waveform":
    var sineData = syntheticMod()
    # Row 1/channel 0 applies vibrato after the row-0 note has begun.
    sineData[1084 + 16 + 2] = 0x04
    sineData[1084 + 16 + 3] = 0x44
    var squareData = sineData
    # Row 0/channel 0 selects retriggered square wave for later vibrato.
    squareData[1084 + 2] = 0x1e
    squareData[1084 + 3] = 0x42
    let sine = renderProtracker(parseProtrackerMod(sineData).module)
    let square = renderProtracker(parseProtrackerMod(squareData).module)
    check square.sound.buffer.channels[0] != sine.sound.buffer.channels[0]

  test "E5 applies signed runtime fine-tune without changing the instrument":
    var normalData = syntheticMod()
    normalData[44] = 0
    # Replace F06 with E50; the note uses the runtime finetune on this row.
    normalData[1084 + 2] = 0x1e
    normalData[1084 + 3] = 0x50
    var sharpData = normalData
    sharpData[1084 + 3] = 0x57
    var flatData = normalData
    flatData[1084 + 3] = 0x58
    let normalModule = parseProtrackerMod(normalData).module
    let sharp = renderProtracker(parseProtrackerMod(sharpData).module)
    let flat = renderProtracker(parseProtrackerMod(flatData).module)
    check sharp.sound.buffer.channels[0] !=
      renderProtracker(normalModule).sound.buffer.channels[0]
    check flat.sound.buffer.channels[0] != sharp.sound.buffer.channels[0]
    check normalModule.instruments[0].fineTuneCents == 0.0

  test "E3 switches tone-portamento glissando quantisation":
    var smoothData = syntheticMod()
    smoothData[44] = 0
    # Replace F06 with E30 to select smooth portamento on channel 0.
    smoothData[1084 + 2] = 0x1e
    smoothData[1084 + 3] = 0x30
    # Row 1/channel 0: target C-3 (period 214), tone-portamento speed 3.
    smoothData[1084 + 16] = 0x00
    smoothData[1084 + 17] = 0xd6
    smoothData[1084 + 18] = 0x03
    smoothData[1084 + 19] = 0x03
    var glissandoData = smoothData
    glissandoData[1084 + 3] = 0x31
    let smooth = renderProtracker(parseProtrackerMod(smoothData).module)
    let glissando = renderProtracker(parseProtrackerMod(glissandoData).module)
    check glissando.sound.buffer.channels[0] != smooth.sound.buffer.channels[0]

  test "instrument-only rows do not replace the sample already playing":
    var unchangedData = syntheticMod()
    # Add a distinct four-byte second instrument with the same volume.
    unchangedData.setBeWord(72, 2)
    unchangedData[75] = 64
    unchangedData.setBeWord(76, 0)
    unchangedData.setBeWord(78, 2)
    unchangedData.add @[0x20'u8, 0x30, 0x40, 0x50]
    var selectedData = unchangedData
    unchangedData.setPatternCell(1, 0, 1, 0, 0, 0)
    selectedData.setPatternCell(1, 0, 2, 0, 0, 0)
    let unchanged = renderProtracker(parseProtrackerMod(unchangedData).module)
    let selected = renderProtracker(parseProtrackerMod(selectedData).module)
    check selected.sound.buffer.channels[0] ==
      unchanged.sound.buffer.channels[0]

  test "note delay retains the old sample until the delayed instrument starts":
    var instrumentOnlyData = syntheticMod()
    instrumentOnlyData.setBeWord(72, 2)
    instrumentOnlyData[75] = 64
    instrumentOnlyData.setBeWord(76, 0)
    instrumentOnlyData.setBeWord(78, 2)
    instrumentOnlyData.add @[0x20'u8, 0x30, 0x40, 0x50]
    instrumentOnlyData.setPatternCell(1, 0, 2, 0, 0, 0)
    var delayedData = instrumentOnlyData
    delayedData.setPatternCell(1, 0, 2, 428, 14, 0xd2)
    let instrumentOnly = renderProtracker(
      parseProtrackerMod(instrumentOnlyData).module)
    let delayed = renderProtracker(parseProtrackerMod(delayedData).module)
    let rowStart = 6 * 882
    let delayedStart = rowStart + 2 * 882
    check delayed.sound.buffer.channels[0][rowStart ..< delayedStart] ==
      instrumentOnly.sound.buffer.channels[0][rowStart ..< delayedStart]
    check delayed.sound.buffer.channels[0][delayedStart ..< delayedStart + 882] !=
      instrumentOnly.sound.buffer.channels[0][delayedStart ..< delayedStart + 882]

  test "900 reuses channel sample-offset memory and preserves overflow rules":
    var rememberedData = syntheticMod()
    rememberedData.setBeWord(42, 150)
    rememberedData.setBeWord(48, 1)
    rememberedData.setLen(1084 + 1024 + 300)
    for index in 0 ..< 300:
      rememberedData[1084 + 1024 + index] = byte(index and 0x7f)
    rememberedData.setPatternCell(0, 0, 1, 428, 9, 1)
    rememberedData.setPatternCell(1, 0, 0, 428, 9, 0)
    var noSecondOffsetData = rememberedData
    noSecondOffsetData.setPatternCell(1, 0, 0, 428, 0, 0)
    let remembered = renderProtracker(
      parseProtrackerMod(rememberedData).module)
    let noSecondOffset = renderProtracker(
      parseProtrackerMod(noSecondOffsetData).module)
    check remembered.sound.buffer.channels[0] !=
      noSecondOffset.sound.buffer.channels[0]

  test "blank rows preserve vibrato phase while 400 reuses its memory":
    var blankData = syntheticMod()
    blankData.setPatternCell(0, 0, 1, 428, 4, 0x44)
    blankData.setPatternCell(1, 0, 0, 0, 0, 0)
    blankData.setPatternCell(1, 3, 0, 0, 0, 0)
    blankData.setPatternCell(2, 0, 0, 0, 4, 0)
    blankData.setPatternCell(2, 3, 0, 0, 11, 0)
    var activeData = blankData
    activeData.setPatternCell(1, 0, 0, 0, 4, 0)
    let blank = renderProtracker(parseProtrackerMod(blankData).module)
    let active = renderProtracker(parseProtrackerMod(activeData).module)
    let thirdRow = 12 * 882
    check active.sound.buffer.channels[0][thirdRow ..< thirdRow + 882] !=
      blank.sound.buffer.channels[0][thirdRow ..< thirdRow + 882]

  test "volume slide ignores the down nibble when the up nibble is nonzero":
    var upOnlyData = syntheticMod()
    upOnlyData.setPatternCell(0, 0, 1, 428, 10, 0x10)
    var bothData = upOnlyData
    bothData.setPatternCell(0, 0, 1, 428, 10, 0x1f)
    let upOnly = renderProtracker(parseProtrackerMod(upOnlyData).module)
    let both = renderProtracker(parseProtrackerMod(bothData).module)
    check both.sound.buffer.channels[0] == upOnly.sound.buffer.channels[0]

  test "E9 retriggers on tick zero only when the row has no note":
    var plainData = syntheticMod()
    plainData.setPatternCell(1, 0, 0, 0, 0, 0)
    var retriggerData = plainData
    retriggerData.setPatternCell(1, 0, 0, 0, 14, 0x91)
    let plain = renderProtracker(parseProtrackerMod(plainData).module)
    let retrigger = renderProtracker(parseProtrackerMod(retriggerData).module)
    check retrigger.sound.buffer.channels[0] != plain.sound.buffer.channels[0]

  test "EF mutates only replay-private loop data and persists until disabled":
    let plainModule = parseProtrackerMod(syntheticMod()).module
    var funkData = syntheticMod()
    funkData.setPatternCell(0, 0, 1, 428, 14, 0xff)
    let funkModule = parseProtrackerMod(funkData).module
    let originalSamples = funkModule.instruments[0].sample.sound.buffer.channels[0]
    let first = renderProtracker(funkModule)
    let second = renderProtracker(funkModule)
    check first.sound.buffer.channels[0] !=
      renderProtracker(plainModule).sound.buffer.channels[0]
    check second.sound.buffer.channels[0] == first.sound.buffer.channels[0]
    check funkModule.instruments[0].sample.sound.buffer.channels[0] ==
      originalSamples

    var stoppedData = funkData
    stoppedData.setPatternCell(1, 0, 0, 0, 14, 0xf0)
    let stopped = renderProtracker(parseProtrackerMod(stoppedData).module)
    check stopped.sound.buffer.channels[0] != first.sound.buffer.channels[0]

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
