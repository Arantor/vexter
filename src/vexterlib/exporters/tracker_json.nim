## Complete structured export for generic tracker modules.

import std/json
import ../archetypes/[audio, tracker]
import ../artifacts

proc textBytes(value: string): seq[byte] =
  for character in value: result.add byte(character)

proc noteKindName(kind: VextTrackerNoteKind): string =
  case kind
  of vtnkNone: "none"
  of vtnkTrigger: "trigger"
  of vtnkTarget: "target"
  of vtnkRelease: "release"
  of vtnkCut: "cut"

proc channelBiasName(bias: VextTrackerChannelBias): string =
  case bias
  of vtcbUnspecified: "unspecified"
  of vtcbLeft: "left"
  of vtcbCentre: "centre"
  of vtcbRight: "right"

proc effectKindName(kind: VextTrackerEffectKind): string =
  case kind
  of vtekUnknown: "unknown"
  of vtekArpeggio: "arpeggio"
  of vtekPitchSlideUp: "pitch-slide-up"
  of vtekPitchSlideDown: "pitch-slide-down"
  of vtekPortamento: "portamento"
  of vtekVibrato: "vibrato"
  of vtekTremolo: "tremolo"
  of vtekSetVolume: "set-volume"
  of vtekVolumeSlide: "volume-slide"
  of vtekSetPan: "set-pan"
  of vtekPanSlide: "pan-slide"
  of vtekSetSpeed: "set-speed"
  of vtekSetTempo: "set-tempo"
  of vtekPositionJump: "position-jump"
  of vtekPatternBreak: "pattern-break"
  of vtekPatternLoop: "pattern-loop"
  of vtekNoteDelay: "note-delay"
  of vtekNoteCut: "note-cut"
  of vtekRetrigger: "retrigger"
  of vtekSampleOffset: "sample-offset"
  of vtekSetFilter: "set-filter"
  of vtekFinePitchSlideUp: "fine-pitch-slide-up"
  of vtekFinePitchSlideDown: "fine-pitch-slide-down"
  of vtekSetGlissando: "set-glissando"
  of vtekSetVibratoWaveform: "set-vibrato-waveform"
  of vtekSetTremoloWaveform: "set-tremolo-waveform"
  of vtekSetFineTune: "set-fine-tune"
  of vtekFineVolumeSlideUp: "fine-volume-slide-up"
  of vtekFineVolumeSlideDown: "fine-volume-slide-down"
  of vtekPatternDelay: "pattern-delay"
  of vtekInvertLoop: "invert-loop"

proc loopStatusName(status: VextTrackerLoopStatus): string =
  case status
  of vtlsNotAnalysed: "not-analysed"
  of vtlsTerminates: "terminates"
  of vtlsCycles: "cycles"
  of vtlsAnalysisLimit: "analysis-limit"

proc exportTrackerJson*(module: VextTrackerModule, resourcePath = "/module",
    suggestedFilename = "tracker.json", sampleResourcePath = ""): VextArtifactSet =
  module.validate
  let samplesPath =
    if sampleResourcePath.len > 0: sampleResourcePath
    else: resourcePath & "/samples"
  var document = %*{
    "schema": "vexter.tracker.v1",
    "title": module.title,
    "timing": {
      "initialSpeed": module.initialSpeed,
      "initialTempoBpm": module.initialTempoBpm,
      "rowsPerBeat": module.rowsPerBeat
    },
    "orders": module.orders,
    "hasRestartOrder": module.hasRestartOrder,
    "loopAnalysis": {
      "status": loopStatusName(module.loopAnalysis.status),
      "transitionsExamined": module.loopAnalysis.transitionsExamined,
      "loopEntryOrder": module.loopAnalysis.loopEntryOrder,
      "loopEntryRow": module.loopAnalysis.loopEntryRow,
      "loopLengthTransitions": module.loopAnalysis.loopLengthTransitions
    }
  }
  if module.hasRestartOrder: document["restartOrder"] = %module.restartOrder
  var channels = newJArray()
  for channel in module.channels:
    channels.add %*{"name": channel.name, "sourceIndex": channel.sourceIndex,
      "bias": channelBiasName(channel.bias), "defaultPan": channel.defaultPan}
  document["channels"] = channels
  var instruments = newJArray()
  for index, instrument in module.instruments:
    instruments.add %*{
      "name": instrument.name,
      "sourceIndex": instrument.sourceIndex,
      "resourcePath": samplesPath & "/" & $(index + 1),
      "referenceNote": instrument.referenceNote,
      "fineTuneCents": instrument.fineTuneCents,
      "sampleRate": instrument.sample.sound.sampleRate,
      "bitsPerSample": instrument.sample.sound.buffer.bitsPerSample,
      "samples": instrument.sample.sound.buffer.sampleCount,
      "oneShotSamples": instrument.sample.oneShotSamples,
      "repeatSamples": instrument.sample.repeatSamples,
      "volume": instrument.sample.volume,
      "pan": instrument.sample.pan
    }
  document["instruments"] = instruments
  var patterns = newJArray()
  for pattern in module.patterns:
    var patternNode = %*{"name": pattern.name,
      "sourceIndex": pattern.sourceIndex}
    var rows = newJArray()
    for rowIndex, row in pattern.rows:
      var rowNode = %*{"index": rowIndex}
      var cells = newJArray()
      for channel, cell in row.cells:
        var cellNode = %*{"channel": channel,
          "noteKind": noteKindName(cell.noteKind),
          "hasSourcePitch": cell.hasSourcePitch,
          "hasInstrument": cell.hasInstrument,
          "hasVolume": cell.hasVolume}
        if cell.noteKind in {vtnkTrigger, vtnkTarget}:
          cellNode["note"] = %cell.note
        if cell.hasSourcePitch: cellNode["sourcePitch"] = %cell.sourcePitch
        if cell.hasInstrument: cellNode["instrument"] = %cell.instrument
        if cell.hasVolume: cellNode["volume"] = %cell.volume
        var effects = newJArray()
        for item in cell.effects:
          effects.add %*{"kind": effectKindName(item.kind),
            "parameter": item.parameter, "rawCommand": item.rawCommand,
            "rawParameter": item.rawParameter}
        cellNode["effects"] = effects
        cells.add cellNode
      rowNode["cells"] = cells
      rows.add rowNode
    patternNode["rows"] = rows
    patterns.add patternNode
  document["patterns"] = patterns
  result.artifacts.add VextArtifact(suggestedFilename: suggestedFilename,
    mediaType: "application/json",
    data: textBytes(document.pretty & "\n"))
