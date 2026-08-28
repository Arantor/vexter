import std/unittest
import vexterlib

proc le16(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16) or (int(data[offset + 3]) shl 24)

proc addLe16(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc addLe32(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)
  data.add byte(value shr 16)
  data.add byte(value shr 24)

proc addChunk(data: var seq[byte], kind: string, payload: openArray[byte]) =
  for value in kind: data.add byte(value)
  data.addLe32(payload.len)
  data.add payload
  if (payload.len and 1) != 0: data.add 0

proc pcmWav(bits, channels, sampleRate: int, samples: openArray[byte],
    dataFirst = false, addUnknown = false): seq[byte] =
  var format: seq[byte]
  format.addLe16(1)
  format.addLe16(channels)
  format.addLe32(sampleRate)
  let align = channels * (bits div 8)
  format.addLe32(sampleRate * align)
  format.addLe16(align)
  format.addLe16(bits)
  for value in "RIFF": result.add byte(value)
  result.addLe32(0)
  for value in "WAVE": result.add byte(value)
  if addUnknown: result.addChunk("JUNK", @[1'u8, 2, 3])
  if dataFirst: result.addChunk("data", samples)
  result.addChunk("fmt ", format)
  if not dataFirst: result.addChunk("data", samples)
  let riffSize = result.len - 8
  for index in 0 ..< 4:
    result[4 + index] = byte(riffSize shr (index * 8))

suite "WAV import and export":
  test "PCM WAV inspection exposes a plain sound":
    let bytes = pcmWav(16, 2, 8000,
      @[0'u8, 128, 0, 0, 255, 127, 255, 255])
    let inspection = inspectSource("stereo.wav", bytes)
    check inspection.selectedFormat.typeId == WavTypeId
    check inspection.resources.roots.len == 1
    let node = inspection.resources.roots[0]
    check node.path == WavSoundResourcePath
    check node.typeId == WavSoundTypeId
    check node.kind == vrnkAudio
    check node.audioKind == varkSound
    check node.sound.sampleRate == 8000
    check node.sound.buffer.bitsPerSample == 16
    check node.sound.buffer.channels == @[
      @[-32768'i32, 32767], @[0'i32, -1]]
    check node.exportFormatsFor[0].id == "wav"
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "stereo"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].suggestedFilename == "stereo.wav"
    check decodeWav(parseWav(exported.artifacts.artifacts[0].data)) == node.sound

  test "all supported integer PCM widths decode with signed semantics":
    check decodeWav(parseWav(pcmWav(8, 1, 11025,
      @[0'u8, 128, 255]))).buffer.channels == @[@[-128'i32, 0, 127]]
    check decodeWav(parseWav(pcmWav(24, 1, 11025,
      @[0'u8, 0, 128, 255, 255, 127]))).buffer.channels ==
        @[@[-8388608'i32, 8388607]]
    check decodeWav(parseWav(pcmWav(32, 1, 11025,
      @[0'u8, 0, 0, 128, 255, 255, 255, 127]))).buffer.channels ==
        @[@[low(int32), high(int32)]]

  test "chunk order, unknown chunks, and odd padding are retained":
    let source = parseWav(pcmWav(8, 1, 4000, @[128'u8],
      dataFirst = true, addUnknown = true))
    check source.chunks.len == 3
    check source.chunks[0].kind == "JUNK"
    check source.chunks[0].data == @[1'u8, 2, 3]
    check source.chunks[1].kind == "data"
    check source.chunks[2].kind == "fmt "
    check decodeWav(source).buffer.channels == @[@[0'i32]]

  test "malformed and unsupported WAV structures are rejected":
    var badSize = pcmWav(8, 1, 8000, @[128'u8])
    badSize[4] = 0
    expect ValueError: discard parseWav(badSize)

    var badEncoding = pcmWav(16, 1, 8000, @[0'u8, 0])
    badEncoding[20] = 3
    expect ValueError: discard parseWav(badEncoding)

    let partialFrame = pcmWav(16, 1, 8000, @[0'u8])
    expect ValueError: discard parseWav(partialFrame)

  test "eight-bit stereo PCM is interleaved and biased to unsigned":
    let artifact = exportWav(VextSound(
      buffer: VextAudioBuffer(bitsPerSample: 8,
        channels: @[@[-128'i32, 127], @[0'i32, -1]]),
      sampleRate: 11025), "stereo.wav").artifacts[0]
    check artifact.suggestedFilename == "stereo.wav"
    check artifact.mediaType == "audio/wav"
    check artifact.data[0 .. 3] == @[byte('R'), byte('I'), byte('F'), byte('F')]
    check artifact.data[8 .. 11] == @[byte('W'), byte('A'), byte('V'), byte('E')]
    check le16(artifact.data, 20) == 1
    check le16(artifact.data, 22) == 2
    check le32(artifact.data, 24) == 11025
    check le32(artifact.data, 28) == 22050
    check le16(artifact.data, 32) == 2
    check le16(artifact.data, 34) == 8
    check le32(artifact.data, 40) == 4
    check artifact.data[44 .. 47] == @[0'u8, 128, 255, 127]

  test "sixteen-bit PCM is little-endian":
    let data = exportWav(VextSound(
      buffer: VextAudioBuffer(bitsPerSample: 16,
        channels: @[@[-32768'i32, 0, 32767]]),
      sampleRate: 8000)).artifacts[0].data
    check data[44 .. 49] == @[0'u8, 128, 0, 0, 255, 127]

  test "odd eight-bit data receives RIFF padding outside the chunk size":
    let data = exportWav(VextSound(
      buffer: VextAudioBuffer(bitsPerSample: 8,
        channels: @[@[-128'i32, 0, 127]]),
      sampleRate: 8000)).artifacts[0].data
    check le32(data, 4) == 40
    check le32(data, 40) == 3
    check data[44 .. 47] == @[0'u8, 128, 255, 0]
    check decodeWav(parseWav(data)).buffer.channels ==
      @[@[-128'i32, 0, 127]]

  test "invalid buffers and out-of-range samples are rejected":
    expect ValueError:
      discard exportWav(VextSound(buffer: VextAudioBuffer(
        bitsPerSample: 12, channels: @[@[0'i32]]), sampleRate: 8000))
    expect ValueError:
      discard exportWav(VextSound(buffer: VextAudioBuffer(
        bitsPerSample: 8, channels: @[@[128'i32]]), sampleRate: 8000))
