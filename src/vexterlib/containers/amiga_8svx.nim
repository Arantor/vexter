## Parser and decoder for IFF 8SVX sampled instruments.

import std/[os, strutils]
import ./amiga_iff
import ../archetypes/audio

const
  Amiga8svxTypeId* = "amiga.8svx"
  Amiga8svxResourcePath* = "/instrument"
  Amiga8svxResourceTypeId* = "amiga.8svx-instrument"

type
  Amiga8svxCompression* = enum
    a8cNone = 0
    a8cFibonacciDelta = 1

  Amiga8svx* = object
    oneShotSamples*: int
    repeatSamples*: int
    samplesPerHighCycle*: int
    sampleRate*: int
    octaves*: int
    compression*: Amiga8svxCompression
    volumeRaw*: uint32
    channelMask*: int
    name*: string
    annotation*: string
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

proc parseAmiga8svx*(data: openArray[byte]): Amiga8svx =
  let form = parseAmigaIff(data)
  if form.formType != "8SVX":
    raise newException(ValueError, "IFF form is not an 8SVX")
  var haveHeader, haveBody, haveChannels = false
  result.channelMask = 0
  for chunk in form.chunks:
    case chunk.id
    of "VHDR":
      if haveHeader: raise newException(ValueError, "8SVX has more than one VHDR chunk")
      if chunk.data.len != 20: raise newException(ValueError, "8SVX VHDR must contain 20 bytes")
      haveHeader = true
      result.oneShotSamples = int(be32(chunk.data, 0))
      result.repeatSamples = int(be32(chunk.data, 4))
      result.samplesPerHighCycle = int(be32(chunk.data, 8))
      result.sampleRate = be16(chunk.data, 12)
      result.octaves = int(chunk.data[14])
      if chunk.data[15] > byte(ord(high(Amiga8svxCompression))):
        raise newException(ValueError, "unsupported 8SVX compression " & $chunk.data[15])
      result.compression = Amiga8svxCompression(chunk.data[15])
      result.volumeRaw = be32(chunk.data, 16)
    of "CHAN":
      if haveChannels: raise newException(ValueError, "8SVX has more than one CHAN chunk")
      if chunk.data.len != 4: raise newException(ValueError, "8SVX CHAN must contain 4 bytes")
      haveChannels = true
      result.channelMask = int(be32(chunk.data, 0))
    of "NAME": result.name = text(chunk.data)
    of "ANNO": result.annotation = text(chunk.data)
    of "BODY":
      if haveBody: raise newException(ValueError, "8SVX has more than one BODY chunk")
      haveBody = true
      result.body = chunk.data
    else: discard
  if not haveHeader: raise newException(ValueError, "8SVX is missing its VHDR chunk")
  if not haveBody: raise newException(ValueError, "8SVX is missing its BODY chunk")
  if result.body.len == 0: raise newException(ValueError, "8SVX BODY is empty")
  if result.sampleRate == 0: raise newException(ValueError, "8SVX sample rate must be positive")
  if result.octaves != 1: raise newException(ValueError, "multi-octave 8SVX is not supported")
  if result.channelMask notin [0, 2, 4, 6]:
    raise newException(ValueError, "unsupported 8SVX channel mask " & $result.channelMask)

proc isAmiga8svx*(data: openArray[byte]): bool =
  try:
    discard parseAmiga8svx(data)
    true
  except ValueError:
    false

proc hasAmiga8svxExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".8svx", ".8sv"]

proc decodeChannel(data: openArray[byte], compression: Amiga8svxCompression):
    seq[VextAudioSample] =
  case compression
  of a8cNone:
    for value in data: result.add VextAudioSample(cast[int8](value))
  of a8cFibonacciDelta:
    if data.len < 2: raise newException(ValueError, "compressed 8SVX BODY is truncated")
    const deltas = [-34'i32, -21, -13, -8, -5, -3, -2, -1,
      0, 1, 2, 3, 5, 8, 13, 21]
    var current = int32(cast[int8](data[1]))
    for index in 2 ..< data.len:
      for shift in [4, 0]:
        current = int32(cast[int8](current + deltas[int((data[index] shr shift) and 15)]))
        result.add current

proc decodeAmiga8svx*(source: Amiga8svx): VextSampledInstrument =
  let channelCount = if source.channelMask == 6: 2 else: 1
  if source.body.len mod channelCount != 0:
    raise newException(ValueError, "8SVX BODY cannot be divided evenly among its channels")
  let channelSize = source.body.len div channelCount
  var buffer = VextAudioBuffer(bitsPerSample: 8)
  for channel in 0 ..< channelCount:
    buffer.channels.add decodeChannel(
      source.body.toOpenArray(channel * channelSize, (channel + 1) * channelSize - 1),
      source.compression)
  buffer.validate
  let declared = source.oneShotSamples + source.repeatSamples
  if declared > buffer.sampleCount:
    raise newException(ValueError, "8SVX VHDR sample regions exceed the decoded BODY")
  VextSampledInstrument(
    sound: VextSound(buffer: buffer, sampleRate: source.sampleRate),
    oneShotSamples: source.oneShotSamples,
    repeatSamples: source.repeatSamples,
    samplesPerHighCycle: source.samplesPerHighCycle,
    volume: float64(source.volumeRaw) / 65536.0,
    pan: if source.channelMask == 2: -1.0 elif source.channelMask == 4: 1.0 else: 0.0)
