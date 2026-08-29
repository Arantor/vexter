## Bounded ProTracker replay into generic stereo PCM.

import std/[math, sets]
import ../archetypes/[audio, tracker]

const
  ProtrackerReplaySampleRate* = 44_100
  MaximumProtrackerReplaySeconds* = 300
  PaulaClock = 7_093_789.2
  FixedPointScale = 4_294_967_296.0
  ProtrackerReplayFilterCutoffHz* = 4_500.0

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
    vibratoSpeed, vibratoDepth, vibratoPhase: int
    slideUp, slideDown, volumeSlide: int

  ProtrackerReplayResult* = object
    sound*: VextSound
    rowsRendered*: int
    stoppedAtCycle*: bool
    reachedSafetyLimit*: bool
    warnings*: seq[string]

proc clampInt(value, minimum, maximum: int): int =
  max(minimum, min(maximum, value))

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
      if cell.hasInstrument:
        state[].instrument = cell.instrument
        state[].hasInstrument = true
        state[].volume = module.instruments[cell.instrument].sample.volume * 64.0
      for item in cell.effects:
        if item.rawCommand == 14 and item.rawParameter shr 4 == 13:
          noteDelays[channelIndex] = item.rawParameter and 15
          delayedPeriods[channelIndex] = cell.sourcePitch
      if cell.noteKind == vtnkTrigger and cell.hasSourcePitch and
          state[].hasInstrument and noteDelays[channelIndex] < 0:
        state[].period = float64(cell.sourcePitch)
        state[].targetPeriod = state[].period
        state[].position = 0'u64
        state[].active = true
      elif cell.noteKind == vtnkTarget and cell.hasSourcePitch:
        state[].targetPeriod = float64(cell.sourcePitch)
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
          state[].period = float64(delayedPeriods[channelIndex])
          state[].targetPeriod = state[].period
          state[].position = 0'u64
          state[].active = true
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
      for channelIndex, state in channels:
        if not state.active or not state.hasInstrument or state.period <= 0:
          continue
        let cell = trackerRow.cells[channelIndex]
        var playbackPeriod = state.period
        if cell.effects.len > 0 and cell.effects[0].rawCommand == 0 and
            cell.effects[0].rawParameter != 0:
          let semitone = case tick mod 3
            of 1: cell.effects[0].rawParameter shr 4
            of 2: cell.effects[0].rawParameter and 15
            else: 0
          playbackPeriod /= pow(2.0, float64(semitone) / 12.0)
        for item in cell.effects:
          if item.rawCommand in [4, 6] and state.vibratoDepth > 0:
            playbackPeriod += sin(float64(state.vibratoPhase) * PI / 32.0) *
              float64(state.vibratoDepth * 2)
        let fineTune = module.instruments[state.instrument].fineTuneCents
        let step = PaulaClock /
          (2.0 * playbackPeriod * float64(sampleRate)) *
          pow(2.0, fineTune / 1200.0)
        steps[channelIndex] = uint64(max(0.0, step) * FixedPointScale)
        # Reserve deterministic four-channel headroom: two hard-panned
        # full-volume channels, or four centred channels, fit without clipping.
        leftGains[channelIndex] = int(round(state.volume *
          (1.0 - state.pan)))
        rightGains[channelIndex] = int(round(state.volume *
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
