## Parsing for the payload of an AMOS `Music` bank.

import std/[algorithm, strutils]
import ../archetypes/audio

const
  AmosMusicTypeId* = "amos.music"
  AmosMusicSongTypeId* = "amos.music-song"
  AmosMusicPatternsTypeId* = "amos.music-patterns"
  AmosMusicPatternTypeId* = "amos.music-pattern"
  AmosMusicSampleTypeId* = "amos.music-sample"
  AmosMusicRenderedAudioTypeId* = "amos.music-rendered-audio"
  AmosMusicChannelCount* = 4
  AmosMusicReferenceSampleRate* = 8287

type
  AmosMusicInstrument* = object
    name*: string
    sampleOffset*, repeatOffset*: int
    repeatStart*, repeatLength*: int
    declaredLength*, volume*: int
    sample*: VextSampledInstrument

  AmosMusicSong* = object
    name*: string
    defaultTempo*: int
    playlists*: array[AmosMusicChannelCount, seq[int]]

  AmosMusicPattern* = object
    streamOffsets*: array[AmosMusicChannelCount, int]

  AmosMusicBank* = object
    instrumentsOffset*, songsOffset*, patternsOffset*: int
    instruments*: seq[AmosMusicInstrument]
    songs*: seq[AmosMusicSong]
    patterns*: seq[AmosMusicPattern]
    data*: seq[byte]

