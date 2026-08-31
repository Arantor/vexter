## Bounded replay and tracker projection for AMOS Music banks.

import std/[math, sets]
import ../archetypes/[audio, tracker]
import ../containers/amos_music_bank

const
  AmosMusicReplaySampleRate* = 44_100
  MaximumAmosMusicReplaySeconds* = 300
  AmosMusicFilterCutoffHz* = 4_500.0
  PaulaClock = 7_093_789.2

type
  AmosMusicReplayResult* = object
    sound*: VextSound
    verticalBlanksRendered*: int
    stoppedAtCycle*, reachedSafetyLimit*: bool
    warnings*: seq[string]

  ReplayChannel = object
    playlistPosition, streamOffset, delay, instrument: int
    hasInstrument, active: bool
    period, targetPeriod, volume, samplePosition: float64
    effectCommand, effectParameter, effectPhase: int
    repeatMark, repeatCount: int

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) shl 8 or int(data[offset + 1])

proc noteForPeriod(period: int): int =
  if period <= 0: return 0
  max(0, min(127, int(round(60.0 + 12.0 * log2(428.0 / float64(period))))))

proc semanticEffect(command, parameter: int): VextTrackerEffect =
  let kind = case command
    of 0x83: vtekSetVolume
    of 0x85: vtekPatternLoop
    of 0x86, 0x87: vtekSetFilter
    of 0x88: vtekSetTempo
    of 0x8a: vtekArpeggio
    of 0x8b: vtekPortamento
    of 0x8c: vtekVibrato
    of 0x8d: vtekVolumeSlide
    of 0x8e: vtekPitchSlideUp
    of 0x8f: vtekPitchSlideDown
    of 0x91: vtekPositionJump
    else: vtekUnknown
  VextTrackerEffect(kind: kind, parameter: parameter,
    rawCommand: command, rawParameter: parameter)

proc decodeStream(bank: AmosMusicBank, offset: int,
    currentInstrument: var int): seq[VextTrackerCell] =
  var cursor = offset
  var pending: seq[VextTrackerEffect]
  while cursor <= bank.data.len - 2:
    let value = bank.data.beWord(cursor)
    cursor += 2
    # Shipped AMOS Music banks use $7Fxx as a compact delay word. It appears
    # before the note whose following delay it controls.
    if value shr 8 == 0x7f:
      pending.add semanticEffect(0x7f, value and 0xff)
      continue
    if (value and 0x8000) == 0:
      var cell = VextTrackerCell(noteKind: vtnkTrigger,
        note: noteForPeriod(value and 0x0fff), hasSourcePitch: true,
        sourcePitch: value and 0x0fff, effects: pending)
      pending = @[]
      if currentInstrument >= 0:
        cell.hasInstrument = true
        cell.instrument = currentInstrument
      result.add cell
      continue
    let command = value shr 8
    let parameter = value and 0xff
    if command == 0x80:
      if pending.len > 0:
        result.add VextTrackerCell(effects: pending)
      return
    if command == 0x89:
      currentInstrument = parameter
    else:
      pending.add semanticEffect(command, parameter)

proc toTrackerModule*(bank: AmosMusicBank, songIndex: int): VextTrackerModule =
  if songIndex < 0 or songIndex >= bank.songs.len:
    raise newException(ValueError, "AMOS music song index is outside bank")
  let song = bank.songs[songIndex]
  result.title = song.name
  result.initialSpeed = max(1, int(round(100.0 / 17.0)))
  result.initialTempoBpm = 125.0
  result.rowsPerBeat = 4
  for channel in 0 ..< AmosMusicChannelCount:
    let left = channel in [0, 3]
    result.channels.add VextTrackerChannel(name: "Channel " & $(channel + 1),
      sourceIndex: channel, bias: if left: vtcbLeft else: vtcbRight,
      defaultPan: if left: -1.0 else: 1.0)
  for index, source in bank.instruments:
    result.instruments.add VextTrackerInstrument(name: source.name,
      sourceIndex: index, sample: source.sample, referenceNote: 36,
      fineTuneCents: 0)
  var currentInstruments = [-1, -1, -1, -1]
  var positions = 0
  for playlist in song.playlists: positions = max(positions, playlist.len)
  for position in 0 ..< positions:
    var channelCells: array[AmosMusicChannelCount, seq[VextTrackerCell]]
    var rowCount = 1
    for channel in 0 ..< AmosMusicChannelCount:
      if position < song.playlists[channel].len:
        let patternIndex = song.playlists[channel][position]
        channelCells[channel] = bank.decodeStream(
          bank.patterns[patternIndex].streamOffsets[channel],
          currentInstruments[channel])
        rowCount = max(rowCount, channelCells[channel].len)
    var pattern = VextTrackerPattern(name: "Position " & $position,
      sourceIndex: position)
    for rowIndex in 0 ..< rowCount:
      var row: VextTrackerRow
      for channel in 0 ..< AmosMusicChannelCount:
        row.cells.add if rowIndex < channelCells[channel].len:
            channelCells[channel][rowIndex]
          else: VextTrackerCell()
      pattern.rows.add row
    result.patterns.add pattern
    result.orders.add position
  result.loopAnalysis.status = vtlsNotAnalysed
  result.validate

