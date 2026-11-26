## Bounded four-voice TFMX preview; format semantics from the locally supplied
## player, independently expressed in Nim. This is not a Paula emulator.
import std/math
import ../containers/tfmx
import ../archetypes/audio

const
  TfmxReplaySampleRate* = 22050
  MaximumTfmxReplaySeconds* = 300
  TfmxReplayFilterCutoffHz* = 4500.0
  MixOversampling = 4
  Periods = [0x6ae,0x64e,0x5f4,0x59e,0x54d,0x501,0x4b9,0x475,
    0x435,0x3f9,0x3c0,0x38c,0x358,0x32a,0x2fc,0x2d0,
    0x2a8,0x282,0x25e,0x23b,0x21b,0x1fd,0x1e0,0x1c6,
    0x1ac,0x194,0x17d,0x168,0x154,0x140,0x12f,0x11e,
    0x10e,0xfe,0xf0,0xe3,0xd6,0xca,0xbf,0xb4,0xaa,0xa0,
    0x97,0x8f,0x87,0x7f,0x78,0x71,0xd6,0xca,0xbf,0xb4,
    0xaa,0xa0,0x97,0x8f,0x87,0x7f,0x78,0x71,0xd6,0xca,0xbf,0xb4]
type
  TfmxEffectMode* = enum
    temClassic, temProfessional
  TfmxRenderResult* = object
    sound*: VextSound
    termination*: string
  Track = object
    active: bool
    base, pc, transpose, wait, loops, returnBase, returnPc: int
  Voice = object
    running, dma, keyDown, deferWait, pendingOn, pendingOff: bool
    base, pc, wait, loops, returnBase, returnPc: int
    note, previousNote, coarseVolume, detune, volume: int
    start, length, playingStart, playingLength: int
    position, increment: uint64
    period, target, portaPeriod, portaRate, portaTime, portaCount: int
    effectState: int
    vibTime, vibCount, vibDelta, vibValue: int
    envTime, envCount, envDelta, envTarget: int
    beginTime, beginCount, beginDelta: int
    dmaWait, lockTime, lockFlag: int
  Player = object
    module: TfmxModule
    effectMode: TfmxEffectMode
    tracks: array[8, Track]
    voices: array[4, Voice]
    song: TfmxSong
    position, divisor, speedCount, trackLoops: int
    bpm, master, fadeTarget, fadeTime, fadeCount: int
    stopped: bool
    reason: string

proc signedByte(value: int): int =
  if (value and 128) != 0: (value and 255) - 256 else: value and 255
proc signedWord(value: int): int =
  if (value and 32768) != 0: (value and 65535) - 65536 else: value and 65535
proc byteDec(value: var int) = value = (value - 1) and 255
proc command(p: Player, base, pc: int): array[4, int] =
  if pc < 0 or pc > (p.module.data.len - base - 4) div 4:
    raise newException(ValueError, "TFMX program counter outside music data")
  let offset = base + pc * 4
  if base < 0 or offset < 0 or offset > p.module.data.len - 4:
    raise newException(ValueError, "TFMX instruction outside music data")
  for i in 0 ..< 4: result[i] = int(p.module.data[offset+i])
proc fade(p: var Player, time, target: int) =
  p.fadeTarget = clamp(target, 0, 64)
  p.fadeTime = time
  p.fadeCount = time
  if time == 0: p.master = p.fadeTarget
proc setVibrato(v: var Voice, time, delta: int, mode: TfmxEffectMode) =
  v.vibTime = if mode == temClassic: time and 254 else: time
  v.vibCount = v.vibTime div 2
  v.vibDelta = signedByte(delta)
  v.vibValue = 0
proc setEnvelope(v: var Voice, delta, time, target: int) =
  v.envTime = time
  v.envCount = time
  v.envDelta = delta
  v.envTarget = target
proc setPorta(v: var Voice, time, rate: int) =
  v.portaTime = time
  v.portaCount = 1
  if v.portaRate == 0: v.portaPeriod = v.target
  v.portaRate = rate
