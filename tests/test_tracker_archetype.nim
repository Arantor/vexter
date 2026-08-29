import std/[json, unittest]
import vexterlib

proc instrument(): VextTrackerInstrument =
  VextTrackerInstrument(name: "Lead", sourceIndex: 1, referenceNote: 60,
    fineTuneCents: -12.5, sample: VextSampledInstrument(
      sound: VextSound(sampleRate: 8287,
        buffer: VextAudioBuffer(bitsPerSample: 8,
          channels: @[@[-128'i32, 0, 127, 0]])),
      oneShotSamples: 2, repeatSamples: 2, samplesPerHighCycle: 32,
      volume: 0.75, pan: 0.0))

proc validModule(): VextTrackerModule =
  let empty = VextTrackerCell()
  let note = VextTrackerCell(noteKind: vtnkTrigger, note: 60,
    hasSourcePitch: true, sourcePitch: 428, hasInstrument: true,
    instrument: 0, hasVolume: true, volume: 0.75,
    effects: @[VextTrackerEffect(kind: vtekPitchSlideUp, parameter: 3,
      rawCommand: 1, rawParameter: 3)])
  VextTrackerModule(title: "Example",
    channels: @[
      VextTrackerChannel(name: "Left", sourceIndex: 0,
        bias: vtcbLeft, defaultPan: -1.0),
      VextTrackerChannel(name: "Right", sourceIndex: 1,
        bias: vtcbRight, defaultPan: 1.0)],
    instruments: @[instrument()],
    patterns: @[
      VextTrackerPattern(name: "A", sourceIndex: 0,
        rows: @[VextTrackerRow(cells: @[note, empty])]),
      VextTrackerPattern(name: "B", sourceIndex: 1,
        rows: @[VextTrackerRow(cells: @[empty, empty])])],
    orders: @[0, 1, 0], hasRestartOrder: true, restartOrder: 0,
    initialSpeed: 6, initialTempoBpm: 125, rowsPerBeat: 4,
    loopAnalysis: VextTrackerLoopAnalysis(status: vtlsCycles,
      transitionsExamined: 3, loopEntryOrder: 0, loopEntryRow: 0,
      loopLengthTransitions: 3))

suite "tracker archetype":
  test "patterns, repeated orders, channel bias, instruments, and effects validate":
    let module = validModule()
    module.validate
    check module.orders == @[0, 1, 0]
    check module.channels[0].defaultPan == -1.0
    check module.patterns[0].rows[0].cells[0].sourcePitch == 428
    check module.patterns[0].rows[0].cells[0].effects[0].kind ==
      vtekPitchSlideUp
    check module.loopAnalysis.status == vtlsCycles

  test "invalid cross-references and loop analysis are rejected":
    var module = validModule()
    module.orders[1] = 4
    expect ValueError: module.validate
    module = validModule()
    module.patterns[0].rows[0].cells.setLen(1)
    expect ValueError: module.validate
    module = validModule()
    module.patterns[0].rows[0].cells[0].instrument = 2
    expect ValueError: module.validate
    module = validModule()
    module.loopAnalysis.loopLengthTransitions = 0
    expect ValueError: module.validate

  test "absent optional cell and restart values need no sentinel":
    var module = validModule()
    module.hasRestartOrder = false
    module.restartOrder = 999
    module.patterns[0].rows[0].cells[1].instrument = 999
    module.validate

  test "tracker resources report structural summaries without becoming audio":
    let resource = VextResourceNode(path: "/module", typeId: "test.tracker",
      kind: vrnkTracker, tracker: validModule())
    check resource.exportFormatsFor.len == 3
    check resource.exportFormatsFor[0].id == "tracker-json"
    check resource.defaultExportFormat == "tracker-json"
    let artifact = exportMetadataJson(resource).artifacts[0]
    var contents = ""
    for value in artifact.data: contents.add char(value)
    let document = parseJson(contents)
    check document["kind"].getStr == "tracker"
    check document["resource"]["archetype"].getStr == "VextTrackerModule"
    check document["resource"]["channels"].getInt == 2
    check document["resource"]["orders"].len == 3
