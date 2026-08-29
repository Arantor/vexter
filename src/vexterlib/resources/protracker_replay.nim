## Bounded ProTracker replay into generic stereo PCM.

import std/[math, sets]
import ../archetypes/[audio, tracker]

const
  ProtrackerReplaySampleRate* = 44_100
  MaximumProtrackerReplaySeconds* = 300
  PaulaClock = 7_093_789.2
  FixedPointScale = 4_294_967_296.0
  ProtrackerReplayFilterCutoffHz* = 4_500.0
  # Integer period sections used by ProTracker 2.3F. The nibble order is
  # +0..+7, -8..-1, matching both instrument headers and E5x.
  ProtrackerFineTunePeriods: array[16, array[36, int]] = [
    [856,808,762,720,678,640,604,570,538,508,480,453,428,404,381,360,339,320,302,285,269,254,240,226,214,202,190,180,170,160,151,143,135,127,120,113],
    [850,802,757,715,674,637,601,567,535,505,477,450,425,401,379,357,337,318,300,284,268,253,239,225,213,201,189,179,169,159,150,142,134,126,119,113],
    [844,796,752,709,670,632,597,563,532,502,474,447,422,398,376,355,335,316,298,282,266,251,237,224,211,199,188,177,167,158,149,141,133,125,118,112],
    [838,791,746,704,665,628,592,559,528,498,470,444,419,395,373,352,332,314,296,280,264,249,235,222,209,198,187,176,166,157,148,140,132,125,118,111],
    [832,785,741,699,660,623,588,555,524,495,467,441,416,392,370,350,330,312,294,278,262,247,233,220,208,196,185,175,165,156,147,139,131,124,117,110],
    [826,779,736,694,655,619,584,551,520,491,463,437,413,390,368,347,328,309,292,276,260,245,232,219,206,195,184,174,164,155,146,138,130,123,116,109],
    [820,774,730,689,651,614,580,547,516,487,460,434,410,387,365,345,325,307,290,274,258,244,230,217,205,193,183,172,163,154,145,137,129,122,115,109],
    [814,768,725,684,646,610,575,543,513,484,457,431,407,384,363,342,323,305,288,272,256,242,228,216,204,192,181,171,161,152,144,136,128,121,114,108],
    [907,856,808,762,720,678,640,604,570,538,508,480,453,428,404,381,360,339,320,302,285,269,254,240,226,214,202,190,180,170,160,151,143,135,127,120],
    [900,850,802,757,715,675,636,601,567,535,505,477,450,425,401,379,357,337,318,300,284,268,253,238,225,212,200,189,179,169,159,150,142,134,126,119],
    [894,844,796,752,709,670,632,597,563,532,502,474,447,422,398,376,355,335,316,298,282,266,251,237,223,211,199,188,177,167,158,149,141,133,125,118],
    [887,838,791,746,704,665,628,592,559,528,498,470,444,419,395,373,352,332,314,296,280,264,249,235,222,209,198,187,176,166,157,148,140,132,125,118],
    [881,832,785,741,699,660,623,588,555,524,494,467,441,416,392,370,350,330,312,294,278,262,247,233,220,208,196,185,175,165,156,147,139,131,123,117],
    [875,826,779,736,694,655,619,584,551,520,491,463,437,413,390,368,347,328,309,292,276,260,245,232,219,206,195,184,174,164,155,146,138,130,123,116],
    [868,820,774,730,689,651,614,580,547,516,487,460,434,410,387,365,345,325,307,290,274,258,244,230,217,205,193,183,172,163,154,145,137,129,122,115],
    [862,814,768,725,684,646,610,575,543,513,484,457,431,407,384,363,342,323,305,288,272,256,242,228,216,203,192,181,171,161,152,144,136,128,121,114]
  ]

type
  ReplayChannel = object
    instrument: int
    hasInstrument: bool
    position: uint64
    period, targetPeriod: float64
    volume: float64
    pan: float64
    active: bool
    portaSpeed: int
    portaActive: bool
    fineTune: int
    glissando: bool
    vibratoSpeed, vibratoDepth, vibratoPhase: int
    vibratoWaveform: int
    vibratoRetrigger: bool
    vibratoRandomState: uint32
    tremoloSpeed, tremoloDepth, tremoloPhase: int
    tremoloActive: bool
    tremoloWaveform: int
    tremoloRetrigger: bool
    tremoloRandomState: uint32
    slideUp, slideDown, volumeSlide: int

  ProtrackerReplayResult* = object
    sound*: VextSound
    rowsRendered*: int
    stoppedAtCycle*: bool
    reachedSafetyLimit*: bool
    warnings*: seq[string]