proc loadPattern(bank: AmosMusicBank, song: AmosMusicSong, channel: int,
    state: var ReplayChannel): bool =
  if state.playlistPosition < 0 or
      state.playlistPosition >= song.playlists[channel].len:
    state.streamOffset = -1
    return false
  let patternIndex = song.playlists[channel][state.playlistPosition]
  state.streamOffset = bank.patterns[patternIndex].streamOffsets[channel]
  state.repeatMark = state.streamOffset
  state.repeatCount = 0
  true

proc advancePattern(bank: AmosMusicBank, song: AmosMusicSong, channel: int,
    state: var ReplayChannel) =
  inc state.playlistPosition
  state.effectCommand = 0
  discard bank.loadPattern(song, channel, state)

proc processPosition(bank: AmosMusicBank, song: AmosMusicSong, channel: int,
    state: var ReplayChannel, tempo: var int, filterEnabled: var bool) =
  if state.delay > 0:
    dec state.delay
    if state.delay > 0:
      return
  var commands = 0
  while state.streamOffset >= 0 and state.streamOffset <= bank.data.len - 2:
    if commands >= 65_536:
      raise newException(ValueError, "AMOS music command stream does not advance")
    inc commands
    let value = bank.data.beWord(state.streamOffset)
    state.streamOffset += 2
    if value shr 8 == 0x7f:
      state.delay = value and 0xff
      continue
    if (value and 0x8000) == 0:
      let period = float64(value and 0x0fff)
      if state.effectCommand == 0x8b and state.active:
        state.targetPeriod = period
      elif state.hasInstrument:
        state.period = period
        state.targetPeriod = period
        state.volume = float64(bank.instruments[state.instrument].volume)
        state.samplePosition = 0
        state.active = true
      return
    let command = value shr 8
    let parameter = value and 0xff
    case command
    of 0x80:
      bank.advancePattern(song, channel, state)
      continue
    of 0x83: state.volume = float64(min(63, parameter))
    of 0x84: state.effectCommand = 0
    of 0x85:
      if parameter == 0:
        state.repeatMark = state.streamOffset
        state.repeatCount = 0
      elif state.repeatCount < parameter:
        inc state.repeatCount
        state.streamOffset = state.repeatMark
      else:
        state.repeatCount = 0
    of 0x86: filterEnabled = true
    of 0x87: filterEnabled = false
    of 0x88:
      if parameter in 1 .. 100: tempo = parameter
    of 0x89:
      if parameter < bank.instruments.len:
        state.instrument = parameter
        state.hasInstrument = true
    of 0x8a .. 0x8f:
      state.effectCommand = command
      state.effectParameter = parameter
      state.effectPhase = 0
    of 0x90: state.delay = parameter
    of 0x91:
      state.playlistPosition = parameter
      state.effectCommand = 0
      discard bank.loadPattern(song, channel, state)
      continue
    else: discard

proc applyEffect(state: var ReplayChannel): float64 =
  result = state.period
  let parameter = state.effectParameter
  case state.effectCommand
  of 0x8a:
    let semitone = case state.effectPhase mod 3
      of 1: parameter shr 4
      of 2: parameter and 15
      else: 0
    result = state.period / pow(2.0, float64(semitone) / 12.0)
  of 0x8b:
    if state.targetPeriod > 0:
      if state.period < state.targetPeriod:
        state.period = min(state.targetPeriod,
          state.period + float64(parameter))
      elif state.period > state.targetPeriod:
        state.period = max(state.targetPeriod,
          state.period - float64(parameter))
      result = state.period
  of 0x8c:
    let speed = parameter shr 4
    let depth = parameter and 15
    result = state.period + sin(float64(state.effectPhase and 63) *
      2.0 * PI / 64.0) * float64(depth * 2)
    state.effectPhase = (state.effectPhase + speed) and 63
    return
  of 0x8d:
    if parameter shr 4 > 0:
      state.volume = min(64.0, state.volume + float64(parameter shr 4))
    else:
      state.volume = max(0.0, state.volume - float64(parameter and 15))
  of 0x8e:
    state.period = max(113.0, state.period - float64(parameter))
    result = state.period
  of 0x8f:
    state.period = min(856.0, state.period + float64(parameter))
    result = state.period
  else: discard
  state.effectPhase = (state.effectPhase + 1) and 63

proc sampleAt(samples: openArray[VextAudioSample], oneShotSamples,
    repeatSamples: int, state: var ReplayChannel): int32 =
  if not state.active: return 0
  var index = int(state.samplePosition)
  if repeatSamples > 0 and index >= oneShotSamples:
    index = oneShotSamples + (index - oneShotSamples) mod repeatSamples
    state.samplePosition = float64(index)
  elif index >= samples.len:
    state.active = false
    return 0
  samples[index]

