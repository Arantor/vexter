## Documented Sierra SCI0 appended digital-sample decoding.
## Format facts are derived from the supplied SCI Specifications chapter 4.

import ../archetypes/audio

type Sci0DigitalSample* = object
  headerOffset*, sampleRate*: int
  pcm*: seq[byte]

type SciAudio* = object
  ## Later SCI `SOL` digital-audio record. Codec 0 is unsigned PCM8; codec 1
  ## packs two differential samples into each byte, high nibble first.
  headerSize*, sampleRate*, codec*, encodedSize*, sampleCount*: int
  encoded*: seq[byte]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI0 digital-sample word")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc le32(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 4:
    raise newException(ValueError, "truncated SCI audio dword")
  int(data[at]) or (int(data[at + 1]) shl 8) or
    (int(data[at + 2]) shl 16) or (int(data[at + 3]) shl 24)

proc parseSciAudio*(data: openArray[byte]): SciAudio =
  var at = 0
  # Standalone resource-manager exports retain their 8d:0000 resource tag.
  if data.len >= 2 and data[0] == 0x8d and data[1] == 0:
    at = 2
  let typed = at < data.len and data[at] == 0x8d
  let headerAt = at + (if typed: 1 else: 0)
  if headerAt > data.len - 12 or
      data[headerAt + 1 .. headerAt + 4] != [0x53'u8, 0x4f, 0x4c, 0x00]:
    raise newException(ValueError, "invalid SCI SOL audio header")
  result.headerSize = int(data[headerAt]) + 1 + (if typed: 1 else: 0)
  result.sampleRate = le16(data, headerAt + 5)
  result.codec = int(data[headerAt + 7])
  result.encodedSize = le32(data, headerAt + 8)
  let payloadAt = at + result.headerSize
  if result.headerSize < 12 or result.sampleRate <= 0 or
      result.codec notin [0, 1] or result.encodedSize <= 0 or
      payloadAt > data.len - result.encodedSize or
      payloadAt + result.encodedSize != data.len:
    raise newException(ValueError, "invalid SCI SOL audio bounds or encoding")
  result.sampleCount = result.encodedSize * (if result.codec == 1: 2 else: 1)
  result.encoded = @data[payloadAt ..< data.len]

proc sound*(audio: SciAudio): VextSound =
  const deltas = [0'i32, 1, 2, 3, 6, 10, 15, 21,
    -21, -15, -10, -6, -3, -2, -1, 0]
  var channel = newSeq[VextAudioSample](audio.sampleCount)
  if audio.codec == 0:
    for index, value in audio.encoded:
      channel[index] = int32(value) - 128
  elif audio.codec == 1:
    var predictor = 128'i32
    var written = 0
    for value in audio.encoded:
      for shift in [4, 0]:
        predictor = clamp(predictor + deltas[(int(value) shr shift) and 0x0f],
          0'i32, 255'i32)
        channel[written] = predictor - 128
        inc written
  else:
    raise newException(ValueError, "unsupported SCI SOL audio codec")
  result = VextSound(sampleRate: audio.sampleRate,
    buffer: VextAudioBuffer(bitsPerSample: 8, channels: @[move(channel)]))
  result.buffer.validate()

proc parseSci0DigitalSample*(data: openArray[byte]): Sci0DigitalSample =
  if data.len < 33 or data[0] != 2:
    raise newException(ValueError, "SCI0 sound has no digital sample flag")
  let declaredOffset = (int(data[31]) shl 8) or int(data[32])
  if declaredOffset != 0:
    result.headerOffset = declaredOffset + 1
  else:
    var at = 33
    while at < data.len and data[at] != 0xfc: inc at
    if at >= data.len:
      raise newException(ValueError, "SCI0 sampled sound has no stop status")
    while at < data.len and data[at] == 0xfc: inc at
    result.headerOffset = at
  if result.headerOffset < 33 or result.headerOffset > data.len - 44:
    raise newException(ValueError, "SCI0 digital-sample header is outside the sound")
  result.sampleRate = le16(data, result.headerOffset + 14)
  let sampleLength = le16(data, result.headerOffset + 32)
  let sampleAt = result.headerOffset + 44
  if result.sampleRate <= 0:
    raise newException(ValueError, "SCI0 digital sample has no playback rate")
  if sampleLength <= 0 or sampleLength != data.len - sampleAt:
    raise newException(ValueError,
      "SCI0 digital sample length does not match the sound resource")
  result.pcm = @data[sampleAt ..< data.len]

proc sound*(sample: Sci0DigitalSample): VextSound =
  var channel = newSeq[VextAudioSample](sample.pcm.len)
  for index, value in sample.pcm:
    channel[index] = int32(value) - 128
  result = VextSound(sampleRate: sample.sampleRate,
    buffer: VextAudioBuffer(bitsPerSample: 8, channels: @[move(channel)]))
  result.buffer.validate()