proc beWord(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 2:
    raise newException(ValueError, "truncated AMOS music word")
  int(data[offset]) shl 8 or int(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 4:
    raise newException(ValueError, "truncated AMOS music dword")
  let value = (uint32(data[offset]) shl 24) or
    (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])
  if value > uint32(high(int)):
    raise newException(ValueError, "AMOS music offset is outside host range")
  int(value)

proc fixedText(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "truncated AMOS music text")
  for index in 0 ..< length:
    let value = data[offset + index]
    if value == 0: break
    result.add if value in 32'u8 .. 126'u8: char(value) else: '?'
  result = result.strip

proc sectionEnd(bank: AmosMusicBank, start: int): int =
  result = bank.data.len
  for candidate in [bank.instrumentsOffset, bank.songsOffset,
      bank.patternsOffset]:
    if candidate > start: result = min(result, candidate)

proc parsePlaylist(data: openArray[byte], offset, limit: int): seq[int] =
  var cursor = offset
  while cursor <= limit - 2:
    let value = data.beWord(cursor)
    cursor += 2
    if value in [0xfffe, 0xffff]: return
    result.add value
  raise newException(ValueError, "unterminated AMOS music playlist")

proc validatePatternStream(data: openArray[byte], offset, limit: int) =
  var cursor = offset
  while cursor <= limit - 2:
    let value = data.beWord(cursor)
    cursor += 2
    if value shr 8 == 0x80: return
    if (value and 0x8000) != 0 and value shr 8 > 0x91:
      raise newException(ValueError, "unknown AMOS music pattern command")
  raise newException(ValueError, "unterminated AMOS music pattern")

proc parseAmosMusicBank*(data: openArray[byte]): AmosMusicBank =
  if data.len < 16:
    raise newException(ValueError, "truncated AMOS music header")
  result.data = @data
  result.instrumentsOffset = data.beDword(0)
  result.songsOffset = data.beDword(4)
  result.patternsOffset = data.beDword(8)
  if data.beDword(12) != 0:
    raise newException(ValueError, "invalid AMOS music reserved header value")
  for offset in [result.instrumentsOffset, result.songsOffset,
      result.patternsOffset]:
    if offset < 16 or offset > data.len - 2:
      raise newException(ValueError, "AMOS music section offset is outside data")

  let instrumentCount = data.beWord(result.instrumentsOffset)
  if instrumentCount > (result.sectionEnd(result.instrumentsOffset) - 2) div 32:
    raise newException(ValueError, "truncated AMOS music instrument table")
  type Header = object
    sampleOffset, repeatOffset, repeatStart, repeatLength,
      volume, declaredLength: int
    name: string
  var headers: seq[Header]
  for index in 0 ..< instrumentCount:
    let offset = result.instrumentsOffset + 2 + index * 32
    headers.add Header(
      sampleOffset: data.beDword(offset), repeatOffset: data.beDword(offset + 4),
      repeatStart: data.beWord(offset + 8) * 4,
      repeatLength: data.beWord(offset + 10) * 2,
      volume: data.beWord(offset + 12) and 0xff,
      declaredLength: data.beWord(offset + 14) * 2,
      name: data.fixedText(offset + 16, 16))
  var sampleOffsets: seq[int]
  for header in headers: sampleOffsets.add header.sampleOffset
  sampleOffsets.sort
  let instrumentsEnd = result.sectionEnd(result.instrumentsOffset)
  for index, header in headers:
    if header.volume > 64 or header.sampleOffset < 2 + instrumentCount * 32 or
        header.sampleOffset >= instrumentsEnd - result.instrumentsOffset:
      raise newException(ValueError, "invalid AMOS music instrument")
    var sampleEnd = instrumentsEnd - result.instrumentsOffset
    for candidate in sampleOffsets:
      if candidate > header.sampleOffset:
        sampleEnd = candidate
        break
    let sampleLength = sampleEnd - header.sampleOffset
    var samples = newSeq[VextAudioSample](sampleLength)
    for sampleIndex in 0 ..< sampleLength:
      samples[sampleIndex] = int32(cast[int8](
        data[result.instrumentsOffset + header.sampleOffset + sampleIndex]))
    let relativeRepeat = header.repeatOffset - header.sampleOffset
    let hasLoop = header.repeatLength > 4 and relativeRepeat >= 0 and
      relativeRepeat < sampleLength
    if hasLoop and header.repeatLength > sampleLength - relativeRepeat:
      raise newException(ValueError, "AMOS music sample loop exceeds its data")
    result.instruments.add AmosMusicInstrument(name: header.name,
      sampleOffset: header.sampleOffset, repeatOffset: header.repeatOffset,
      repeatStart: header.repeatStart, repeatLength: header.repeatLength,
      declaredLength: header.declaredLength, volume: header.volume,
      sample: VextSampledInstrument(
        sound: VextSound(sampleRate: AmosMusicReferenceSampleRate,
          buffer: VextAudioBuffer(bitsPerSample: 8, channels: @[samples])),
        oneShotSamples: if hasLoop: relativeRepeat else: sampleLength,
        repeatSamples: if hasLoop: header.repeatLength else: 0,
        samplesPerHighCycle: 0, volume: float64(header.volume) / 64.0,
        pan: 0.0))

  let songEnd = result.sectionEnd(result.songsOffset)
  let songCount = data.beWord(result.songsOffset)
  if songCount > (songEnd - result.songsOffset - 2) div 4:
    raise newException(ValueError, "truncated AMOS music song table")
  var songStarts: seq[int]
  for index in 0 ..< songCount:
    let relativeOffset = data.beDword(result.songsOffset + 2 + index * 4)
    let offset = result.songsOffset + relativeOffset
    if relativeOffset < 2 + songCount * 4 or offset > songEnd - 28:
      raise newException(ValueError, "invalid AMOS music song offset")
    songStarts.add offset
  for index, offset in songStarts:
    var thisSongEnd = songEnd
    for candidate in songStarts:
      if candidate > offset: thisSongEnd = min(thisSongEnd, candidate)
    # Shipped AMOS banks place the four playlist offsets at 0..7 and the
    # default tempo at 8, despite the saved reference table listing tempo first.
    var song = AmosMusicSong(defaultTempo: data.beWord(offset + 8),
      name: data.fixedText(offset + 12, 16))
    if song.defaultTempo notin 1 .. 100 or data.beWord(offset + 10) != 0:
      raise newException(ValueError, "invalid AMOS music song header")
    var playlistStarts: array[AmosMusicChannelCount, int]
    for channel in 0 ..< AmosMusicChannelCount:
      let playlistOffset = data.beWord(offset + channel * 2)
      if playlistOffset < 28 or offset + playlistOffset >= thisSongEnd:
        raise newException(ValueError, "invalid AMOS music playlist offset " &
          $playlistOffset & " for channel " & $channel)
      playlistStarts[channel] = offset + playlistOffset
    for channel in 0 ..< AmosMusicChannelCount:
      var playlistEnd = thisSongEnd
      for candidate in playlistStarts:
        if candidate > playlistStarts[channel]:
          playlistEnd = min(playlistEnd, candidate)
      song.playlists[channel] = data.parsePlaylist(
        playlistStarts[channel], playlistEnd)
    result.songs.add song

  let patternEnd = result.sectionEnd(result.patternsOffset)
  let patternCount = data.beWord(result.patternsOffset)
  if patternCount > (patternEnd - result.patternsOffset - 2) div 8:
    raise newException(ValueError, "truncated AMOS music pattern table")
  var streamStarts: seq[int]
  for patternIndex in 0 ..< patternCount:
    var pattern: AmosMusicPattern
    for channel in 0 ..< AmosMusicChannelCount:
      let relativeOffset = data.beWord(
        result.patternsOffset + 2 + patternIndex * 8 + channel * 2)
      let offset = result.patternsOffset + relativeOffset
      if relativeOffset < 2 + patternCount * 8 or offset >= patternEnd:
        raise newException(ValueError, "invalid AMOS music pattern offset")
      pattern.streamOffsets[channel] = offset
      streamStarts.add offset
    result.patterns.add pattern
  for offset in streamStarts:
    var streamEnd = patternEnd
    for candidate in streamStarts:
      if candidate > offset: streamEnd = min(streamEnd, candidate)
    data.validatePatternStream(offset, streamEnd)
  for song in result.songs:
    for playlist in song.playlists:
      for patternIndex in playlist:
        if patternIndex >= result.patterns.len:
          raise newException(ValueError,
            "AMOS music playlist references a missing pattern")

proc isAmosMusicBank*(data: openArray[byte]): bool =
  try:
    discard parseAmosMusicBank(data)
    true
  except ValueError:
    false
