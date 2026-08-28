## Dependency-free uncompressed PCM WAV exporter.

import ../archetypes/audio
import ../artifacts

proc appendU16(data: var seq[byte], value: uint16) =
  data.add byte(value)
  data.add byte(value shr 8)

proc appendU32(data: var seq[byte], value: uint32) =
  data.add byte(value)
  data.add byte(value shr 8)
  data.add byte(value shr 16)
  data.add byte(value shr 24)

proc exportWav*(sound: VextSound,
    suggestedFilename = "sound.wav"): VextArtifactSet =
  sound.buffer.validate
  if sound.sampleRate <= 0:
    raise newException(ValueError, "WAV sample rate must be positive")
  if sound.buffer.bitsPerSample notin [8, 16, 24, 32]:
    raise newException(ValueError,
      "WAV PCM bit depth must be 8, 16, 24, or 32")
  if sound.buffer.channels.len > int(high(uint16)):
    raise newException(ValueError, "WAV has too many channels")

  let
    channelCount = sound.buffer.channels.len
    bytesPerSample = sound.buffer.bitsPerSample div 8
    blockAlign = channelCount * bytesPerSample
    dataLength = sound.buffer.sampleCount * blockAlign
    paddingLength = dataLength and 1
  if dataLength > int(high(uint32)) - 36 - paddingLength:
    raise newException(ValueError, "WAV sample data is too large")
  let byteRate = uint64(sound.sampleRate) * uint64(blockAlign)
  if byteRate > uint64(high(uint32)):
    raise newException(ValueError, "WAV byte rate is too large")

  var encoded: seq[byte]
  for value in "RIFF": encoded.add byte(value)
  encoded.appendU32(uint32(36 + dataLength + paddingLength))
  for value in "WAVEfmt ": encoded.add byte(value)
  encoded.appendU32(16)
  encoded.appendU16(1) # WAVE_FORMAT_PCM
  encoded.appendU16(uint16(channelCount))
  encoded.appendU32(uint32(sound.sampleRate))
  encoded.appendU32(uint32(byteRate))
  encoded.appendU16(uint16(blockAlign))
  encoded.appendU16(uint16(sound.buffer.bitsPerSample))
  for value in "data": encoded.add byte(value)
  encoded.appendU32(uint32(dataLength))

  let
    minimum = -(1'i64 shl (sound.buffer.bitsPerSample - 1))
    maximum = (1'i64 shl (sound.buffer.bitsPerSample - 1)) - 1
  for sampleIndex in 0 ..< sound.buffer.sampleCount:
    for channel in sound.buffer.channels:
      let sample = int64(channel[sampleIndex])
      if sample < minimum or sample > maximum:
        raise newException(ValueError, "audio sample is outside its declared bit depth")
      if sound.buffer.bitsPerSample == 8:
        encoded.add byte(sample + 128)
      else:
        let bits = cast[uint32](int32(sample))
        for index in 0 ..< bytesPerSample:
          encoded.add byte(bits shr (index * 8))
  if paddingLength != 0:
    encoded.add 0

  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "audio/wav",
    data: encoded)
