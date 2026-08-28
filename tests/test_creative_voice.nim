import std/unittest
import vexterlib

proc addLe16(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)

proc addLe32(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 24) and 0xff)

proc addBlock(data: var seq[byte], blockType: int,
    payload: openArray[byte]) =
  data.add byte(blockType)
  data.add byte(payload.len and 0xff)
  data.add byte((payload.len shr 8) and 0xff)
  data.add byte((payload.len shr 16) and 0xff)
  data.add payload

proc voiceHeader(version = 0x010a): seq[byte] =
  for value in "Creative Voice File": result.add byte(value)
  result.add 0x1a
  result.addLe16(26)
  result.addLe16(version)
  result.addLe16(((not version) + 0x1234) and 0xffff)

proc simpleVoice(): seq[byte] =
  result = voiceHeader()
  result.addBlock(0x01, @[131'u8, 0, 0, 128]) # 8000 Hz PCM.
  result.addBlock(0x02, @[255'u8])
  result.addBlock(0x03, @[1'u8, 0, 131]) # Two silent samples.
  result.addBlock(0x04, @[7'u8, 0])
  result.addBlock(0x05, @[byte('o'), byte('k'), 0])
  result.addBlock(0x06, @[1'u8, 0]) # Two total iterations.
  result.addBlock(0x02, @[129'u8])
  result.add 0x07
  result.add 0x00

suite "Creative Voice import":
  test "version-one PCM blocks form one playable and exportable sound":
    let data = simpleVoice()
    let source = parseCreativeVoice(data)
    check source.version == 0x010a
    check source.dataOffset == 26
    check source.sampleRate == 8000
    check source.bitsPerSample == 8
    check source.channelCount == 1
    check source.blocks.len == 9
    check source.blocks[0].blockType == 1
    check source.blocks[0].size == 4
    check source.samples == @[-128'i32, 0, 127, 0, 0, 1, 1]

    let inspection = inspectSource("voice.voc", data)
    check inspection.selectedFormat.typeId == CreativeVoiceTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.resources.roots.len == 1
    let audio = inspection.resources.roots[0]
    check audio.path == CreativeVoiceSoundResourcePath
    check audio.typeId == CreativeVoiceSoundTypeId
    check audio.kind == vrnkAudio
    check audio.sound.sampleRate == 8000
    check audio.sound.buffer.bitsPerSample == 8
    check audio.sound.buffer.channels == @[source.samples]
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "voice"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].suggestedFilename == "voice.wav"
    check decodeWav(parseWav(exported.artifacts.artifacts[0].data)) ==
      audio.sound

  test "header and block framing are validated":
    var badValidation = simpleVoice()
    badValidation[24] = 0
    expect ValueError: discard parseCreativeVoice(badValidation)

    var badOffset = simpleVoice()
    badOffset[20] = 25
    expect ValueError: discard parseCreativeVoice(badOffset)

    var truncated = simpleVoice()
    truncated.setLen(truncated.len - 2)
    expect ValueError: discard parseCreativeVoice(truncated)

    var trailing = simpleVoice()
    trailing.add 1
    expect ValueError: discard parseCreativeVoice(trailing)

  test "extended mono PCM attributes override the following sound block":
    var data = voiceHeader(0x010a)
    data.addBlock(0x08, @[0xa7'u8, 0xd2, 0, 0])
    data.addBlock(0x01, @[0xd3'u8, 3, 0, 128, 255])
    data.add 0x00

    let source = parseCreativeVoice(data)
    check source.usesExtendedInfo
    check source.extendedTimeConstant == 0xd2a7
    check source.packMethod == 0
    check source.voiceMode == 0
    check source.sampleRate == 22_051
    check source.samples == @[-128'i32, 0, 127]

    let inspection = inspectSource("extended.voc", data)
    check inspection.resources.roots[0].sound.sampleRate == 22_051

    var compressed = voiceHeader()
    compressed.addBlock(0x08, @[0xa7'u8, 0xd2, 1, 0])
    compressed.addBlock(0x01, @[0'u8, 0, 128, 0x10])
    compressed.add 0x00
    let extendedAdpcm = parseCreativeVoice(compressed)
    check extendedAdpcm.codec == 1
    check extendedAdpcm.sampleRate == 22_051
    check extendedAdpcm.samples == @[0'i32, 1, 1]

  test "extended stereo PCM uses the channel-aware rate and interleaving":
    var data = voiceHeader()
    data.addBlock(0x08, @[0xa7'u8, 0xd2, 0, 1])
    data.addBlock(0x01, @[0'u8, 3, 0, 255, 128, 64])
    data.add 0x00

    let source = parseCreativeVoice(data)
    check source.sampleRate == 11_025
    check source.bitsPerSample == 8
    check source.channelCount == 2
    check source.channels == @[@[-128'i32, 0], @[127'i32, -64]]
    check decodeCreativeVoice(source).buffer.channels == source.channels

  test "Creative eight-bit ADPCM codecs decode and continue their state":
    var fourBit = voiceHeader()
    fourBit.addBlock(0x01, @[131'u8, 1, 128, 0x17])
    fourBit.addBlock(0x02, @[0x80'u8])
    fourBit.add 0x00
    let decodedFourBit = parseCreativeVoice(fourBit)
    check decodedFourBit.codec == 1
    check decodedFourBit.samples == @[0'i32, 1, 8, 8, 8]

    var twoPointSixBit = voiceHeader()
    twoPointSixBit.addBlock(0x01, @[131'u8, 2, 100, 0x3e])
    twoPointSixBit.add 0x00
    check parseCreativeVoice(twoPointSixBit).samples ==
      @[-28'i32, -27, -30, -30]

    var twoBit = voiceHeader()
    twoBit.addBlock(0x01, @[131'u8, 3, 128, 0x57])
    twoBit.add 0x00
    check parseCreativeVoice(twoBit).samples == @[0'i32, 4, 12, 28, -4]

  test "compressed repeat replay advances decoder state":
    var data = voiceHeader()
    data.addBlock(0x01, @[131'u8, 1, 128])
    data.addBlock(0x06, @[1'u8, 0])
    data.addBlock(0x02, @[0x10'u8])
    data.add 0x07
    data.add 0x00
    check parseCreativeVoice(data).samples == @[0'i32, 1, 1, 2, 2]

  test "new-format blocks decode eight- and sixteen-bit PCM":
    var pcm8Payload: seq[byte]
    pcm8Payload.addLe32(11_025)
    pcm8Payload.add @[8'u8, 2, 0, 0]
    pcm8Payload.add @[0'u8, 0, 0, 0]
    pcm8Payload.add @[0'u8, 255, 128, 64]
    var pcm8 = voiceHeader(0x0114)
    pcm8.addBlock(0x09, pcm8Payload)
    pcm8.add 0x00
    let decoded8 = parseCreativeVoice(pcm8)
    check decoded8.sampleRate == 11_025
    check decoded8.bitsPerSample == 8
    check decoded8.channels == @[@[-128'i32, 0], @[127'i32, -64]]

    var pcm16Payload: seq[byte]
    pcm16Payload.addLe32(22_050)
    pcm16Payload.add @[16'u8, 1, 4, 0]
    pcm16Payload.add @[0'u8, 0, 0, 0]
    pcm16Payload.add @[0'u8, 0x80, 0xff, 0x7f, 0, 0]
    var pcm16 = voiceHeader(0x0114)
    pcm16.addBlock(0x09, pcm16Payload)
    pcm16.add 0x00
    let decoded16 = parseCreativeVoice(pcm16)
    check decoded16.bitsPerSample == 16
    check decoded16.channelCount == 1
    check decoded16.samples == @[-32_768'i32, 32_767, 0]
    check decodeCreativeVoice(decoded16).buffer.bitsPerSample == 16
    let inspection = inspectSource("new-format.voc", pcm16)
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "new-format"))
    check decodeWav(parseWav(exported.artifacts.artifacts[0].data)) ==
      inspection.resources.roots[0].sound

  test "unsupported or unrepresentable streams fail explicitly":
    var compressed = voiceHeader()
    compressed.addBlock(0x01, @[131'u8, 5, 0])
    expect ValueError: discard parseCreativeVoice(compressed)

    var extendedCodec = voiceHeader()
    extendedCodec.addBlock(0x08, @[0xa7'u8, 0xd2, 5, 0])
    expect ValueError: discard parseCreativeVoice(extendedCodec)

    var extendedChannels = voiceHeader()
    extendedChannels.addBlock(0x08, @[0xa7'u8, 0xd2, 0, 2])
    expect ValueError: discard parseCreativeVoice(extendedChannels)

    var orphanedExtension = voiceHeader()
    orphanedExtension.addBlock(0x08, @[0xa7'u8, 0xd2, 0, 0])
    orphanedExtension.add 0x00
    expect ValueError: discard parseCreativeVoice(orphanedExtension)

    var badNewFormat = voiceHeader(0x0114)
    badNewFormat.addBlock(0x09,
      @[0x22'u8, 0x56, 0, 0, 8, 1, 6, 0, 0, 0, 0, 0, 128])
    expect ValueError: discard parseCreativeVoice(badNewFormat)

    var partialFrame = voiceHeader(0x0114)
    partialFrame.addBlock(0x09,
      @[0x22'u8, 0x56, 0, 0, 16, 2, 4, 0, 0, 0, 0, 0, 0])
    expect ValueError: discard parseCreativeVoice(partialFrame)

    var infinite = voiceHeader()
    infinite.addBlock(0x01, @[131'u8, 0, 128])
    infinite.addBlock(0x06, @[255'u8, 255])
    expect ValueError: discard parseCreativeVoice(infinite)

    var changedRate = voiceHeader()
    changedRate.addBlock(0x01, @[131'u8, 0, 128])
    changedRate.addBlock(0x03, @[0'u8, 0, 156]) # 10,000 Hz.
    expect ValueError: discard parseCreativeVoice(changedRate)
