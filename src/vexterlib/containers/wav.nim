## RIFF/WAVE container parsing and integer PCM decoding.

import std/[os, strutils]
import ../archetypes/audio

const
  WavTypeId* = "wav"
  WavSoundTypeId* = "wav.sound"
  WavSoundResourcePath* = "/audio"

type
  WavChunk* = object
    kind*: string
    data*: seq[byte]

  WavSource* = object
    audioFormat*: int
    channelCount*: int
    sampleRate*: int
    byteRate*: int
    blockAlign*: int
    bitsPerSample*: int
    sampleData*: seq[byte]
    chunks*: seq[WavChunk]

proc le16(data: openArray[byte], offset: int): uint16 {.inline.} =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or
    (uint32(data[offset + 3]) shl 24)

proc chunkName(data: openArray[byte], offset: int): string =
  result = newString(4)
  for index in 0 ..< 4:
    result[index] = char(data[offset + index])

proc parseWav*(data: openArray[byte]): WavSource =
  if data.len < 12 or data.chunkName(0) != "RIFF" or
      data.chunkName(8) != "WAVE":
    raise newException(ValueError, "WAV must begin with a RIFF/WAVE header")
  let riffSize = int(data.le32(4))
  if riffSize != data.len - 8:
    raise newException(ValueError, "WAV RIFF size does not match the file length")

  var offset = 12
  var haveFormat = false
  var haveData = false
  while offset < data.len:
    if data.len - offset < 8:
      raise newException(ValueError, "truncated WAV chunk header")
    let
      kind = data.chunkName(offset)
      size = int(data.le32(offset + 4))
      payload = offset + 8
    if size > data.len - payload:
      raise newException(ValueError, "truncated WAV " & kind & " chunk")
    result.chunks.add WavChunk(kind: kind,
      data: @data[payload ..< payload + size])

    case kind
    of "fmt ":
      if haveFormat:
        raise newException(ValueError, "WAV contains more than one fmt chunk")
      if size < 16:
        raise newException(ValueError, "WAV fmt chunk is shorter than 16 bytes")
      haveFormat = true
      result.audioFormat = int(data.le16(payload))
      result.channelCount = int(data.le16(payload + 2))
      result.sampleRate = int(data.le32(payload + 4))
      result.byteRate = int(data.le32(payload + 8))
      result.blockAlign = int(data.le16(payload + 12))
      result.bitsPerSample = int(data.le16(payload + 14))
    of "data":
      if haveData:
        raise newException(ValueError, "WAV contains more than one data chunk")
      haveData = true
      result.sampleData = @data[payload ..< payload + size]
    else:
      discard

    let paddedSize = size + (size and 1)
    if paddedSize > data.len - payload:
      raise newException(ValueError, "WAV chunk is missing its padding byte")
    offset = payload + paddedSize

  if not haveFormat:
    raise newException(ValueError, "WAV contains no fmt chunk")
  if not haveData:
    raise newException(ValueError, "WAV contains no data chunk")
  if result.audioFormat != 1:
    raise newException(ValueError, "unsupported WAV encoding; only integer PCM is implemented")
  if result.channelCount <= 0:
    raise newException(ValueError, "WAV channel count must be positive")
  if result.sampleRate <= 0:
    raise newException(ValueError, "WAV sample rate must be positive")
  if result.bitsPerSample notin [8, 16, 24, 32]:
    raise newException(ValueError, "WAV PCM bit depth must be 8, 16, 24, or 32")
  let expectedAlign = result.channelCount * (result.bitsPerSample div 8)
  if result.blockAlign != expectedAlign:
    raise newException(ValueError, "WAV block alignment is inconsistent")
  let expectedByteRate = uint64(result.sampleRate) * uint64(expectedAlign)
  if expectedByteRate > uint64(high(uint32)) or
      result.byteRate != int(expectedByteRate):
    raise newException(ValueError, "WAV byte rate is inconsistent")
  if result.sampleData.len mod result.blockAlign != 0:
    raise newException(ValueError, "WAV data does not contain complete sample frames")

proc isWav*(data: openArray[byte]): bool =
  try:
    discard parseWav(data)
    true
  except ValueError:
    false

proc hasWavExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".wav", ".wave"]

proc decodeWav*(source: WavSource): VextSound =
  let
    bytesPerSample = source.bitsPerSample div 8
    sampleCount = source.sampleData.len div source.blockAlign
  result.sampleRate = source.sampleRate
  result.buffer.bitsPerSample = source.bitsPerSample
  result.buffer.channels = newSeq[seq[VextAudioSample]](source.channelCount)
  for channel in 0 ..< source.channelCount:
    result.buffer.channels[channel] = newSeq[VextAudioSample](sampleCount)

  for sampleIndex in 0 ..< sampleCount:
    for channel in 0 ..< source.channelCount:
      let offset = sampleIndex * source.blockAlign + channel * bytesPerSample
      var sample: int32
      case source.bitsPerSample
      of 8:
        sample = int32(source.sampleData[offset]) - 128
      of 16:
        sample = int32(cast[int16](source.sampleData.le16(offset)))
      of 24:
        sample = int32(source.sampleData[offset]) or
          (int32(source.sampleData[offset + 1]) shl 8) or
          (int32(source.sampleData[offset + 2]) shl 16)
        if (sample and 0x00800000'i32) != 0:
          sample = sample or cast[int32](0xff000000'u32)
      of 32:
        sample = cast[int32](source.sampleData.le32(offset))
      else:
        raise newException(ValueError, "unsupported WAV PCM bit depth")
      result.buffer.channels[channel][sampleIndex] = sample
  result.buffer.validate
