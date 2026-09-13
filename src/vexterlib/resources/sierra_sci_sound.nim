## Documented Sierra SCI0 appended digital-sample decoding.
## Format facts are derived from the supplied SCI Specifications chapter 4.

import ../archetypes/audio

type Sci0DigitalSample* = object
  headerOffset*, sampleRate*: int
  pcm*: seq[byte]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI0 digital-sample word")
  int(data[at]) or (int(data[at + 1]) shl 8)

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