proc note(p: var Player, c: array[4, int]) =
  let channel = c[2] and 15
  if channel > 3:
    raise newException(ValueError, "TFMX seven-voice playback is not implemented")
  template v: untyped = p.voices[channel]
  if c[0] == 0xfc: # Player NOTEPORT uses FC for channel locking.
    v.lockFlag = c[1]
    v.lockTime = c[3]
    return
  if v.lockFlag != 0: return
  case c[0]
  of 0xf5: v.keyDown = false
  of 0xf6: v.setVibrato(c[1] and 254, c[3], p.effectMode)
  of 0xf7: v.setEnvelope(c[1], (c[2] shr 4) + 1, c[3])
  of 0xbf .. 0xef:
    v.setPorta(c[1], c[3])
    v.note = c[0] and 63
    v.target = Periods[v.note]
  else:
    if c[0] >= 0xf0: return
    v.detune = signedByte(c[3])
    v.coarseVolume = c[2] shr 4
    v.previousNote = v.note
    v.note = c[0] and 63
    v.base = p.module.pointer(true, c[1])
    v.pc = 0
    v.wait = 0
    v.loops = 255
    v.effectState = 0
    v.running = true
    v.keyDown = true
    v.dmaWait = -1

proc loadStep(p: var Player) =
  for attempt in 0 ..< 256:
    let offset = p.module.trackOffset + p.position * 16
    var words: array[8,int]
    for i in 0 ..< 8: words[i] = p.module.data.word(offset + i*2)
    if words[0] != 0xeffe:
      for i in 0 ..< 8:
        let pattern = words[i] shr 8
        p.tracks[i].transpose = signedByte(words[i])
        if pattern < 0x80:
          p.tracks[i].base = p.module.pointer(false, pattern)
          p.tracks[i].pc = 0
          p.tracks[i].wait = 0
          p.tracks[i].loops = 255
          p.tracks[i].active = true
        elif pattern == 0xfe:
          let channel = words[i] and 15
          if channel < 4 and p.voices[channel].lockFlag == 0:
            p.voices[channel].running = false
            p.voices[channel].dma = false
          p.tracks[i].active = false
        elif pattern != 0x80: p.tracks[i].active = false
      return
    case words[1]
    of 0:
      p.stopped = true
      p.reason = "stop command"
      return
    of 1:
      if p.trackLoops == 0:
        p.trackLoops = -1
        inc p.position
      else:
        if p.trackLoops < 0: p.trackLoops = words[3] - 1
        else: dec p.trackLoops
        p.position = words[2]
    of 2:
      p.divisor = words[2]
      p.speedCount = words[2]
      if words[3] < 32768: p.bpm = if words[3] >= 32: words[3] else: 125
      inc p.position
    of 3:
      if words[2] > 1:
        raise newException(ValueError, "TFMX seven-voice track command is not implemented")
      inc p.position
    of 4:
      p.fade(words[2] and 255, words[3] and 255)
      inc p.position
    else: inc p.position
  raise newException(ValueError, "TFMX track command safety limit exhausted")

proc patterns(p: var Player) =
  dec p.speedCount
  if p.speedCount >= 0: return
  p.speedCount = p.divisor
  var restarts = 0
  var trackIndex = 0
  while trackIndex < 8 and not p.stopped:
    let i = trackIndex
    inc trackIndex
    template t: untyped = p.tracks[i]
    if not t.active: continue
    if t.wait > 0:
      dec t.wait
      continue
    var yielded = false
    for budget in 0 ..< 1024:
      var c = p.command(t.base, t.pc)
      inc t.pc
      let parameter = c[2]*256+c[3]
      if c[0] < 0xf0:
        let original = c[0]
        if original >= 0x7f and original < 0xc0:
          t.wait = c[3]
          c[3] = 0
        c[0] = (original + t.transpose) and 255
        if original < 0xc0: c[0] = c[0] and 63
        p.note(c)
        if original >= 0x7f and original < 0xc0:
          yielded = true
          break
      else:
        case c[0]
        of 0xf0:
          t.active = false
          if p.position == p.song.last:
            p.stopped = true
            p.reason = "song end"
          else:
            inc p.position
            p.loadStep()
            trackIndex = 0
            inc restarts
            if restarts > 256:
              raise newException(ValueError, "TFMX pattern/track safety limit exhausted")
          yielded = true
          break
        of 0xf1:
          if t.loops == 0: t.loops = 255
          else:
            if t.loops == 255: t.loops = (c[1]-1) and 255
            else: byteDec(t.loops)
            t.pc = parameter
        of 0xf2, 0xf8:
          if c[0] == 0xf8:
            t.returnBase = t.base
            t.returnPc = t.pc
          t.base = p.module.pointer(false, c[1])
          t.pc = parameter
        of 0xf3:
          t.wait = c[1]
          yielded = true
          break
        of 0xf4, 0xfe:
          t.active = false
          yielded = true
          break
        of 0xf5, 0xf6, 0xf7, 0xfc: p.note(c)
        of 0xf9:
          t.base = t.returnBase
          t.pc = t.returnPc
        of 0xfa: p.fade(c[1],c[3])
        of 0xfb:
          let other = c[2]
          if other >= 8: raise newException(ValueError, "TFMX pattern track outside 0..7")
          p.tracks[other].base = p.module.pointer(false,c[1])
          p.tracks[other].pc = 0
          p.tracks[other].wait = 0
          p.tracks[other].loops = 255
          p.tracks[other].transpose = signedByte(c[3])
          p.tracks[other].active = true
        else: discard
    if not yielded:
      raise newException(ValueError, "TFMX pattern instruction safety limit exhausted")

