## Generic in-memory contracts for sampled audio.

type
  VextAudioSample* = int32

  VextAudioBuffer* = object
    ## Channel-major PCM. Each channel contains the same number of samples.
    bitsPerSample*: int
    channels*: seq[seq[VextAudioSample]]

  VextSound* = object
    buffer*: VextAudioBuffer
    sampleRate*: int

  VextSampledInstrument* = object
    ## A sampled sound with the playback metadata needed by an instrument.
    sound*: VextSound
    oneShotSamples*: int
    repeatSamples*: int
    samplesPerHighCycle*: int
    volume*: float64
    pan*: float64

proc sampleCount*(buffer: VextAudioBuffer): int =
  if buffer.channels.len == 0: 0 else: buffer.channels[0].len

proc validate*(buffer: VextAudioBuffer) =
  if buffer.bitsPerSample <= 0 or buffer.bitsPerSample > 32:
    raise newException(ValueError, "audio buffer bit depth must be between 1 and 32")
  if buffer.channels.len == 0:
    raise newException(ValueError, "audio buffer must contain at least one channel")
  let count = buffer.channels[0].len
  for channel in buffer.channels:
    if channel.len != count:
      raise newException(ValueError, "audio buffer channels have different lengths")

