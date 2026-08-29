## Noisetracker/Soundtracker/Protracker MOD parsing into tracker archetypes.

import std/[strutils, tables]
import ../archetypes/[audio, tracker]

const
  ProtrackerModTypeId* = "protracker.mod"
  ProtrackerModResourcePath* = "/module"
  ProtrackerPatternRows* = 64
  ProtrackerInitialSpeed* = 6
  ProtrackerInitialTempo* = 125.0
  ProtrackerReferenceSampleRate* = 8287
  MaximumProtrackerControlTransitions* = 1_000_000

type
  ProtrackerSampleHeader = object
    name: string
    lengthBytes: int
    fineTune: int
    volume: int
    repeatStart: int
    repeatLength: int

  ProtrackerMod* = object
    signature*: string
    sampleCount*: int
    module*: VextTrackerModule

proc beWord(data: openArray[byte], offset: int): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated MOD word")
  int(data[offset]) shl 8 or int(data[offset + 1])

proc fixedText(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or length > data.len - offset:
    raise newException(ValueError, "truncated MOD text")
  for index in 0 ..< length:
    let value = data[offset + index]
    if value == 0: break
    result.add if value in 32'u8 .. 126'u8: char(value) else: '?'
  result = result.strip

proc signatureInfo(signature: string): tuple[known: bool, channels: int] =
  case signature
  of "M.K.", "M!K!", "FLT4", "4CHN": (true, 4)
  of "6CHN": (true, 6)
  of "FLT8", "8CHN": (true, 8)
  else: (false, 0)

const Periods = [
  1712, 1616, 1525, 1440, 1357, 1281, 1209, 1141, 1077, 1017, 961, 907,
  856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
  428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
  107, 101, 95, 90, 85, 80, 76, 71, 67, 64, 60, 57]

proc noteForPeriod(period: int): int =
  var best = 0
  var distance = high(int)
  for index, candidate in Periods:
    let candidateDistance = abs(candidate - period)
    if candidateDistance < distance:
      distance = candidateDistance
      best = index
  12 + best # Documented octave 0 maps to MIDI C0.

proc effect(kind: VextTrackerEffectKind, command, rawParameter: int,
    parameter = -1): VextTrackerEffect =
  VextTrackerEffect(kind: kind,
    parameter: if parameter >= 0: parameter else: rawParameter,
    rawCommand: command, rawParameter: rawParameter)

proc decodeEffects(command, parameter: int): seq[VextTrackerEffect] =
  case command
  of 0:
    if parameter != 0: result.add effect(vtekArpeggio, command, parameter)
  of 1: result.add effect(vtekPitchSlideUp, command, parameter)
  of 2: result.add effect(vtekPitchSlideDown, command, parameter)
  of 3: result.add effect(vtekPortamento, command, parameter)
  of 4: result.add effect(vtekVibrato, command, parameter)
  of 5:
    result.add effect(vtekPortamento, command, parameter, 0)
    result.add effect(vtekVolumeSlide, command, parameter)
  of 6:
    result.add effect(vtekVibrato, command, parameter, 0)
    result.add effect(vtekVolumeSlide, command, parameter)
  of 7: result.add effect(vtekTremolo, command, parameter)
  of 8: result.add effect(vtekSetPan, command, parameter)
  of 9: result.add effect(vtekSampleOffset, command, parameter)
  of 10: result.add effect(vtekVolumeSlide, command, parameter)
  of 11: result.add effect(vtekPositionJump, command, parameter)
  of 12: result.add effect(vtekSetVolume, command, parameter)
  of 13:
    result.add effect(vtekPatternBreak, command, parameter,
      (parameter shr 4) * 10 + (parameter and 15))
  of 14:
    let subcommand = parameter shr 4
    let value = parameter and 15
    let kind = case subcommand
      of 0: vtekSetFilter
      of 1: vtekFinePitchSlideUp
      of 2: vtekFinePitchSlideDown
      of 3: vtekSetGlissando
      of 4: vtekSetVibratoWaveform
      of 5: vtekSetFineTune
      of 6: vtekPatternLoop
      of 7: vtekSetTremoloWaveform
      of 9: vtekRetrigger
      of 10: vtekFineVolumeSlideUp
      of 11: vtekFineVolumeSlideDown
      of 12: vtekNoteCut
      of 13: vtekNoteDelay
      of 14: vtekPatternDelay
      of 15: vtekInvertLoop
      else: vtekUnknown
    result.add effect(kind, command, parameter, value)
  of 15:
    result.add effect(if parameter <= 32: vtekSetSpeed else: vtekSetTempo,
      command, parameter, if parameter == 0: 1 else: parameter)
  else: result.add effect(vtekUnknown, command, parameter)

proc channelBias(index: int): VextTrackerChannelBias =
  if index mod 4 in [0, 3]: vtcbLeft else: vtcbRight

proc analyseControlFlow(module: VextTrackerModule): VextTrackerLoopAnalysis =
  type PlaybackState = object
    order, row: int
    loopStarts, loopCounts: seq[int]
  var state = PlaybackState(order: 0, row: 0,
    loopStarts: newSeq[int](module.channels.len),
    loopCounts: newSeq[int](module.channels.len))
  var visited = initTable[string, tuple[transition, order, row: int]]()
  for transition in 0 ..< MaximumProtrackerControlTransitions:
    if state.order < 0 or state.order >= module.orders.len:
      result.status = vtlsTerminates
      result.transitionsExamined = transition
      return
    let pattern = module.patterns[module.orders[state.order]]
    if state.row < 0 or state.row >= pattern.rows.len:
      result.status = vtlsAnalysisLimit
      result.transitionsExamined = transition
      return
    let key = $state.order & ":" & $state.row & ":" &
      $state.loopStarts & ":" & $state.loopCounts
    if key in visited:
      let first = visited[key]
      result = VextTrackerLoopAnalysis(status: vtlsCycles,
        transitionsExamined: transition, loopEntryOrder: first.order,
        loopEntryRow: first.row,
        loopLengthTransitions: transition - first.transition)
      return
    visited[key] = (transition, state.order, state.row)

    var positionJump = -1
    var patternBreak = -1
    var loopJump = -1
    for channel, cell in pattern.rows[state.row].cells:
      for item in cell.effects:
        if item.rawCommand == 11:
          positionJump = item.rawParameter
        elif item.rawCommand == 13:
          patternBreak = (item.rawParameter shr 4) * 10 +
            (item.rawParameter and 15)
        elif item.rawCommand == 14 and item.rawParameter shr 4 == 6:
          let count = item.rawParameter and 15
          if count == 0:
            state.loopStarts[channel] = state.row
          elif state.loopCounts[channel] == 0:
            state.loopCounts[channel] = count
            loopJump = state.loopStarts[channel]
          else:
            dec state.loopCounts[channel]
            if state.loopCounts[channel] > 0:
              loopJump = state.loopStarts[channel]
    if positionJump >= 0 or patternBreak >= 0:
      state.order = if positionJump >= 0: positionJump else: state.order + 1
      state.row = if patternBreak >= 0: patternBreak else: 0
      state.loopStarts = newSeq[int](module.channels.len)
      state.loopCounts = newSeq[int](module.channels.len)
    elif loopJump >= 0:
      state.row = loopJump
    else:
      inc state.row
      if state.row >= pattern.rows.len:
        inc state.order
        state.row = 0
        state.loopStarts = newSeq[int](module.channels.len)
        state.loopCounts = newSeq[int](module.channels.len)
        if state.order >= module.orders.len and module.hasRestartOrder:
          state.order = module.restartOrder
  result.status = vtlsAnalysisLimit
  result.transitionsExamined = MaximumProtrackerControlTransitions

proc parseVariant(data: openArray[byte], sampleCount, channels: int,
    signature: string): ProtrackerMod =
  let songOffset = 20 + sampleCount * 30
  let patternTableOffset = songOffset + 2
  let patternDataOffset = patternTableOffset + 128 +
    (if sampleCount == 31: 4 else: 0)
  if data.len < patternDataOffset:
    raise newException(ValueError, "truncated MOD header")
  let songLength = int(data[songOffset])
  let restart = int(data[songOffset + 1])
  if songLength < 1 or songLength > 128:
    raise newException(ValueError, "invalid MOD song length")

  var headers: seq[ProtrackerSampleHeader]
  var totalSampleBytes = 0
  for index in 0 ..< sampleCount:
    let offset = 20 + index * 30
    let lengthBytes = beWord(data, offset + 22) * 2
    let fineNibble = int(data[offset + 24] and 15)
    let volume = int(data[offset + 25])
    let repeatStart = beWord(data, offset + 26) * 2
    let repeatLength = beWord(data, offset + 28) * 2
    if (data[offset + 24] and 0xf0) != 0 or volume > 64:
      raise newException(ValueError, "invalid MOD sample tuning or volume")
    headers.add ProtrackerSampleHeader(name: fixedText(data, offset, 22),
      lengthBytes: lengthBytes,
      fineTune: if fineNibble < 8: fineNibble else: fineNibble - 16,
      volume: volume, repeatStart: repeatStart, repeatLength: repeatLength)
    totalSampleBytes += lengthBytes

  var highestPattern = 0
  for index in 0 ..< 128:
    highestPattern = max(highestPattern, int(data[patternTableOffset + index]))
  let patternCount = highestPattern + 1
  let patternBytes = patternCount * ProtrackerPatternRows * channels * 4
  if patternBytes > data.len - patternDataOffset or
      totalSampleBytes != data.len - patternDataOffset - patternBytes:
    raise newException(ValueError,
      "MOD pattern and sample lengths do not match the file")

  result.sampleCount = sampleCount
  result.signature = signature
  result.module.title = fixedText(data, 0, 20)
  result.module.initialSpeed = ProtrackerInitialSpeed
  result.module.initialTempoBpm = ProtrackerInitialTempo
  result.module.rowsPerBeat = 4
  if restart != 127 and restart < songLength:
    result.module.hasRestartOrder = true
    result.module.restartOrder = restart
  for index in 0 ..< channels:
    let bias = channelBias(index)
    result.module.channels.add VextTrackerChannel(
      name: "Channel " & $(index + 1), sourceIndex: index, bias: bias,
      defaultPan: if bias == vtcbLeft: -1.0 else: 1.0)
  for index in 0 ..< songLength:
    result.module.orders.add int(data[patternTableOffset + index])

  for patternIndex in 0 ..< patternCount:
    var pattern = VextTrackerPattern(name: "Pattern " & $patternIndex,
      sourceIndex: patternIndex)
    let patternOffset = patternDataOffset + patternIndex *
      ProtrackerPatternRows * channels * 4
    for rowIndex in 0 ..< ProtrackerPatternRows:
      var row: VextTrackerRow
      for channel in 0 ..< channels:
        let offset = patternOffset + (rowIndex * channels + channel) * 4
        let sampleNumber = int(data[offset] and 0xf0) or
          int(data[offset + 2] shr 4)
        let period = int(data[offset] and 0x0f) shl 8 or int(data[offset + 1])
        let command = int(data[offset + 2] and 0x0f)
        let parameter = int(data[offset + 3])
        if sampleNumber > sampleCount:
          raise newException(ValueError,
            "MOD pattern references a missing sample")
        var cell = VextTrackerCell(
          hasInstrument: sampleNumber > 0,
          instrument: if sampleNumber > 0: sampleNumber - 1 else: 0,
          effects: decodeEffects(command, parameter))
        if period > 0:
          cell.hasSourcePitch = true
          cell.sourcePitch = period
          cell.note = noteForPeriod(period)
          cell.noteKind = if command in [3, 5]: vtnkTarget else: vtnkTrigger
        row.cells.add cell
      pattern.rows.add row
    result.module.patterns.add pattern

  var sampleOffset = patternDataOffset + patternBytes
  for index, header in headers:
    var samples: seq[VextAudioSample]
    if header.lengthBytes != 2:
      samples = newSeq[VextAudioSample](header.lengthBytes)
      for sampleIndex in 0 ..< header.lengthBytes:
        samples[sampleIndex] = int32(cast[int8](data[sampleOffset + sampleIndex]))
    let hasLoop = header.repeatLength > 2
    if hasLoop and (header.repeatStart > samples.len or
        header.repeatLength > samples.len - header.repeatStart):
      raise newException(ValueError, "MOD sample loop exceeds its sample data")
    result.module.instruments.add VextTrackerInstrument(
      name: header.name, sourceIndex: index + 1, referenceNote: 36,
      fineTuneCents: float64(header.fineTune) * 12.5,
      sample: VextSampledInstrument(
        sound: VextSound(sampleRate: ProtrackerReferenceSampleRate,
          buffer: VextAudioBuffer(bitsPerSample: 8, channels: @[samples])),
        oneShotSamples: if hasLoop: header.repeatStart else: samples.len,
        repeatSamples: if hasLoop: header.repeatLength else: 0,
        samplesPerHighCycle: 0, volume: float64(header.volume) / 64.0,
        pan: 0.0))
    sampleOffset += header.lengthBytes
  result.module.loopAnalysis = analyseControlFlow(result.module)
  result.module.validate

proc parseProtrackerMod*(data: openArray[byte]): ProtrackerMod =
  if data.len >= 1084:
    let signature = fixedText(data, 1080, 4)
    let info = signature.signatureInfo
    if info.known:
      return parseVariant(data, 31, info.channels, signature)
  parseVariant(data, 15, 4, "")

proc isProtrackerMod*(data: openArray[byte]): bool =
  try:
    discard parseProtrackerMod(data)
    true
  except ValueError:
    false

proc hasProtrackerModExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".mod")