proc runMacro(p: var Player, channel: int) =
  template v: untyped = p.voices[channel]
  if v.lockTime >= 0: dec v.lockTime
  else: v.lockFlag = 0
  if not v.running: return
  if v.dmaWait >= 0: return
  if v.wait > 0:
    dec v.wait
    return
  for budget in 0 ..< 1024:
    let c = p.command(v.base, v.pc)
    let w = c[2]*256+c[3]
    let address = c[1]*65536+w
    inc v.pc
    case c[0]
    of 0x00:
      v.beginTime = 0
      v.envTime = 0
      v.vibTime = 0
      v.portaRate = 0
      v.volume = (c[3] + (if c[2] == 0: v.coarseVolume*3 else: 0)) and 255
      v.dma = false
      v.pendingOn = false
      if c[1] != 0:
        v.pendingOff = true
        v.deferWait = false
        return
    of 0x01:
      v.effectState = signedByte(c[1])
      v.pendingOn = true
    of 0x02:
      v.beginTime = 0
      v.start = address and not 1
    of 0x03: v.length = (if w == 0: 65536 else: w)*2
    of 0x04:
      v.wait = w
      if v.deferWait: return
      v.deferWait = true
    of 0x05, 0x10:
      if c[0] == 0x10 and not v.keyDown: discard
      elif v.loops == 0: v.loops = 255
      else:
        if v.loops == 255: v.loops = (c[1]-1) and 255
        else: byteDec(v.loops)
        v.pc = w
    of 0x06, 0x15:
      if c[0] == 0x15:
        v.returnBase = v.base
        v.returnPc = v.pc
      v.base = p.module.pointer(true,c[1] and 127)
      v.pc = w
      v.loops = 255
    of 0x07:
      v.running = false
      return
    of 0x08, 0x09, 0x1f:
      let n = ((if c[0] == 8: v.note elif c[0] == 0x1f: v.previousNote else: 0) + c[1]) and 63
      let tuning = (v.detune + w) and 65535
      v.target = if p.effectMode == temClassic:
        (Periods[n] + tuning) and 65535
        else: (Periods[n] * ((256 + tuning) and 65535) shr 8) and 65535
      if v.portaRate == 0: v.period = v.target
      if v.deferWait: return
      v.deferWait = true
    of 0x0a:
      v.beginTime = 0
      v.envTime = 0
      v.vibTime = 0
      v.portaRate = 0
    of 0x0b: v.setPorta(c[1],w)
    of 0x0c: v.setVibrato(c[1],c[3],p.effectMode)
    of 0x0d: v.volume = (v.coarseVolume*3+w) and 255
    of 0x0e: v.volume = c[3]
    of 0x0f: v.setEnvelope(c[1],c[2],c[3])
    of 0x11:
      v.beginTime = c[1]
      v.beginCount = c[1]
      v.beginDelta = signedWord(w)
      v.start += v.beginDelta
    of 0x12: v.length = ((v.length div 2 + w) and 65535)*2
    of 0x13:
      if c[1] != 0:
        v.pendingOff = true
        v.deferWait = false
        return
      v.dma = false
      v.pendingOn = false
    of 0x14:
      if v.keyDown:
        if v.loops == 0: v.loops = 255
        else:
          if v.loops == 255: v.loops = (c[3]-1) and 255
          else: byteDec(v.loops)
          dec v.pc
          return
    of 0x16:
      v.base = v.returnBase
      v.pc = v.returnPc
    of 0x17:
      v.target = w
      if v.portaRate == 0: v.period = w
    of 0x18:
      v.start += address
      v.length = ((v.length div 2 - (address and 65535) div 2) and 65535)*2
    of 0x19:
      v.beginTime = 0
      v.start = 0
      v.length = 2
    of 0x1a:
      v.dmaWait = w
      if v.deferWait: return
      v.deferWait = true
    of 0x1b, 0x1e, 0x20: discard # No-ops in this supplied player version.
    of 0x1c:
      if v.note > c[1]: v.pc = w
    of 0x1d:
      if v.volume > c[1]: v.pc = w
    of 0x21:
      p.note([v.note,c[1],(v.coarseVolume shl 4) or (c[2] and 15),c[3]])
    of 0x22 .. 0x29:
      raise newException(ValueError, "TFMX SID sample manipulation is not implemented")
    else:
      raise newException(ValueError, "unsupported TFMX macro opcode " & $c[0])
  raise newException(ValueError, "TFMX macro instruction safety limit exhausted")