proc clampInt(value, minimum, maximum: int): int =
  max(minimum, min(maximum, value))

proc fineTuneNibble(cents: float64): int =
  let steps = clampInt(int(round(cents / 12.5)), -8, 7)
  if steps < 0: steps + 16 else: steps

proc directNotePeriod(sourcePeriod, fineTune: int): float64 =
  var index = 0
  while index < 35 and sourcePeriod < ProtrackerFineTunePeriods[0][index]:
    inc index
  float64(ProtrackerFineTunePeriods[fineTune and 15][index])

proc tonePortamentoTarget(sourcePeriod, fineTune: int): float64 =
  let periods = ProtrackerFineTunePeriods[fineTune and 15]
  var index = 0
  while index < 35 and sourcePeriod < periods[index]:
    inc index
  # PT2.3F backs up one entry for negative finetunes after its table search.
  if (fineTune and 8) != 0 and index > 0: dec index
  float64(periods[index])

proc glissandoPeriod(period: float64, fineTune: int): float64 =
  let periods = ProtrackerFineTunePeriods[fineTune and 15]
  var index = 0
  while index < 35 and period < float64(periods[index]): inc index
  float64(periods[index])

proc tremoloValue(channel: var ReplayChannel): float64 =
  case channel.tremoloWaveform
  of 1: # Ramp down over one 64-step cycle.
    1.0 - float64(channel.tremoloPhase) / 31.5
  of 2:
    if channel.tremoloPhase < 32: 1.0 else: -1.0
  of 3:
    # The supplied specification describes random as a deterministic-time
    # choice among the three defined waveforms. Use a private reproducible PRNG
    # so repeated WAV exports are byte-identical.
    channel.tremoloRandomState = channel.tremoloRandomState * 1_664_525'u32 +
      1_013_904_223'u32
    case int(channel.tremoloRandomState mod 3)
    of 0: sin(float64(channel.tremoloPhase) * PI / 32.0)
    of 1: 1.0 - float64(channel.tremoloPhase) / 31.5
    else: (if channel.tremoloPhase < 32: 1.0 else: -1.0)
  else:
    sin(float64(channel.tremoloPhase) * PI / 32.0)

proc vibratoValue(channel: var ReplayChannel): float64 =
  case channel.vibratoWaveform
  of 1:
    1.0 - float64(channel.vibratoPhase) / 31.5
  of 2:
    if channel.vibratoPhase < 32: 1.0 else: -1.0
  of 3:
    channel.vibratoRandomState = channel.vibratoRandomState * 1_664_525'u32 +
      1_013_904_223'u32
    case int(channel.vibratoRandomState mod 3)
    of 0: sin(float64(channel.vibratoPhase) * PI / 32.0)
    of 1: 1.0 - float64(channel.vibratoPhase) / 31.5
    else: (if channel.vibratoPhase < 32: 1.0 else: -1.0)
  else:
    sin(float64(channel.vibratoPhase) * PI / 32.0)

proc sampleAt(samples: openArray[VextAudioSample], loopStart, loopLength: int,
    channel: var ReplayChannel): int32 =
  if not channel.active or samples.len == 0: return 0
  let loopEnd = loopStart + loopLength
  var index = int(channel.position shr 32)
  if loopLength > 0 and index >= loopEnd:
    let loopStartFixed = uint64(loopStart) shl 32
    let loopLengthFixed = uint64(loopLength) shl 32
    channel.position = loopStartFixed +
      (channel.position - loopStartFixed) mod loopLengthFixed
    index = int(channel.position shr 32)
  elif loopLength == 0 and index >= samples.len:
    channel.active = false
    return 0
  # Paula outputs the current 8-bit sample until the DMA period advances;
  # nearest/sample-and-hold playback is both faithful and deterministic.
  samples[clampInt(index, 0, samples.high)]

