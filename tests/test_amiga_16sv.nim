import std/unittest
import vexterlib

const FixturePath = "16sv_datatype/Bluebird.16sv"

proc be16(value: int): seq[byte] =
  @[byte(value shr 8), byte(value)]

proc be32(value: int): seq[byte] =
  @[byte(value shr 24), byte(value shr 16), byte(value shr 8), byte(value)]

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.add be32(payload.len)
  result.add payload
  if (payload.len and 1) != 0: result.add 0

proc synthetic16sv(body: openArray[byte], samples, compression: int,
    channels = 0): seq[byte] =
  var header: seq[byte]
  header.add be32(samples)
  header.add be32(0)
  header.add be32(0)
  header.add be16(22050)
  header.add @[1.byte, byte(compression)]
  header.add be32(0x10000)
  var payload = @[byte('1'), byte('6'), byte('S'), byte('V')]
  payload.add chunk("VHDR", header)
  if channels != 0: payload.add chunk("CHAN", be32(channels))
  payload.add chunk("BODY", body)
  result = @[byte('F'), byte('O'), byte('R'), byte('M')]
  result.add be32(payload.len)
  result.add payload

suite "Amiga IFF 16SV":
  test "supplied reference fixture decodes as signed big-endian PCM":
    let
      data = cast[seq[byte]](readFile(FixturePath))
      candidates = detectFormats("Bluebird.16sv", data)
      inspection = inspectSource("Bluebird.16sv", data)
      node = inspection.resources.leafResources[0]
    check data.len == 48070
    check candidates[0].typeId == Amiga16svTypeId
    check candidates[0].confidence == vdcCertain
    check node.kind == vrnkAudio
    check node.typeId == Amiga16svResourceTypeId
    check node.instrument.sound.sampleRate == 16384
    check node.instrument.sound.buffer.bitsPerSample == 16
    check node.instrument.sound.buffer.sampleCount == 23982
    check node.instrument.sound.buffer.channels[0][0 .. 3] ==
      @[-256'i32, 0, -256, -256]
    check node.instrument.oneShotSamples == 23982
    check node.instrument.volume == 1.0

    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "Bluebird"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].data[44 .. 51] ==
      @[0'u8, 255, 0, 0, 0, 255, 0, 255]

  test "channel-major stereo is retained as two channels":
    let instrument = decodeAmiga16sv(parseAmiga16sv(synthetic16sv(
      @[0x80'u8, 0, 0x7f, 0xff, 0, 1, 0xff, 0xff], 2, 0, channels = 6)))
    check instrument.sound.buffer.channels ==
      @[@[-32768'i32, 32767], @[1'i32, -1]]

  test "compression, partial words, and excessive regions are rejected":
    expect ValueError:
      discard parseAmiga16sv(synthetic16sv(@[0'u8, 0], 1, 1))
    expect ValueError:
      discard decodeAmiga16sv(parseAmiga16sv(
        synthetic16sv(@[0'u8, 0, 0], 1, 0)))
    expect ValueError:
      discard decodeAmiga16sv(parseAmiga16sv(
        synthetic16sv(@[0'u8, 0], 2, 0)))