proc effects(p: var Player, channel: int) =
  template v: untyped = p.voices[channel]
  let runEffects = v.effectState > 0
  if v.effectState == 0: v.effectState = 1
  if runEffects:
    if v.beginTime != 0:
      v.start += v.beginDelta
      byteDec(v.beginCount)
      if v.beginCount == 0:
        v.beginCount = v.beginTime
        v.beginDelta = -v.beginDelta
    if v.vibTime != 0:
      v.vibValue = signedWord(v.vibValue + v.vibDelta)
      if v.portaRate == 0:
        v.period = if p.effectMode == temClassic:
          (v.target + v.vibValue) and 65535
          else: (v.target * ((2048+v.vibValue) and 65535) shr 11) and 65535
      byteDec(v.vibCount)
      if v.vibCount == 0:
        v.vibCount = v.vibTime
        v.vibDelta = signedByte(-v.vibDelta)
    if v.portaRate != 0:
      byteDec(v.portaCount)
      if v.portaCount == 0:
        v.portaCount = v.portaTime
        if v.portaPeriod > v.target:
          v.portaPeriod = if p.effectMode == temClassic:
            (v.portaPeriod - v.portaRate) and 65535
            else: v.portaPeriod * ((256-v.portaRate) and 65535) shr 8
          if v.portaPeriod <= v.target:
            v.portaPeriod = v.target
            v.portaRate = 0
        else:
          v.portaPeriod = if p.effectMode == temClassic:
            (v.portaPeriod + v.portaRate) and 65535
            else: v.portaPeriod * ((256+v.portaRate) and 65535) shr 8
          if v.portaPeriod >= v.target:
            v.portaPeriod = v.target
            v.portaRate = 0
        v.portaPeriod = v.portaPeriod and 2047
        v.period = v.portaPeriod
    if v.envTime != 0:
      if v.envCount > 0: dec v.envCount
      else:
        v.envCount = v.envTime
        if v.volume > v.envTarget: v.volume = max(v.envTarget,v.volume-v.envDelta)
        else: v.volume = min(v.envTarget,v.volume+v.envDelta)
        if v.volume == v.envTarget: v.envTime = 0
  # The original master fade counter is advanced once per synthesized voice.
  if p.fadeTime != 0 and p.master != p.fadeTarget:
    byteDec(p.fadeCount)
    if p.fadeCount == 0:
      p.fadeCount = p.fadeTime
      p.master += (if p.master < p.fadeTarget: 1 else: -1)