proc controlKey(channels: array[AmosMusicChannelCount, ReplayChannel],
    tempo, tempoCounter: int, filterEnabled: bool): string =
  result = $tempo & ":" & $tempoCounter & ":" & $filterEnabled
  for state in channels:
    result.add ":" & $state.playlistPosition & ":" & $state.streamOffset &
      ":" & $state.delay & ":" & $state.instrument & ":" &
      $state.hasInstrument & ":" & $state.effectCommand & ":" &
      $state.effectParameter & ":" & $state.effectPhase & ":" &
      $state.repeatMark & ":" & $state.repeatCount

proc renderAmosMusic*(bank: AmosMusicBank, songIndex: int,
    sampleRate = AmosMusicReplaySampleRate,
    maximumSeconds = MaximumAmosMusicReplaySeconds): AmosMusicReplayResult =
  if songIndex < 0 or songIndex >= bank.songs.len or
      sampleRate <= 0 or maximumSeconds <= 0:
    raise newException(ValueError, "invalid AMOS music replay request")
  let song = bank.songs[songIndex]
  var channels: array[AmosMusicChannelCount, ReplayChannel]
  for channel in 0 ..< AmosMusicChannelCount:
    discard bank.loadPattern(song, channel, channels[channel])
  var tempo = 17
  var tempoCounter = 100
  var filterEnabled = true
  var filteredLeft, filteredRight = 0'i64
  let filterCoefficient = int64(round((1.0 - exp(
    -2.0 * PI * AmosMusicFilterCutoffHz / float64(sampleRate))) * 65_536.0))
  let maximumFrames = sampleRate * maximumSeconds
  var left = newSeqOfCap[VextAudioSample](min(maximumFrames, sampleRate * 180))
  var right = newSeqOfCap[VextAudioSample](min(maximumFrames, sampleRate * 180))
  var visited = initHashSet[string]()
  var frameRemainder = 0
  while left.len < maximumFrames:
    var hasControl = false
    for state in channels: hasControl = hasControl or state.streamOffset >= 0
    if hasControl:
      let key = channels.controlKey(tempo, tempoCounter, filterEnabled)
      if key in visited:
        result.stoppedAtCycle = true
        break
      visited.incl key
    if tempoCounter >= 100:
      tempoCounter -= 100
      for channel in 0 ..< AmosMusicChannelCount:
        bank.processPosition(song, channel, channels[channel], tempo,
          filterEnabled)
    var periods: array[AmosMusicChannelCount, float64]
    var anyActive = false
    for channel in 0 ..< AmosMusicChannelCount:
      periods[channel] = channels[channel].applyEffect
      anyActive = anyActive or channels[channel].active or
        channels[channel].streamOffset >= 0
    if not anyActive: break
    frameRemainder += sampleRate
    let frames = frameRemainder div 50
    frameRemainder = frameRemainder mod 50
    var steps: array[AmosMusicChannelCount, float64]
    for channel in 0 ..< AmosMusicChannelCount:
      if periods[channel] > 0:
        steps[channel] = PaulaClock /
          (2.0 * periods[channel] * float64(sampleRate))
    for frame in 0 ..< frames:
      if left.len >= maximumFrames: break
      var mixedLeft, mixedRight = 0'i64
      for channel in 0 ..< AmosMusicChannelCount:
        var value = 0'i64
        if channels[channel].active and channels[channel].hasInstrument:
          let instrumentIndex = channels[channel].instrument
          value = int64(sampleAt(
            bank.instruments[instrumentIndex].sample.sound.buffer.channels[0],
            bank.instruments[instrumentIndex].sample.oneShotSamples,
            bank.instruments[instrumentIndex].sample.repeatSamples,
            channels[channel]))
        let gain = int64(round(channels[channel].volume))
        if channel in [0, 3]: mixedLeft += value * gain * 2
        else: mixedRight += value * gain * 2
        channels[channel].samplePosition += steps[channel]
      filteredLeft += ((mixedLeft - filteredLeft) * filterCoefficient) shr 16
      filteredRight += ((mixedRight - filteredRight) * filterCoefficient) shr 16
      left.add VextAudioSample(max(-32768'i64, min(32767'i64,
        if filterEnabled: filteredLeft else: mixedLeft)))
      right.add VextAudioSample(max(-32768'i64, min(32767'i64,
        if filterEnabled: filteredRight else: mixedRight)))
    tempoCounter += tempo
    inc result.verticalBlanksRendered
  if left.len >= maximumFrames:
    result.reachedSafetyLimit = true
    result.warnings.add "AMOS music rendering stopped at the five-minute safety limit"
  result.sound = VextSound(sampleRate: sampleRate,
    buffer: VextAudioBuffer(bitsPerSample: 16, channels: @[left, right]))