proc renderProtracker*(module: VextTrackerModule,
    sampleRate = ProtrackerReplaySampleRate,
    maximumSeconds = MaximumProtrackerReplaySeconds): ProtrackerReplayResult =
  module.validate
  if sampleRate <= 0 or maximumSeconds <= 0:
    raise newException(ValueError, "invalid ProTracker replay bounds")
  var channels = newSeq[ReplayChannel](module.channels.len)
  for index in 0 ..< channels.len:
    channels[index].pan = module.channels[index].defaultPan
    channels[index].vibratoRetrigger = true
    channels[index].vibratoRandomState = uint32(index + 0x101)
    channels[index].tremoloRetrigger = true
    channels[index].tremoloRandomState = uint32(index + 1)
  var speed = module.initialSpeed
  var tempo = module.initialTempoBpm
  var filterEnabled = true
  var filteredLeft, filteredRight = 0'i64
  let filterCoefficient = int64(round((1.0 - exp(
    -2.0 * PI * ProtrackerReplayFilterCutoffHz / float64(sampleRate))) *
    65_536.0))
  var order = 0
  var row = 0
  var visited = initHashSet[string]()
  var loopStarts = newSeq[int](module.channels.len)
  var loopCounts = newSeq[int](module.channels.len)
  let maximumFrames = sampleRate * maximumSeconds
  var left = newSeqOfCap[VextAudioSample](
    sampleRate * min(maximumSeconds, 180))
  var right = newSeqOfCap[VextAudioSample](
    sampleRate * min(maximumSeconds, 180))

  while order >= 0 and order < module.orders.len and left.len < maximumFrames:
    let stateKey = $order & ":" & $row & ":" & $loopStarts & ":" & $loopCounts
    if stateKey in visited:
      result.stoppedAtCycle = true
      break
    visited.incl stateKey
    let pattern = module.patterns[module.orders[order]]
    if row < 0 or row >= pattern.rows.len: break
    let trackerRow = pattern.rows[row]
    var nextOrder = order
    var nextRow = row + 1
    var flowChanged = false
    var patternLoopRow = -1
    var patternDelay = 0
    var noteDelays = newSeq[int](channels.len)
    var delayedPeriods = newSeq[int](channels.len)
    for index in 0 ..< noteDelays.len: noteDelays[index] = -1

    for channelIndex, cell in trackerRow.cells:
      var state = addr channels[channelIndex]
      state[].slideUp = 0
      state[].slideDown = 0
      state[].volumeSlide = 0
      state[].portaActive = false
      state[].tremoloActive = false
      if cell.hasInstrument:
        state[].instrument = cell.instrument
        state[].hasInstrument = true
        state[].volume = module.instruments[cell.instrument].sample.volume * 64.0
        state[].fineTune = fineTuneNibble(
          module.instruments[cell.instrument].fineTuneCents)
      for item in cell.effects:
        if item.rawCommand == 14 and item.rawParameter shr 4 == 13:
          noteDelays[channelIndex] = item.rawParameter and 15
          delayedPeriods[channelIndex] = cell.sourcePitch
      # E5x precedes period selection in PT2.3F, including when a note shares
      # the row. It changes replay state, never the extracted instrument.
      for item in cell.effects:
        if item.rawCommand == 14 and item.rawParameter shr 4 == 5:
          state[].fineTune = item.rawParameter and 15
      if cell.noteKind == vtnkTrigger and cell.hasSourcePitch and
          state[].hasInstrument and noteDelays[channelIndex] < 0:
        state[].period = directNotePeriod(cell.sourcePitch, state[].fineTune)
        state[].targetPeriod = state[].period
        state[].position = 0'u64
        state[].active = true
        if state[].vibratoRetrigger:
          state[].vibratoPhase = 0
          state[].vibratoRandomState = uint32(channelIndex + 0x101)
        if state[].tremoloRetrigger:
          state[].tremoloPhase = 0
          state[].tremoloRandomState = uint32(channelIndex + 1)
      elif cell.noteKind == vtnkTarget and cell.hasSourcePitch:
        state[].targetPeriod = tonePortamentoTarget(
          cell.sourcePitch, state[].fineTune)
      for item in cell.effects:
        let x = item.rawParameter shr 4
        let y = item.rawParameter and 15
        case item.rawCommand
        of 1: state[].slideUp = item.rawParameter
        of 2: state[].slideDown = item.rawParameter
        of 3:
          if item.rawParameter != 0: state[].portaSpeed = item.rawParameter
          state[].portaActive = true
        of 4:
          if x != 0: state[].vibratoSpeed = x
          if y != 0: state[].vibratoDepth = y
        of 5:
          state[].portaActive = true
          state[].volumeSlide = x - y
        of 6:
          state[].volumeSlide = x - y
        of 7:
          if x != 0: state[].tremoloSpeed = x
          if y != 0: state[].tremoloDepth = y
          state[].tremoloActive = true
        of 8: state[].pan = float64(item.rawParameter) / 127.5 - 1.0
        of 9:
          if state[].active:
            state[].position = uint64(item.rawParameter * 256) shl 32
        of 10: state[].volumeSlide = x - y
        of 11:
          nextOrder = item.rawParameter
          nextRow = 0
          flowChanged = true
        of 12: state[].volume = float64(min(64, item.rawParameter))
        of 13:
          if not flowChanged: nextOrder = order + 1
          nextRow = min(63, x * 10 + y)
          flowChanged = true
        of 14:
          case x
          of 0: filterEnabled = y == 0
          of 1: state[].period = max(1.0, state[].period - float64(y))
          of 2: state[].period += float64(y)
          of 4:
            state[].vibratoWaveform = y and 3
            state[].vibratoRetrigger = (y and 4) == 0
          of 3: state[].glissando = y != 0
          of 10: state[].volume = min(64.0, state[].volume + float64(y))
          of 11: state[].volume = max(0.0, state[].volume - float64(y))
          of 6:
            if y == 0:
              loopStarts[channelIndex] = row
            elif loopCounts[channelIndex] == 0:
              loopCounts[channelIndex] = y
              patternLoopRow = loopStarts[channelIndex]
            else:
              dec loopCounts[channelIndex]
              if loopCounts[channelIndex] > 0:
                patternLoopRow = loopStarts[channelIndex]
          of 7:
            state[].tremoloWaveform = y and 3
            state[].tremoloRetrigger = (y and 4) == 0
          of 14: patternDelay = y
          else: discard
        of 15:
          if item.rawParameter in 1 .. 32: speed = item.rawParameter
          elif item.rawParameter > 32: tempo = float64(item.rawParameter)
        else: discard

    for tick in 0 ..< speed * (patternDelay + 1):
      for channelIndex, cell in trackerRow.cells:
        var state = addr channels[channelIndex]
        if noteDelays[channelIndex] == tick and state[].hasInstrument and
            delayedPeriods[channelIndex] > 0:
          state[].period = directNotePeriod(
            delayedPeriods[channelIndex], state[].fineTune)
          state[].targetPeriod = state[].period
          state[].position = 0'u64
          state[].active = true
          if state[].vibratoRetrigger:
            state[].vibratoPhase = 0
            state[].vibratoRandomState = uint32(channelIndex + 0x101)
          if state[].tremoloRetrigger:
            state[].tremoloPhase = 0
            state[].tremoloRandomState = uint32(channelIndex + 1)
        for item in cell.effects:
          if item.rawCommand == 14:
            let subcommand = item.rawParameter shr 4
            let value = item.rawParameter and 15
            if subcommand == 9 and value > 0 and tick > 0 and
                tick mod value == 0 and state[].hasInstrument:
              state[].position = 0'u64
              state[].active = true
            elif subcommand == 12 and tick == value:
              state[].active = false
      if tick > 0:
        for state in channels.mitems:
          if state.slideUp > 0: state.period = max(1.0, state.period - float64(state.slideUp))
          if state.slideDown > 0: state.period += float64(state.slideDown)
          if state.portaActive and state.portaSpeed > 0 and state.targetPeriod > 0:
            if state.period < state.targetPeriod:
              state.period = min(state.targetPeriod, state.period + float64(state.portaSpeed))
            elif state.period > state.targetPeriod:
              state.period = max(state.targetPeriod, state.period - float64(state.portaSpeed))
          state.volume = max(0.0, min(64.0,
            state.volume + float64(state.volumeSlide)))
      let tickFrames = max(1, int(round(float64(sampleRate) * 2.5 / tempo)))
      var steps = newSeq[uint64](channels.len)
      var leftGains = newSeq[int](channels.len)
      var rightGains = newSeq[int](channels.len)
      for channelIndex, state in channels.mpairs:
        if not state.active or not state.hasInstrument or state.period <= 0:
          continue
        let cell = trackerRow.cells[channelIndex]
        var playbackPeriod = state.period
        if state.glissando and state.portaActive:
          playbackPeriod = glissandoPeriod(playbackPeriod, state.fineTune)
        if cell.effects.len > 0 and cell.effects[0].rawCommand == 0 and
            cell.effects[0].rawParameter != 0:
          let semitone = case tick mod 3
            of 1: cell.effects[0].rawParameter shr 4
            of 2: cell.effects[0].rawParameter and 15
            else: 0
          playbackPeriod /= pow(2.0, float64(semitone) / 12.0)
        for item in cell.effects:
          if item.rawCommand in [4, 6] and state.vibratoDepth > 0:
            playbackPeriod += state.vibratoValue *
              float64(state.vibratoDepth * 2)
        let step = PaulaClock /
          (2.0 * playbackPeriod * float64(sampleRate))
        steps[channelIndex] = uint64(max(0.0, step) * FixedPointScale)
        # Reserve deterministic four-channel headroom: two hard-panned
        # full-volume channels, or four centred channels, fit without clipping.
        var tickVolume = state.volume
        if state.tremoloActive and tick > 0 and state.tremoloDepth > 0:
          tickVolume = max(0.0, min(64.0, tickVolume +
            state.tremoloValue *
            float64(state.tremoloDepth * 4)))
        leftGains[channelIndex] = int(round(tickVolume *
          (1.0 - state.pan)))
        rightGains[channelIndex] = int(round(tickVolume *
          (1.0 + state.pan)))
      for frame in 0 ..< tickFrames:
        if left.len >= maximumFrames: break
        var mixedLeft, mixedRight = 0'i64
        for channelIndex, state in channels.mpairs:
          if not state.active or not state.hasInstrument or state.period <= 0: continue
          let instrumentIndex = state.instrument
          let value = int64(sampleAt(
            module.instruments[instrumentIndex].sample.sound.buffer.channels[0],
            module.instruments[instrumentIndex].sample.oneShotSamples,
            module.instruments[instrumentIndex].sample.repeatSamples, state))
          mixedLeft += value * int64(leftGains[channelIndex])
          mixedRight += value * int64(rightGains[channelIndex])
          state.position += steps[channelIndex]
        filteredLeft += ((mixedLeft - filteredLeft) * filterCoefficient) shr 16
        filteredRight += ((mixedRight - filteredRight) * filterCoefficient) shr 16
        let outputLeft = if filterEnabled: filteredLeft else: mixedLeft
        let outputRight = if filterEnabled: filteredRight else: mixedRight
        left.add VextAudioSample(clampInt(int(outputLeft), -32768, 32767))
        right.add VextAudioSample(clampInt(int(outputRight), -32768, 32767))
      for state in channels.mitems:
        state.vibratoPhase = (state.vibratoPhase + state.vibratoSpeed) and 63
        if state.tremoloActive:
          state.tremoloPhase =
            (state.tremoloPhase + state.tremoloSpeed) and 63

    inc result.rowsRendered
    if patternLoopRow >= 0 and not flowChanged:
      nextRow = patternLoopRow
    if nextRow >= pattern.rows.len:
      inc nextOrder
      nextRow = 0
    if nextOrder != order:
      loopStarts = newSeq[int](module.channels.len)
      loopCounts = newSeq[int](module.channels.len)
    order = nextOrder
    row = nextRow
    if order >= module.orders.len and module.hasRestartOrder:
      order = module.restartOrder
  if left.len >= maximumFrames:
    result.reachedSafetyLimit = true
    result.warnings.add "ProTracker rendering stopped at the five-minute safety limit"
  result.sound = VextSound(sampleRate: sampleRate,
    buffer: VextAudioBuffer(bitsPerSample: 16, channels: @[left, right]))
