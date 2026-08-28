## Bounded Creative Voice (VOC) parsing and PCM/ADPCM decoding.

import std/[os, strutils]
import ../archetypes/audio

const
  CreativeVoiceTypeId* = "creative.voice"
  CreativeVoiceSoundTypeId* = "creative.voice.sound"
  CreativeVoiceSoundResourcePath* = "/audio"
  MaximumCreativeVoiceBlocks* = 100_000
  MaximumCreativeVoiceOperations* = 100_000
  MaximumCreativeVoiceSamples* = 64 * 1024 * 1024
  MaximumCreativeVoiceRepeatDepth* = 16

type
  CreativeVoiceBlock* = object
    blockType*: int
    size*: int

  CreativeVoiceSource* = object
    dataOffset*: int
    version*: int
    validation*: int
    sampleRate*: int
    bitsPerSample*: int
    channelCount*: int
    usesExtendedInfo*: bool
    extendedTimeConstant*: int
    packMethod*: int
    voiceMode*: int
    codec*: int
    samples*: seq[VextAudioSample]
    channels*: seq[seq[VextAudioSample]]
    blocks*: seq[CreativeVoiceBlock]

  CreativeVoiceOperationKind = enum
    cvokAudio, cvokSilence

  CreativeVoiceOperation = object
    kind: CreativeVoiceOperationKind
    data: seq[byte]
    codec: int
    includesReference: bool
    bitsPerSample: int
    channelCount: int
    silenceSamples: int

  CreativeVoiceAdpcmState = object
    prediction: int
    step: int

