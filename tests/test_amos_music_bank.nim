import std/[json, sequtils, strutils, unittest]
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

proc addDword(data: var seq[byte], value: int) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc setDword(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc addFixedText(data: var seq[byte], value: string, length: int) =
  for index in 0 ..< length:
    data.add byte(if index < value.len: value[index] else: ' ')

proc syntheticMusicPayload(): seq[byte] =
  result = newSeq[byte](16)
  let instrumentsOffset = result.len
  result.addWord(1)
  result.addDword(34) # Sample starts after one 32-byte header.
  result.addDword(34) # Non-looping repeat pointer is ignored.
  result.addWord(1)
  result.addWord(2)
  result.addWord(64)
  result.addWord(2)
  result.addFixedText("SYNTH SAMPLE", 16)
  result.add @[0x80'u8, 0x40, 0xc0, 0]

  let songsOffset = result.len
  result.addWord(1)
  result.addDword(6)
  for playlistOffset in [28, 34, 40, 46]: result.addWord(playlistOffset)
  result.addWord(17)
  result.addWord(0)
  result.addFixedText("SYNTH SONG", 16)
  for channel in 0 ..< AmosMusicChannelCount:
    result.addWord(0)
    result.addWord(0)
    result.addWord(0xfffe)

  let patternsOffset = result.len
  result.addWord(1)
  for streamOffset in [10, 18, 26, 34]: result.addWord(streamOffset)
  for channel in 0 ..< AmosMusicChannelCount:
    result.addWord(0x8900)
    result.addWord(0x7f01)
    result.addWord(428)
    result.addWord(0x8000)

  result.setDword(0, instrumentsOffset)
  result.setDword(4, songsOffset)
  result.setDword(8, patternsOffset)

proc syntheticMusicBank(): seq[byte] =
  let payload = syntheticMusicPayload()
  for value in AmosBankMagic: result.add byte(value)
  result.addWord(3)
  result.addWord(0)
  result.addDword(payload.len + AmosBankStoredLengthOverhead)
  result.addFixedText("Music", 8)
  result.add payload

proc bytesString(data: openArray[byte]): string =
  for value in data: result.add char(value)

suite "AMOS music banks":
  test "sections, independent playlists, samples, and commands parse":
    let music = parseAmosMusicBank(syntheticMusicPayload())
    check music.instruments.len == 1
    check music.songs.len == 1
    check music.patterns.len == 1
    check music.songs[0].name == "SYNTH SONG"
    check music.songs[0].defaultTempo == 17
    for playlist in music.songs[0].playlists:
      check playlist == @[0, 0]
    check music.instruments[0].sample.sound.buffer.channels[0] ==
      @[-128'i32, 64, -64, 0]
    check music.instruments[0].sample.repeatSamples == 0

  test "Music banks expose songs, shared samples, and playable audio":
    let inspection = inspectSource("music.abk", syntheticMusicBank())
    check inspection.selectedFormat.typeId == AmosBankTypeId
    let resource = inspection.resources.roots[0]
    check resource.typeId == AmosMusicTypeId
    check resource.kind == vrnkOpaque
    check resource.rawDataAvailable
    check resource.children[0].path == "/bank/songs"
    let song = resource.children[0].children[0]
    check song.path == "/bank/songs/1"
    check song.kind == vrnkTracker
    check song.tracker.channels.len == 4
    check song.tracker.instruments.len == 1
    check song.tracker.orders == @[0, 1]
    let firstCell = song.tracker.patterns[0].rows[0].cells[0]
    check firstCell.sourcePitch == 428
    check firstCell.effects[0].rawCommand == 0x7f
    check firstCell.effects[0].rawParameter == 1
    check song.children[0].path == "/bank/songs/1/patterns"
    check song.children[0].children.len == 2
    check song.children[0].children[0].path ==
      "/bank/songs/1/patterns/0"
    check song.children[0].children[0].kind == vrnkTracker
    check song.children[0].children[1].path ==
      "/bank/songs/1/patterns/1"
    check song.children[1].path == "/bank/songs/1/rendered-audio"
    let sound = song.children[1].audioSound
    check sound.buffer.channels.len == 2
    check sound.buffer.channels[0].anyIt(it != 0)
    check sound.buffer.channels[1].anyIt(it != 0)
    # A delay of one advances on the very next AMOS position; it must not add
    # an extra position before the end command is fetched.
    let replay = renderAmosMusic(parseAmosMusicBank(syntheticMusicPayload()),
      0, maximumSeconds = 1)
    check replay.verticalBlanksRendered < 16
    check not replay.reachedSafetyLimit
    check resource.children[1].path == "/bank/samples"
    check resource.children[1].children[0].path == "/bank/samples/1"

    let mix = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/bank/songs/1/rendered-audio", outputFormat: "wav",
      suggestedName: "song"))
    check mix.artifacts.artifacts[0].data.bytesString.startsWith("RIFF")
    let roundTrip = decodeWav(parseWav(mix.artifacts.artifacts[0].data))
    check roundTrip.buffer.channels.len == 2
    check roundTrip.buffer.channels[1].anyIt(it != 0)
    let tracker = exportResource(inspection.resources, VextExportRequest(
      resourcePath: "/bank/songs/1", outputFormat: "tracker-json",
      suggestedName: "song"))
    check parseJson(tracker.artifacts.artifacts[0].data.bytesString)[
      "schema"].getStr == "vexter.tracker.v1"

  test "invalid offsets and unterminated streams are rejected":
    var badOffset = syntheticMusicPayload()
    badOffset.setDword(8, badOffset.len)
    check not isAmosMusicBank(badOffset)
    var unterminated = syntheticMusicPayload()
    unterminated[^2] = 0
    unterminated[^1] = 0
    check not isAmosMusicBank(unterminated)
