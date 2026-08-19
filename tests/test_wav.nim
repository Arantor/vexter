import std/unittest
import vexterlib

proc le16(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16) or (int(data[offset + 3]) shl 24)

suite "WAV export":
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

  test "invalid buffers and out-of-range samples are rejected":
    expect ValueError:
      discard exportWav(VextSound(buffer: VextAudioBuffer(
        bitsPerSample: 12, channels: @[@[0'i32]]), sampleRate: 8000))
    expect ValueError:
      discard exportWav(VextSound(buffer: VextAudioBuffer(
        bitsPerSample: 8, channels: @[@[128'i32]]), sampleRate: 8000))
