## Generic pattern/order tracker music values, independent of source format.

import std/math
import ./audio

type
  VextTrackerChannelBias* = enum
    vtcbUnspecified
    vtcbLeft
    vtcbCentre
    vtcbRight

  VextTrackerNoteKind* = enum
    vtnkNone
    vtnkTrigger
    vtnkTarget
    vtnkRelease
    vtnkCut

  VextTrackerEffectKind* = enum
    vtekUnknown
    vtekArpeggio
    vtekPitchSlideUp
    vtekPitchSlideDown
    vtekPortamento
    vtekVibrato
    vtekTremolo
    vtekSetVolume
    vtekVolumeSlide
    vtekSetPan
    vtekPanSlide
    vtekSetSpeed
    vtekSetTempo
    vtekPositionJump
    vtekPatternBreak
    vtekPatternLoop
    vtekNoteDelay
    vtekNoteCut
    vtekRetrigger
    vtekSampleOffset
    vtekSetFilter
    vtekFinePitchSlideUp
    vtekFinePitchSlideDown
    vtekSetGlissando
    vtekSetVibratoWaveform
    vtekSetTremoloWaveform
    vtekSetFineTune
    vtekFineVolumeSlideUp
    vtekFineVolumeSlideDown
    vtekPatternDelay
    vtekInvertLoop

  VextTrackerLoopStatus* = enum
    vtlsNotAnalysed
    vtlsTerminates
    vtlsCycles
    vtlsAnalysisLimit

  VextTrackerChannel* = object
    name*: string
    sourceIndex*: int
    bias*: VextTrackerChannelBias
    ## Nominal stereo position from -1 (left) through 0 (centre) to 1 (right).
    defaultPan*: float64

  VextTrackerEffect* = object
    kind*: VextTrackerEffectKind
    parameter*: int
    ## Exact source values remain available when semantic support is partial.
    rawCommand*: int
    rawParameter*: int

  VextTrackerCell* = object
    noteKind*: VextTrackerNoteKind
    ## MIDI-style semitone number when noteKind is vtnkTrigger.
    note*: int
    hasSourcePitch*: bool
    ## Format-native period/frequency/key value used to derive the note.
    sourcePitch*: int
    hasInstrument*: bool
    ## Index into module.instruments when hasInstrument is true.
    instrument*: int
    hasVolume*: bool
    ## Normalized source volume from 0 through 1.
    volume*: float64
    effects*: seq[VextTrackerEffect]

  VextTrackerRow* = object
    cells*: seq[VextTrackerCell]

  VextTrackerPattern* = object
    name*: string
    sourceIndex*: int
    rows*: seq[VextTrackerRow]

  VextTrackerInstrument* = object
    name*: string
    sourceIndex*: int
    sample*: VextSampledInstrument
    ## MIDI-style reference note for the sample's natural playback pitch.
    referenceNote*: int
    fineTuneCents*: float64

  VextTrackerLoopAnalysis* = object
    status*: VextTrackerLoopStatus
    transitionsExamined*: int
    loopEntryOrder*: int
    loopEntryRow*: int
    loopLengthTransitions*: int

  VextTrackerModule* = object
    title*: string
    channels*: seq[VextTrackerChannel]
    instruments*: seq[VextTrackerInstrument]
    patterns*: seq[VextTrackerPattern]
    ## Pattern indices in playback order. Repeated indices remain significant.
    orders*: seq[int]
    hasRestartOrder*: bool
    ## Order at which intentional restart occurs when present.
    restartOrder*: int
    initialSpeed*: int
    initialTempoBpm*: float64
    rowsPerBeat*: int
    loopAnalysis*: VextTrackerLoopAnalysis