proc renderTfmx*(module: TfmxModule, samples: openArray[byte], songIndex = 0,
    maximumSeconds = MaximumTfmxReplaySeconds,
    effectMode = temClassic, applyFilter = true): TfmxRenderResult =
  if maximumSeconds < 1 or maximumSeconds > MaximumTfmxReplaySeconds:
    raise newException(ValueError, "TFMX preview duration outside safety bounds")
  if samples.len == 0:
    raise newException(ValueError, "TFMX sample companion is empty or missing")
  var p = Player(module: module, effectMode: effectMode,
    bpm: 125, master: 64, trackLoops: -1)
  var found = false
  for song in module.songs:
    if song.index == songIndex:
      p.song = song
      found = true
  if not found: raise newException(ValueError, "TFMX song number not available")
  if p.song.tempo shr 8 == 0xef:
    raise newException(ValueError, "TFMX seven-voice tempo is not implemented")
  if p.song.tempo < 16: p.divisor = p.song.tempo
  else: p.bpm = if p.song.tempo >= 32: p.song.tempo else: 125
  p.position = p.song.first
  for v in p.voices.mitems:
    v.dmaWait = -1
    v.lockTime = -1
  p.loadStep()
  result.sound = VextSound(sampleRate: TfmxReplaySampleRate,
    buffer: VextAudioBuffer(bitsPerSample: 16, channels: @[newSeq[int32](), newSeq[int32]()]))
  let maxFrames = maximumSeconds * TfmxReplaySampleRate
  var rendered = 0
  var exactFrames = 0.0
  var tick = 0
  var filterLeft, filterRight: float64
  let filterAlpha = 1.0 - exp(-2.0 * PI * TfmxReplayFilterCutoffHz /
    float64(TfmxReplaySampleRate * MixOversampling))
  while not p.stopped and rendered < maxFrames:
    for ch in 0 ..< 4:
      if p.voices[ch].pendingOff:
        p.voices[ch].dma = false
        p.voices[ch].pendingOff = false
      p.runMacro(ch)
      p.effects(ch)
    p.patterns()
    for ch in 0 ..< 4:
      template v: untyped = p.voices[ch]
      if v.pendingOn and not v.dma:
        v.playingStart = v.start and not 1
        v.playingLength = v.length
        v.position = 0
        v.dma = true
      v.pendingOn = false
      v.increment = if v.period > 0:
        uint64(3546895.0 / float64(v.period) / float64(TfmxReplaySampleRate * MixOversampling) * 4294967296.0)
        else: 0'u64
    # The supplied source hardcodes an NTSC timer numerator. Pair the PAL
    # sample clock with a PAL CIA timer, preserving nominal 24 ticks/beat.
    # A CIA reload of N counts N+1 clocks.
    let timer = (709379 * 5 div 2) div p.bpm
    exactFrames += float64(TfmxReplaySampleRate) * float64(timer + 1) / 709379.0
    let frameEnd = min(maxFrames,int(floor(exactFrames)))
    for frame in rendered ..< frameEnd:
      var accumulatedLeft, accumulatedRight: float64
      # Mix the DAC's held sample values above the output rate, then average
      # each output frame. This reduces aliases and gives the fixed low-pass
      # a useful analogue-like response near the output Nyquist frequency.
      for subFrame in 0 ..< MixOversampling:
        var left, right: int
        for ch in 0 ..< 4:
          template v: untyped = p.voices[ch]
          if not v.dma or v.increment == 0: continue
          let pos = int(v.position shr 32)
          if v.playingLength <= 0 or pos >= v.playingLength:
            v.dma = false
            continue
          let offset = v.playingStart + pos
          let sample = if offset >= 4 and offset < samples.len: int(cast[int8](samples[offset])) else: 0
          let volume = clamp(v.volume,0,64)
          let amplitude = sample * volume * clamp(p.master,0,64) div 64
          if ch in [0,3]: left += amplitude
          else: right += amplitude
          v.position += v.increment
          let endPos = uint64(v.playingLength) shl 32
          if v.position >= endPos:
            v.position -= endPos
            v.playingStart = v.start and not 1
            v.playingLength = v.length
            if v.playingLength <= 0: v.dma = false
            else: v.position = v.position mod (uint64(v.playingLength) shl 32)
            if v.dmaWait >= 0: dec v.dmaWait
        if applyFilter:
          filterLeft += filterAlpha * (float64(left) - filterLeft)
          filterRight += filterAlpha * (float64(right) - filterRight)
        else:
          filterLeft = float64(left)
          filterRight = float64(right)
        accumulatedLeft += filterLeft
        accumulatedRight += filterRight
      # Two voices per lane, fixed headroom without per-song normalization.
      result.sound.buffer.channels[0].add int32(clamp(
        round(accumulatedLeft * 2.0 / MixOversampling), -32768.0, 32767.0))
      result.sound.buffer.channels[1].add int32(clamp(
        round(accumulatedRight * 2.0 / MixOversampling), -32768.0, 32767.0))
    rendered = frameEnd
    inc tick
    if tick > MaximumTfmxReplaySeconds*1000:
      raise newException(ValueError, "TFMX tick safety limit exhausted")
  result.termination = if p.stopped: p.reason else: "preview duration limit"
