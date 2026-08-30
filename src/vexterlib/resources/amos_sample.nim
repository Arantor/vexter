## Audio conversion for records stored in AMOS `Samples` banks.

import ../archetypes/audio
import ../containers/amos_sample_bank

proc decodeAmosSample*(source: AmosSample): VextSampledInstrument =
  var samples = newSeq[VextAudioSample](source.data.len)
  for index, value in source.data:
    samples[index] = VextAudioSample(cast[int8](value))
  let buffer = VextAudioBuffer(bitsPerSample: 8, channels: @[samples])
  buffer.validate
  VextSampledInstrument(
    sound: VextSound(sampleRate: source.sampleRate, buffer: buffer),
    oneShotSamples: samples.len,
    repeatSamples: 0,
    samplesPerHighCycle: 0,
    volume: 1.0,
    pan: 0.0)