proc le16(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc le24(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16)

proc le32(data: openArray[byte], offset: int): int64 {.inline.} =
  int64(data[offset]) or (int64(data[offset + 1]) shl 8) or
    (int64(data[offset + 2]) shl 16) or (int64(data[offset + 3]) shl 24)

proc copiedBytes(data: openArray[byte], first, pastLast: int): seq[byte] =
  result = newSeq[byte](pastLast - first)
  for index in 0 ..< result.len:
    result[index] = data[first + index]

proc ensureOutputChannels(channels: var seq[seq[VextAudioSample]], count: int) =
  if channels.len == 0:
    channels.setLen(count)
  elif channels.len != count:
    raise newException(ValueError,
      "Creative Voice stream changes channel count and cannot form one sound")

proc appendSample(channel: var seq[VextAudioSample], value: int32) =
  if channel.len >= MaximumCreativeVoiceSamples:
    raise newException(ValueError, "Creative Voice output exceeds the sample limit")
  channel.add value

proc appendSilence(channels: var seq[seq[VextAudioSample]], count: int) =
  for channel in channels.mitems:
    if count > MaximumCreativeVoiceSamples - channel.len:
      raise newException(ValueError, "Creative Voice output exceeds the sample limit")
  for channel in channels.mitems:
    channel.setLen(channel.len + count)

proc appendPcm8(channels: var seq[seq[VextAudioSample]],
    data: openArray[byte], channelCount: int) =
  if data.len mod channelCount != 0:
    raise newException(ValueError,
      "Creative Voice eight-bit PCM data does not contain complete sample frames")
  channels.ensureOutputChannels(channelCount)
  for offset, value in data:
    channels[offset mod channelCount].appendSample(int32(value) - 128)

proc appendPcm16(channels: var seq[seq[VextAudioSample]],
    data: openArray[byte], channelCount: int) =
  let frameBytes = channelCount * 2
  if data.len mod frameBytes != 0:
    raise newException(ValueError,
      "Creative Voice sixteen-bit PCM data does not contain complete sample frames")
  channels.ensureOutputChannels(channelCount)
  var offset = 0
  while offset < data.len:
    let value = data.le16(offset)
    channels[(offset div 2) mod channelCount].appendSample(
      int32(if value >= 0x8000: value - 0x10000 else: value))
    offset += 2

proc decodeAdpcmCode(samples: var seq[VextAudioSample], code, bits,
    shift, limit: int, state: var CreativeVoiceAdpcmState) =
  let signMask = 1 shl (bits - 1)
  let value = code and (signMask - 1)
  let difference = value shl (state.step + shift)
  if (code and signMask) == 0:
    state.prediction = min(255, state.prediction + difference)
  else:
    state.prediction = max(0, state.prediction - difference)
  samples.appendSample(int32(state.prediction - 128))
  if value >= limit:
    state.step = min(3, state.step + 1)
  elif value == 0:
    state.step = max(0, state.step - 1)

proc appendAdpcm(samples: var seq[VextAudioSample], data: openArray[byte],
    codec: int, includesReference: bool, state: var CreativeVoiceAdpcmState) =
  var offset = 0
  if includesReference:
    if data.len == 0:
      raise newException(ValueError,
        "Creative Voice compressed sound data has no reference sample")
    state.prediction = int(data[0])
    state.step = 0
    samples.appendSample(int32(state.prediction - 128))
    offset = 1

  let shift = if codec == 3: 2 else: 0
  let limit = case codec
    of 1: 5
    of 2: 3
    of 3: 1
    else: 0
  while offset < data.len:
    let packed = int(data[offset])
    case codec
    of 1:
      samples.decodeAdpcmCode((packed shr 4) and 0x0f, 4,
        shift, limit, state)
      samples.decodeAdpcmCode(packed and 0x0f, 4, shift, limit, state)
    of 2:
      samples.decodeAdpcmCode((packed shr 5) and 0x07, 3,
        shift, limit, state)
      samples.decodeAdpcmCode((packed shr 2) and 0x07, 3,
        shift, limit, state)
      samples.decodeAdpcmCode(packed and 0x03, 2, shift, limit, state)
    of 3:
      for bitOffset in countdown(6, 0, 2):
        samples.decodeAdpcmCode((packed shr bitOffset) and 0x03, 2,
          shift, limit, state)
    else:
      raise newException(ValueError, "unsupported Creative Voice ADPCM codec")
    inc offset

proc execute(operation: CreativeVoiceOperation,
    channels: var seq[seq[VextAudioSample]], state: var CreativeVoiceAdpcmState) =
  case operation.kind
  of cvokSilence:
    channels.ensureOutputChannels(operation.channelCount)
    channels.appendSilence(operation.silenceSamples)
  of cvokAudio:
    case operation.codec
    of 0:
      channels.appendPcm8(operation.data, operation.channelCount)
    of 1 .. 3:
      if operation.channelCount != 1 or operation.bitsPerSample != 8:
        raise newException(ValueError,
          "Creative Voice multichannel ADPCM is not supported")
      channels.ensureOutputChannels(1)
      channels[0].appendAdpcm(operation.data, operation.codec,
        operation.includesReference, state)
    of 4:
      channels.appendPcm16(operation.data, operation.channelCount)
    else:
      raise newException(ValueError, "unsupported Creative Voice codec")

proc vocSampleRate(timeConstant: int): int =
  let denominator = 256 - timeConstant
  if denominator <= 0:
    raise newException(ValueError, "Creative Voice time constant is invalid")
  result = 1_000_000 div denominator
  if result <= 0:
    raise newException(ValueError, "Creative Voice sample rate is invalid")

proc extendedVocSampleRate(timeConstant, channelCount: int): int =
  let denominator = channelCount * (65_536 - timeConstant)
  if denominator <= 0:
    raise newException(ValueError,
      "Creative Voice extended time constant is invalid")
  result = 256_000_000 div denominator
  if result <= 0:
    raise newException(ValueError,
      "Creative Voice extended sample rate is invalid")

proc requireAudioFormat(source: var CreativeVoiceSource, sampleRate,
    bitsPerSample, channelCount: int) =
  if sampleRate <= 0 or bitsPerSample notin [8, 16] or channelCount notin 1 .. 2:
    raise newException(ValueError, "Creative Voice audio format is invalid")
  if source.sampleRate == 0:
    source.sampleRate = sampleRate
    source.bitsPerSample = bitsPerSample
    source.channelCount = channelCount
  elif source.sampleRate != sampleRate or
      source.bitsPerSample != bitsPerSample or source.channelCount != channelCount:
    raise newException(ValueError,
      "Creative Voice stream changes audio format and cannot form one sound")

proc parseCreativeVoice*(data: openArray[byte]): CreativeVoiceSource =
  const signature = "Creative Voice File"
  if data.len < 26:
    raise newException(ValueError, "Creative Voice header is truncated")
  for index, expected in signature:
    if data[index] != byte(expected):
      raise newException(ValueError, "Creative Voice file signature is invalid")
  if data[19] != 0x1a:
    raise newException(ValueError,
      "Creative Voice signature terminator is invalid")
  result.dataOffset = data.le16(20)
  result.version = data.le16(22)
  result.validation = data.le16(24)
  if result.dataOffset < 26 or result.dataOffset > data.len:
    raise newException(ValueError,
      "Creative Voice first-block offset is outside the file")
  let expectedValidation = ((not result.version) + 0x1234) and 0xffff
  if result.validation != expectedValidation:
    raise newException(ValueError,
      "Creative Voice version validation word is invalid")

  var offset = result.dataOffset
  var currentCodec = -1
  var haveAudioFormat = false
  var havePendingExtension = false
  var operations: seq[CreativeVoiceOperation]
  var state: CreativeVoiceAdpcmState
  var repeats: seq[tuple[startOperation: int, count: int]]
  while offset < data.len:
    if result.blocks.len >= MaximumCreativeVoiceBlocks:
      raise newException(ValueError,
        "Creative Voice block count exceeds the safety limit")
    let blockType = int(data[offset])
    inc offset
    if havePendingExtension and blockType != 0x01:
      raise newException(ValueError,
        "Creative Voice extended block must immediately precede sound data")
    if blockType in [0x00, 0x07]:
      result.blocks.add CreativeVoiceBlock(blockType: blockType, size: 0)
      if blockType == 0x00:
        if offset != data.len:
          raise newException(ValueError,
            "Creative Voice terminator is followed by trailing data")
        break
      if repeats.len == 0:
        raise newException(ValueError,
          "Creative Voice repeat end has no matching repeat block")
      let loop = repeats.pop()
      let operationCount = operations.len - loop.startOperation
      if operationCount > 0 and loop.count > 1:
        if operationCount >
            (MaximumCreativeVoiceOperations - operations.len) div (loop.count - 1):
          raise newException(ValueError,
            "Creative Voice repeat exceeds the operation limit")
        let segment = operations[loop.startOperation ..< operations.len]
        for repetition in 1 ..< loop.count:
          for operation in segment:
            operation.execute(result.channels, state)
            operations.add operation
      continue

    if data.len - offset < 3:
      raise newException(ValueError, "Creative Voice block header is truncated")
    let size = data.le24(offset)
    offset += 3
    if size > data.len - offset:
      raise newException(ValueError, "Creative Voice block payload is truncated")
    let payload = offset
    result.blocks.add CreativeVoiceBlock(blockType: blockType, size: size)

    case blockType
    of 0x01:
      if size < 2:
        raise newException(ValueError,
          "Creative Voice sound-data block is shorter than two bytes")
      let channelCount = if havePendingExtension: result.voiceMode + 1 else: 1
      let sampleRate = if havePendingExtension:
          extendedVocSampleRate(result.extendedTimeConstant, channelCount)
        else:
          vocSampleRate(int(data[payload]))
      currentCodec = if havePendingExtension:
          result.packMethod
        else:
          int(data[payload + 1])
      if currentCodec notin 0 .. 3:
        raise newException(ValueError, "unsupported Creative Voice codec")
      if currentCodec != 0 and channelCount != 1:
        raise newException(ValueError,
          "Creative Voice multichannel ADPCM is not supported")
      result.requireAudioFormat(sampleRate, 8, channelCount)
      result.codec = currentCodec
      havePendingExtension = false
      haveAudioFormat = true
      let operation = CreativeVoiceOperation(kind: cvokAudio,
        data: copiedBytes(data, payload + 2, payload + size),
        codec: currentCodec, includesReference: currentCodec != 0,
        bitsPerSample: 8, channelCount: channelCount)
      operation.execute(result.channels, state)
      if operations.len >= MaximumCreativeVoiceOperations:
        raise newException(ValueError,
          "Creative Voice operation count exceeds the safety limit")
      operations.add operation
    of 0x02:
      if not haveAudioFormat:
        raise newException(ValueError,
          "Creative Voice continuation precedes sound data")
      let operation = CreativeVoiceOperation(kind: cvokAudio,
        data: copiedBytes(data, payload, payload + size), codec: currentCodec,
        bitsPerSample: result.bitsPerSample, channelCount: result.channelCount)
      operation.execute(result.channels, state)
      if operations.len >= MaximumCreativeVoiceOperations:
        raise newException(ValueError,
          "Creative Voice operation count exceeds the safety limit")
      operations.add operation
    of 0x03:
      if size != 3:
        raise newException(ValueError,
          "Creative Voice silence block must contain three bytes")
      result.requireAudioFormat(vocSampleRate(int(data[payload + 2])), 8, 1)
      let operation = CreativeVoiceOperation(kind: cvokSilence,
        channelCount: 1, silenceSamples: data.le16(payload) + 1)
      operation.execute(result.channels, state)
      if operations.len >= MaximumCreativeVoiceOperations:
        raise newException(ValueError,
          "Creative Voice operation count exceeds the safety limit")
      operations.add operation
    of 0x04:
      if size != 2:
        raise newException(ValueError,
          "Creative Voice marker block must contain two bytes")
    of 0x05:
      if size == 0 or data[payload + size - 1] != 0:
        raise newException(ValueError,
          "Creative Voice text block must be null terminated")
    of 0x06:
      if size != 2:
        raise newException(ValueError,
          "Creative Voice repeat block must contain two bytes")
      if repeats.len >= MaximumCreativeVoiceRepeatDepth:
        raise newException(ValueError,
          "Creative Voice repeat nesting exceeds the safety limit")
      let repeatValue = data.le16(payload)
      if repeatValue == 0xffff:
        raise newException(ValueError,
          "infinite Creative Voice repeats are not supported")
      repeats.add (startOperation: operations.len, count: repeatValue + 1)
    of 0x08:
      if size != 4:
        raise newException(ValueError,
          "Creative Voice extended block must contain four bytes")
      if haveAudioFormat:
        raise newException(ValueError,
          "Creative Voice extended block cannot change an active sound format")
      result.usesExtendedInfo = true
      result.extendedTimeConstant = data.le16(payload)
      result.packMethod = int(data[payload + 2])
      result.voiceMode = int(data[payload + 3])
      if result.packMethod notin 0 .. 3:
        raise newException(ValueError,
          "unsupported Creative Voice extended codec")
      if result.voiceMode notin 0 .. 1:
        raise newException(ValueError,
          "unsupported Creative Voice extended channel count")
      havePendingExtension = true
    of 0x09:
      if size < 12:
        raise newException(ValueError,
          "Creative Voice new-format block is shorter than twelve bytes")
      let storedSampleRate = data.le32(payload)
      if storedSampleRate <= 0 or storedSampleRate > int64(high(int)):
        raise newException(ValueError,
          "Creative Voice new-format sample rate is invalid")
      let sampleRate = int(storedSampleRate)
      let bitsPerSample = int(data[payload + 4])
      let channelCount = int(data[payload + 5])
      currentCodec = data.le16(payload + 6)
      if not ((currentCodec == 0 and bitsPerSample == 8) or
          (currentCodec == 4 and bitsPerSample == 16)):
        raise newException(ValueError,
          "unsupported Creative Voice new-format codec or sample width")
      result.requireAudioFormat(sampleRate, bitsPerSample, channelCount)
      result.codec = currentCodec
      haveAudioFormat = true
      let operation = CreativeVoiceOperation(kind: cvokAudio,
        data: copiedBytes(data, payload + 12, payload + size),
        codec: currentCodec, bitsPerSample: bitsPerSample,
        channelCount: channelCount)
      operation.execute(result.channels, state)
      if operations.len >= MaximumCreativeVoiceOperations:
        raise newException(ValueError,
          "Creative Voice operation count exceeds the safety limit")
      operations.add operation
    else:
      raise newException(ValueError,
        "unsupported Creative Voice block type " & $blockType)
    offset += size

  if repeats.len > 0:
    raise newException(ValueError,
      "Creative Voice repeat block has no matching end")
  if havePendingExtension:
    raise newException(ValueError,
      "Creative Voice extended block has no following sound data")
  if not haveAudioFormat:
    raise newException(ValueError, "Creative Voice file contains no sound data")
  if result.channels.len == 0 or result.channels[0].len == 0:
    raise newException(ValueError, "Creative Voice sound contains no samples")
  result.samples = result.channels[0]

proc decodeCreativeVoice*(source: CreativeVoiceSource): VextSound =
  result = VextSound(buffer: VextAudioBuffer(bitsPerSample: source.bitsPerSample,
    channels: source.channels), sampleRate: source.sampleRate)
  result.buffer.validate

proc isCreativeVoice*(data: openArray[byte]): bool =
  try:
    discard parseCreativeVoice(data)
    true
  except ValueError:
    false

proc hasCreativeVoiceExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".voc"
