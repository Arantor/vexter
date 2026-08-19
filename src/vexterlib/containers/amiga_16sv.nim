## Parser and decoder for IFF 16SV sampled instruments.

import std/[os, strutils]
import ./amiga_iff
import ../archetypes/audio

const
  Amiga16svTypeId* = "amiga.16sv"
  Amiga16svResourcePath* = "/instrument"
  Amiga16svResourceTypeId* = "amiga.16sv-instrument"

type
  Amiga16sv* = object
    oneShotSamples*: int
    repeatSamples*: int
    samplesPerHighCycle*: int
    sampleRate*: int
    octaves*: int
    compression*: int
    volumeRaw*: uint32
    channelMask*: int
    name*: string
    annotation*: string
    author*: string
    copyright*: string
    version*: string
    body*: seq[byte]

proc be16(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc be32(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc text(data: openArray[byte]): string =
  for value in data:
    if value == 0: break
    result.add char(value)

proc parseAmiga16sv*(data: openArray[byte]): Amiga16sv =
  let form = parseAmigaIff(data)
  if form.formType != "16SV":
    raise newException(ValueError, "IFF form is not a 16SV")
  var haveHeader, haveBody, haveChannels = false
  for chunk in form.chunks:
    case chunk.id
    of "VHDR":
      if haveHeader: raise newException(ValueError, "16SV has more than one VHDR chunk")
      if chunk.data.len != 20: raise newException(ValueError, "16SV VHDR must contain 20 bytes")
      haveHeader = true
      result.oneShotSamples = int(be32(chunk.data, 0))
      result.repeatSamples = int(be32(chunk.data, 4))
      result.samplesPerHighCycle = int(be32(chunk.data, 8))
      result.sampleRate = be16(chunk.data, 12)
      result.octaves = int(chunk.data[14])
      result.compression = int(chunk.data[15])
      result.volumeRaw = be32(chunk.data, 16)
    of "CHAN":
      if haveChannels: raise newException(ValueError, "16SV has more than one CHAN chunk")
      if chunk.data.len != 4: raise newException(ValueError, "16SV CHAN must contain 4 bytes")
      haveChannels = true
      result.channelMask = int(be32(chunk.data, 0))
    of "NAME": result.name = text(chunk.data)
    of "ANNO": result.annotation = text(chunk.data)
    of "AUTH": result.author = text(chunk.data)
    of "(c) ": result.copyright = text(chunk.data)
    of "FVER": result.version = text(chunk.data)
    of "BODY":
      if haveBody: raise newException(ValueError, "16SV has more than one BODY chunk")
      haveBody = true
      result.body = chunk.data
    else: discard
  if not haveHeader: raise newException(ValueError, "16SV is missing its VHDR chunk")
  if not haveBody: raise newException(ValueError, "16SV is missing its BODY chunk")
  if result.body.len == 0: raise newException(ValueError, "16SV BODY is empty")
  if result.sampleRate == 0: raise newException(ValueError, "16SV sample rate must be positive")
  if result.octaves != 1: raise newException(ValueError, "multi-octave 16SV is not supported")
  if result.compression != 0:
    raise newException(ValueError, "unsupported 16SV compression " & $result.compression)
  if result.channelMask notin [0, 2, 4, 6]:
    raise newException(ValueError, "unsupported 16SV channel mask " & $result.channelMask)

proc isAmiga16sv*(data: openArray[byte]): bool =
  try:
    discard parseAmiga16sv(data)
    true
  except ValueError:
    false

proc hasAmiga16svExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".16sv", ".16svx"]

proc decodeAmiga16sv*(source: Amiga16sv): VextSampledInstrument =
  let channelCount = if source.channelMask == 6: 2 else: 1
  if source.body.len mod (channelCount * 2) != 0:
    raise newException(ValueError,
      "16SV BODY cannot be divided into complete samples for its channels")
  let samplesPerChannel = source.body.len div (channelCount * 2)
  var buffer = VextAudioBuffer(bitsPerSample: 16)
  for channel in 0 ..< channelCount:
    var samples = newSeq[VextAudioSample](samplesPerChannel)
    let channelOffset = channel * samplesPerChannel * 2
    for index in 0 ..< samplesPerChannel:
      let word = uint16(be16(source.body, channelOffset + index * 2))
      samples[index] = VextAudioSample(cast[int16](word))
    buffer.channels.add samples
  buffer.validate
  if source.oneShotSamples + source.repeatSamples > buffer.sampleCount:
    raise newException(ValueError, "16SV VHDR sample regions exceed the decoded BODY")
  VextSampledInstrument(
    sound: VextSound(buffer: buffer, sampleRate: source.sampleRate),
    oneShotSamples: source.oneShotSamples,
    repeatSamples: source.repeatSamples,
    samplesPerHighCycle: source.samplesPerHighCycle,
    volume: float64(source.volumeRaw) / 65536.0,
    pan: if source.channelMask == 2: -1.0 elif source.channelMask == 4: 1.0 else: 0.0)

