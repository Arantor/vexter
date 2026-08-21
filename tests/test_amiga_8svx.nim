import std/unittest
import vexterlib

proc be16(value: int): seq[byte] =
  @[byte(value shr 8), byte(value)]

proc be32(value: int): seq[byte] =
  @[byte(value shr 24), byte(value shr 16), byte(value shr 8), byte(value)]

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.add be32(payload.len)
  result.add payload
  if (payload.len and 1) != 0: result.add 0

proc svx(body: openArray[byte], oneShot, repeat: int,
    compression = 0, channels = 0): seq[byte] =
  var header: seq[byte]
  header.add be32(oneShot)
  header.add be32(repeat)
  header.add be32(2)
  header.add be16(11025)
  header.add @[1.byte, byte(compression)]
  header.add be32(0x10000)
  var payload = @[byte('8'), byte('S'), byte('V'), byte('X')]
  payload.add chunk("VHDR", header)
  if channels != 0: payload.add chunk("CHAN", be32(channels))
  payload.add chunk("NAME", @[byte('T'), byte('e'), byte('s'), byte('t')])
  payload.add chunk("BODY", body)
  result = @[byte('F'), byte('O'), byte('R'), byte('M')]
  result.add be32(payload.len)
  result.add payload

suite "Amiga IFF 8SVX":
  test "uncompressed mono becomes a sampled instrument":
    let
      data = svx(@[0x80.byte, 0.byte, 0x7f.byte, 0xff.byte], 2, 2)
      candidates = detectFormats("tone.8svx", data)
      inspection = inspectSource("tone.8svx", data)
      node = inspection.resources.leafResources[0]
    check candidates[0].typeId == Amiga8svxTypeId
    check candidates[0].confidence == vdcCertain
    check node.kind == vrnkAudio
    check node.audioKind == varkSampledInstrument
    check node.path == Amiga8svxResourcePath
    check node.instrument.sound.sampleRate == 11025
    check node.audioSound == node.instrument.sound
    check node.instrument.sound.buffer.bitsPerSample == 8
    check node.instrument.sound.buffer.channels == @[@[-128'i32, 0, 127, -1]]
    check node.instrument.oneShotSamples == 2
    check node.instrument.repeatSamples == 2
    check node.instrument.volume == 1.0
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "tone"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].suggestedFilename == "tone.wav"
    check exported.artifacts.artifacts[0].mediaType == "audio/wav"
    check exported.artifacts.artifacts[0].data[0 .. 3] ==
      @[byte('R'), byte('I'), byte('F'), byte('F')]

  test "stereo BODY stores complete left and right channels":
    let instrument = decodeAmiga8svx(parseAmiga8svx(
      svx(@[1.byte, 2, 3, 4], 2, 0, channels = 6)))
    check instrument.sound.buffer.channels == @[@[1'i32, 2], @[3'i32, 4]]

  test "Fibonacci delta expands both nibbles":
    let instrument = decodeAmiga8svx(parseAmiga8svx(
      svx(@[0.byte, 10, 0x89], 2, 0, compression = 1)))
    check instrument.sound.buffer.channels[0] == @[10'i32, 11]

  test "invalid structure and unsupported variants are rejected":
    expect ValueError:
      discard decodeAmiga8svx(parseAmiga8svx(svx(@[1.byte], 2, 0)))
    var data = svx(@[1.byte], 1, 0)
    # VHDR octave byte: FORM header + VHDR framing + 14-byte field offset.
    data[12 + 8 + 14] = 2
    expect ValueError:
      discard parseAmiga8svx(data)