proc validate*(module: VextTrackerModule) =
  if module.channels.len == 0:
    raise newException(ValueError, "tracker module must contain channels")
  if module.patterns.len == 0:
    raise newException(ValueError, "tracker module must contain patterns")
  if module.orders.len == 0:
    raise newException(ValueError, "tracker module must contain an order list")
  if module.initialSpeed <= 0 or module.initialTempoBpm <= 0 or
      module.initialTempoBpm.classify in {fcNan, fcInf, fcNegInf} or
      module.rowsPerBeat <= 0:
    raise newException(ValueError, "tracker module has invalid initial timing")
  for index, channel in module.channels:
    if channel.sourceIndex < 0 or channel.defaultPan < -1 or
        channel.defaultPan > 1 or
        channel.defaultPan.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "tracker channel is invalid")
    for previous in 0 ..< index:
      if module.channels[previous].sourceIndex == channel.sourceIndex:
        raise newException(ValueError,
          "tracker channels contain duplicate source indices")
  for index, instrument in module.instruments:
    if instrument.sourceIndex < 0 or instrument.referenceNote notin 0 .. 127 or
        instrument.fineTuneCents.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "tracker instrument is invalid")
    instrument.sample.sound.buffer.validate
    let sampleCount = instrument.sample.sound.buffer.sampleCount
    if instrument.sample.sound.sampleRate <= 0 or
        instrument.sample.oneShotSamples < 0 or
        instrument.sample.repeatSamples < 0 or
        instrument.sample.oneShotSamples + instrument.sample.repeatSamples >
          sampleCount or instrument.sample.volume < 0 or
        instrument.sample.volume > 1 or
        instrument.sample.volume.classify in {fcNan, fcInf, fcNegInf} or
        instrument.sample.pan < -1 or instrument.sample.pan > 1 or
        instrument.sample.pan.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "tracker sampled instrument is invalid")
    for previous in 0 ..< index:
      if module.instruments[previous].sourceIndex == instrument.sourceIndex:
        raise newException(ValueError,
          "tracker instruments contain duplicate source indices")
  for index, pattern in module.patterns:
    if pattern.sourceIndex < 0 or pattern.rows.len == 0:
      raise newException(ValueError, "tracker pattern is invalid")
    for previous in 0 ..< index:
      if module.patterns[previous].sourceIndex == pattern.sourceIndex:
        raise newException(ValueError,
          "tracker patterns contain duplicate source indices")
    for row in pattern.rows:
      if row.cells.len != module.channels.len:
        raise newException(ValueError,
          "tracker row cell count does not match its channels")
      for cell in row.cells:
        if cell.noteKind in {vtnkTrigger, vtnkTarget} and
            cell.note notin 0 .. 127:
          raise newException(ValueError, "tracker note is outside MIDI range")
        if cell.hasInstrument and (cell.instrument < 0 or
            cell.instrument >= module.instruments.len):
          raise newException(ValueError,
            "tracker cell references a missing instrument")
        if cell.hasVolume and (cell.volume < 0 or cell.volume > 1 or
            cell.volume.classify in {fcNan, fcInf, fcNegInf}):
          raise newException(ValueError, "tracker cell volume is invalid")
  for patternIndex in module.orders:
    if patternIndex < 0 or patternIndex >= module.patterns.len:
      raise newException(ValueError,
        "tracker order references a missing pattern")
  if module.hasRestartOrder and (module.restartOrder < 0 or
      module.restartOrder >= module.orders.len):
    raise newException(ValueError, "tracker restart order is invalid")
  let analysis = module.loopAnalysis
  if analysis.transitionsExamined < 0 or analysis.loopLengthTransitions < 0:
    raise newException(ValueError, "tracker loop analysis counts are invalid")
  if analysis.status == vtlsCycles:
    if analysis.loopEntryOrder < 0 or
        analysis.loopEntryOrder >= module.orders.len or
        analysis.loopEntryRow < 0 or
        analysis.loopEntryRow >=
          module.patterns[module.orders[analysis.loopEntryOrder]].rows.len or
        analysis.loopLengthTransitions <= 0:
      raise newException(ValueError, "tracker cycle analysis is invalid")
