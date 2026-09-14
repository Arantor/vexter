## Sierra SCI0/SCI1/SCI1.1 directory-backed resource packages.
## Format facts are derived from supplied SCI Specifications chapters 1-3.

import std/[strutils, tables]
import ../archetypes/raster
import ../byte_sources
import ../metadata
import ../resource_tree
import ../resources/sierra_sci_graphics
import ../resources/sierra_sci_picture
import ../resources/sierra_sci_sound
import ../resources/sierra_sci_vocabulary

const SierraSciGameTypeId* = "sierra.sci-game"

type
  SciResourceMapVersion* = enum srmvSci0, srmvSci1, srmvSci11
  SciResourceKind* = enum
    srkView, srkPicture, srkScript, srkText, srkSound, srkMemory,
    srkVocabulary, srkFont, srkCursor, srkPatch, srkBitmap, srkPalette,
    srkCdAudio, srkAudio, srkSync, srkMessage, srkMap, srkHeap, srkUnknown
  SciResourceEntry* = object
    kind*: SciResourceKind
    typeNumber*, number*, volume*, offset*: int
    compressedSize*, decompressedSize*, compressionMethod*: int
    valid*: bool
    warning*: string
  SciGame* = object
    version*: SciResourceMapVersion
    root*, mapPath*: string
    entries*: seq[SciResourceEntry]

const ResourceKindNames* = ["views", "pictures", "scripts", "texts", "sounds",
  "memory", "vocabularies", "fonts", "cursors", "patches", "bitmaps",
  "palettes", "cd-audio", "audio", "sync", "messages", "maps", "heaps",
  "unknown"]

proc dirname(path: string): string =
  let at = path.rfind('/')
  if at < 0: "" else: path[0 ..< at]

proc basename(path: string): string =
  let at = path.rfind('/')
  if at < 0: path else: path[at + 1 .. ^1]

proc joined(root, name: string): string =
  if root.len == 0: name else: root & "/" & name

proc uniquePath(sources: VextSourceCollection, path: string): string =
  for item in sources.relatedSources:
    if item.relativePath.cmpIgnoreCase(path) == 0:
      if result.len > 0: return ""
      result = item.relativePath

proc readRelated(sources: VextSourceCollection, path: string): seq[byte] =
  let source = sources.related(path)
  if source.isNil: raise newException(ValueError, "missing SCI member: " & path)
  defer: source.close()
  source.readAll()

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2: raise newException(ValueError, "truncated SCI word")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc le32(data: openArray[byte], at: int): uint32 =
  if at < 0 or at > data.len - 4: raise newException(ValueError, "truncated SCI dword")
  uint32(data[at]) or (uint32(data[at + 1]) shl 8) or
    (uint32(data[at + 2]) shl 16) or (uint32(data[at + 3]) shl 24)

proc le24(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 3:
    raise newException(ValueError, "truncated SCI 24-bit value")
  int(data[at]) or (int(data[at + 1]) shl 8) or (int(data[at + 2]) shl 16)

proc resourceKind(value: int): SciResourceKind =
  if value in 0 .. 17: SciResourceKind(value) else: srkUnknown

proc parseSci0Map(data: openArray[byte]): seq[SciResourceEntry] =
  if data.len < 6 or data.len mod 6 != 0:
    raise newException(ValueError, "invalid SCI0 resource map length")
  var at = 0
  while at < data.len:
    let id = le16(data, at)
    let location = le32(data, at + 2)
    if id == 0xffff and location == 0xffffffff'u32:
      if at + 6 != data.len:
        raise newException(ValueError, "SCI0 resource map has data after its terminator")
      return
    let typeNumber = id shr 11
    if typeNumber > 31:
      raise newException(ValueError, "invalid SCI0 resource type")
    result.add SciResourceEntry(kind: resourceKind(typeNumber),
      typeNumber: typeNumber, number: id and 0x7ff,
      volume: int(location shr 26), offset: int(location and 0x03ffffff'u32))
    at += 6
  raise newException(ValueError, "SCI0 resource map has no terminator")

proc parseSci1Map(data: openArray[byte], version: var SciResourceMapVersion): seq[SciResourceEntry] =
  if data.len < 6: raise newException(ValueError, "truncated SCI1 resource map")
  var types: seq[tuple[number, first: int]]
  var at = 0
  while true:
    if at > data.len - 3: raise newException(ValueError, "unterminated SCI1 type table")
    let typeByte = int(data[at])
    let first = le16(data, at + 1)
    if first < at + 3 or first > data.len:
      raise newException(ValueError, "SCI1 lookup offset is outside the map")
    if typeByte == 0xff:
      types.add (number: -1, first: first)
      break
    if typeByte notin 0x80 .. 0x91 or
        types.len > 0 and typeByte <= types[^1].number + 0x80:
      raise newException(ValueError, "invalid SCI1 resource type table")
    types.add (number: typeByte - 0x80, first: first)
    at += 3
  let directoryEnd = at + 3
  if types.len < 2 or types[0].first < directoryEnd:
    raise newException(ValueError, "SCI1 resource tables overlap the type table")
  var sci1 = true
  var sci11 = true
  for index in 0 ..< types.len - 1:
    let first = types[index].first
    let finish = types[index + 1].first
    if finish < first:
      raise newException(ValueError, "invalid SCI1 resource table bounds")
    sci1 = sci1 and (finish - first) mod 6 == 0
    sci11 = sci11 and (finish - first) mod 5 == 0
  # Prefer SCI1 when both entry widths happen to divide every table length.
  if sci1:
    version = srmvSci1
  elif sci11:
    version = srmvSci11
  else:
    raise newException(ValueError,
      "SCI resource tables have neither SCI1 nor SCI1.1 entry widths")
  let entrySize = if version == srmvSci1: 6 else: 5
  for index in 0 ..< types.len - 1:
    let first = types[index].first
    let finish = types[index + 1].first
    var previous = -1
    var entryAt = first
    while entryAt < finish:
      let number = le16(data, entryAt)
      if number < previous:
        raise newException(ValueError, "SCI1 resource table is not sorted")
      var volume, offset: int
      if version == srmvSci1:
        let location = le32(data, entryAt + 2)
        volume = int(location shr 28)
        offset = int(location and 0x0fffffff'u32)
      else:
        volume = 0
        offset = le24(data, entryAt + 2) * 2
      result.add SciResourceEntry(kind: resourceKind(types[index].number),
        typeNumber: types[index].number, number: number,
        volume: volume, offset: offset)
      previous = number
      entryAt += entrySize
  if types[^1].first != data.len:
    raise newException(ValueError, "SCI1 resource map end offset does not match its length")

proc volumePath(sources: VextSourceCollection, game: SciGame, volume: int): string =
  uniquePath(sources, joined(game.root, "RESOURCE." & align($volume, 3, '0')))

proc inspectEntry(sources: VextSourceCollection, game: SciGame,
    entry: var SciResourceEntry) =
  let path = sources.volumePath(game, entry.volume)
  if path.len == 0:
    entry.warning = "missing or ambiguous resource volume"
    return
  let volume = sources.related(path)
  if volume.isNil:
    entry.warning = "missing or ambiguous resource volume"
    return
  defer: volume.close()
  let headerSize = if game.version == srmvSci0: 8 else: 9
  if entry.offset < 0 or entry.offset > volume.length - headerSize:
    entry.warning = "resource offset is outside volume bounds"
    return
  let header = volume.readAt(entry.offset, headerSize)
  var id, typeNumber, number: int
  if game.version == srmvSci0:
    id = le16(header, 0)
    typeNumber = id shr 11
    number = id and 0x7ff
  else:
    typeNumber = int(header[0]) and 0x7f
    number = le16(header, 1)
  if typeNumber != entry.typeNumber or number != entry.number:
    entry.warning = "volume header identity does not match the resource map"
    return
  let wordsAt = if game.version == srmvSci0: 2 else: 3
  entry.compressedSize = le16(header, wordsAt)
  entry.decompressedSize = le16(header, wordsAt + 2)
  entry.compressionMethod = le16(header, wordsAt + 4)
  # SCI0/early SCI1 include four identity bytes in the stored-size field.
  # In the supplied word-addressed SCI1.1 generation it is the number of
  # payload bytes following the nine-byte header; adjacent map offsets in the
  # authentic corpus independently confirm that framing.
  let payloadSize = if game.version == srmvSci11:
    entry.compressedSize else: entry.compressedSize - 4
  if payloadSize < 0 or entry.decompressedSize < 0 or
      payloadSize > volume.length - entry.offset - headerSize:
    entry.warning = "resource payload extends beyond volume bounds"
    return
  entry.valid = true

proc discoverSciGames*(sources: VextSourceCollection): seq[SciGame] =
  var maps: seq[string]
  for item in sources.relatedSources:
    if item.relativePath.basename.cmpIgnoreCase("RESOURCE.MAP") == 0:
      maps.add item.relativePath
  for mapPath in maps:
    try:
      let data = sources.readRelated(mapPath)
      var game = SciGame(root: mapPath.dirname, mapPath: mapPath)
      if data.len >= 1 and data[0] in 0x80'u8 .. 0x91'u8:
        game.entries = parseSci1Map(data, game.version)
      else:
        game.version = srmvSci0
        game.entries = parseSci0Map(data)
      var valid = 0
      for entry in game.entries.mitems:
        sources.inspectEntry(game, entry)
        if entry.valid: inc valid
      if valid > 0: result.add move(game)
    except CatchableError:
      discard

proc huffmanDecode*(input: openArray[byte], expected: int): seq[byte] =
  if input.len < 2: raise newException(ValueError, "truncated SCI Huffman header")
  let terminator = input[0]
  let count = int(input[1])
  if count == 0 or 2 + count * 2 > input.len:
    raise newException(ValueError, "invalid SCI Huffman node table")
  var bitAt = (2 + count * 2) * 8
  template takeBit(): int =
    block:
      if bitAt >= input.len * 8:
        raise newException(ValueError, "truncated SCI Huffman bits")
      let decoded = (int(input[bitAt div 8]) shr (7 - bitAt mod 8)) and 1
      inc bitAt
      decoded
  var terminated = false
  while not terminated:
    var node = 0
    var literal = false
    var value: byte
    while true:
      if node < 0 or node >= count: raise newException(ValueError, "invalid SCI Huffman node")
      value = input[2 + node * 2]
      let siblings = int(input[3 + node * 2])
      if siblings == 0: break
      if takeBit() == 0:
        let distance = siblings shr 4
        if distance == 0: raise newException(ValueError, "invalid SCI Huffman left branch")
        node += distance
      else:
        let distance = siblings and 0x0f
        if distance == 0:
          value = 0
          for unused in 0 ..< 8: value = byte((int(value) shl 1) or takeBit())
          literal = true
          break
        node += distance
    if literal and value == terminator:
      terminated = true
      break
    result.add value
    if result.len > expected:
      raise newException(ValueError, "SCI Huffman output exceeds its declared length")
  if not terminated or result.len != expected:
    raise newException(ValueError, "SCI Huffman output length mismatch")

proc sciLzwDecode*(input: openArray[byte], expected: int): seq[byte] =
  ## Candidate established from the project's existing adaptive-LZW machinery
  ## and accepted only when the authentic stream reaches its exact declared
  ## output length without an invalid dictionary reference.
  var prefix: array[4096, int]
  var suffix: array[4096, byte]
  var stack: array[4096, byte]
  var bitAt = 0
  var width = 9
  var next = 258
  var previous = -1
  template nextCode(): int =
    block:
      var decoded = -1
      if bitAt + width <= input.len * 8:
        decoded = 0
        for bit in 0 ..< width:
          decoded = decoded or (((int(input[bitAt div 8]) shr
            (bitAt mod 8)) and 1) shl bit)
          inc bitAt
      decoded
  while result.len < expected:
    let value = nextCode()
    if value < 0 or value == 257: break
    if value == 256:
      width = 9; next = 258; previous = -1
      continue
    if value > next or value >= 4096:
      raise newException(ValueError, "invalid SCI LZW dictionary code")
    var current = value
    var top = 0
    if current == next:
      if previous < 0: raise newException(ValueError, "invalid SCI LZW first code")
      current = previous
      while current >= 256:
        if top >= stack.len: raise newException(ValueError, "cyclic SCI LZW dictionary")
        stack[top] = suffix[current]; inc top; current = prefix[current]
      let first = byte(current)
      stack[top] = first; inc top
      for index in countdown(top - 1, 0): result.add stack[index]
      result.add first
      if next < 4096: prefix[next] = previous; suffix[next] = first; inc next
    else:
      while current >= 256:
        if top >= stack.len: raise newException(ValueError, "cyclic SCI LZW dictionary")
        stack[top] = suffix[current]; inc top; current = prefix[current]
      let first = byte(current)
      stack[top] = first; inc top
      for index in countdown(top - 1, 0): result.add stack[index]
      if previous >= 0 and next < 4096:
        prefix[next] = previous; suffix[next] = first; inc next
    if result.len > expected:
      raise newException(ValueError, "SCI LZW output exceeds its declared length")
    previous = value
    if next == (1 shl width) and width < 12: inc width
  if result.len != expected:
    raise newException(ValueError, "SCI LZW output length mismatch")

const
  DclAsciiCodes = [73, 127, 126, 125, 124, 123, 122, 121, 120, 29, 35,
    119, 118, 34, 117, 116, 115, 114, 113, 112, 111, 110, 109, 108, 107,
    106, 73, 105, 104, 103, 102, 101, 15, 41, 28, 100, 40, 99, 39, 27, 33,
    32, 26, 27, 31, 37, 30, 25, 29, 36, 28, 27, 26, 25, 24, 24, 23, 23,
    22, 98, 72, 22, 26, 71, 97, 35, 21, 34, 33, 29, 20, 21, 20, 32, 70,
    25, 31, 19, 30, 29, 18, 69, 28, 27, 26, 17, 24, 19, 23, 22, 68, 18,
    67, 21, 96, 17, 95, 28, 25, 24, 23, 27, 22, 21, 20, 26, 66, 16, 25,
    19, 24, 23, 18, 38, 22, 21, 20, 19, 16, 15, 15, 14, 37, 65, 64, 94,
    93, 92, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63, 62, 61, 60, 59, 58,
    57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41,
    40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 91,
    90, 89, 88, 87, 86, 85, 84, 83, 82, 81, 80, 79, 78, 77, 76, 75, 74,
    73, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63, 62, 61, 60, 59, 58, 57,
    56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 24, 43, 23, 22,
    21, 42, 20, 19, 18, 41, 17, 16, 15, 14, 40, 13, 12, 11, 39, 38, 37,
    10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
  DclAsciiCodeLengths = [11, 12, 12, 12, 12, 12, 12, 12, 12, 8, 7, 12,
    12, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 12, 12,
    12, 12, 12, 4, 10, 8, 12, 10, 12, 10, 8, 7, 7, 8, 9, 7, 6, 7, 8,
    7, 6, 7, 7, 7, 7, 8, 7, 7, 8, 8, 12, 11, 7, 9, 11, 12, 6, 7, 6,
    6, 5, 7, 8, 8, 6, 11, 9, 6, 7, 6, 6, 7, 11, 6, 6, 6, 7, 9, 8, 9,
    9, 11, 8, 11, 9, 12, 8, 12, 5, 6, 6, 6, 5, 6, 6, 6, 5, 11, 7, 5,
    6, 5, 5, 6, 10, 5, 5, 5, 5, 8, 7, 8, 8, 10, 11, 11, 12, 12, 12,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 12, 13, 13,
    13, 12, 13, 13, 13, 12, 13, 13, 13, 13, 12, 13, 13, 13, 12, 12,
    12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13]

proc dclExplodeDecode*(input: openArray[byte], expected: int): seq[byte] =
  ## DCL-EXPLODE as specified in the supplied SCI Specifications chapter 2.
  ## SCI resources in the supplied corpus use binary literals (P1 = 0).
  if input.len < 2:
    raise newException(ValueError, "truncated SCI DCL-EXPLODE parameters")
  let asciiLiterals = input[0] == 1
  if input[0] notin 0'u8 .. 1'u8:
    raise newException(ValueError, "invalid SCI DCL-EXPLODE literal parameter")
  let distanceBits = int(input[1])
  if distanceBits notin 4 .. 6:
    raise newException(ValueError, "invalid SCI DCL-EXPLODE distance parameter")
  if expected < 0:
    raise newException(ValueError, "invalid SCI DCL-EXPLODE output size")

  let encoded = @input
  var bitAt = 16
  proc takeBit(): int =
    if bitAt >= encoded.len * 8:
      raise newException(ValueError, "truncated SCI DCL-EXPLODE bit stream")
    result = (int(encoded[bitAt div 8]) shr (bitAt mod 8)) and 1
    inc bitAt
  proc takeBits(count: int): int =
    for bit in 0 ..< count:
      result = result or (takeBit() shl bit)
  proc asciiLiteral(): byte =
    var code = 0
    for width in 1 .. 13:
      code = (code shl 1) or takeBit()
      for value in 0 .. 255:
        if DclAsciiCodeLengths[value] == width and DclAsciiCodes[value] == code:
          return byte(value)
    raise newException(ValueError, "invalid SCI DCL-EXPLODE ASCII literal code")
  proc lengthToken(): int =
    var code = 0
    for width in 1 .. 7:
      code = (code shl 1) or takeBit()
      case width
      of 2:
        if code == 3: return 1
      of 3:
        if code == 5: return 0
        if code == 4: return 2
        if code == 3: return 3
      of 4:
        if code in 3 .. 5: return 9 - code
      of 5:
        if code in 2 .. 5: return 12 - code
      of 6:
        if code in 1 .. 3: return 14 - code
      of 7:
        if code in 0 .. 1: return 15 - code
      else: discard
    raise newException(ValueError, "invalid SCI DCL-EXPLODE length code")
  proc distanceToken(): int =
    var code = 0
    for width in 1 .. 8:
      code = (code shl 1) or takeBit()
      case width
      of 2:
        if code == 3: return 0
      of 4:
        if code in 10 .. 11: return 12 - code
      of 5:
        if code in 16 .. 19: return 22 - code
      of 6:
        if code in 17 .. 31: return 38 - code
      of 7:
        if code in 8 .. 33: return 55 - code
      of 8:
        if code in 0 .. 15: return 63 - code
      else: discard
    raise newException(ValueError, "invalid SCI DCL-EXPLODE distance code")

  while result.len < expected:
    if takeBit() == 0:
      result.add(if asciiLiterals: asciiLiteral() else: byte(takeBits(8)))
    else:
      let l1 = lengthToken()
      var length = l1 + 2
      if l1 > 7:
        let extra = l1 - 7
        # M[0] = 7; M[n+1] = M[n] + 2^n.
        let base = 6 + (1 shl extra)
        length = takeBits(extra) + base + 2
      let d1 = distanceToken()
      let lowBits = if length == 2: 2 else: distanceBits
      let distance = (d1 shl lowBits or takeBits(lowBits)) + 1
      if distance > result.len:
        raise newException(ValueError,
          "SCI DCL-EXPLODE distance precedes the output")
      if length > expected - result.len:
        raise newException(ValueError,
          "SCI DCL-EXPLODE output exceeds its declared length")
      for unused in 0 ..< length:
        result.add result[result.len - distance]
  if result.len != expected:
    raise newException(ValueError, "SCI DCL-EXPLODE output length mismatch")

proc payloadSize(game: SciGame, entry: SciResourceEntry): int =
  if game.version == srmvSci11: entry.compressedSize
  else: entry.compressedSize - 4

proc resourceBytes*(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): seq[byte] =
  if not entry.valid: raise newException(ValueError, entry.warning)
  let volume = sources.related(sources.volumePath(game, entry.volume))
  if volume.isNil: raise newException(ValueError, "SCI resource volume is unavailable")
  defer: volume.close()
  let headerSize = if game.version == srmvSci0: 8 else: 9
  let stored = volume.readAt(entry.offset + headerSize, game.payloadSize(entry))
  if entry.compressionMethod == 0:
    if stored.len != entry.decompressedSize:
      raise newException(ValueError, "uncompressed SCI resource sizes disagree")
    return @stored
  if entry.compressionMethod == 1:
    return sciLzwDecode(stored, entry.decompressedSize)
  if game.version == srmvSci0 and entry.compressionMethod == 2:
    return huffmanDecode(stored, entry.decompressedSize)
  if entry.compressionMethod in 18 .. 20:
    return dclExplodeDecode(stored, entry.decompressedSize)
  raise newException(ValueError, "SCI compression method " & $entry.compressionMethod &
    " is not documented sufficiently for decoding")

proc storedResourceBytes(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): seq[byte] =
  if not entry.valid: raise newException(ValueError, entry.warning)
  let volume = sources.related(sources.volumePath(game, entry.volume))
  if volume.isNil: raise newException(ValueError, "SCI resource volume is unavailable")
  defer: volume.close()
  let headerSize = if game.version == srmvSci0: 8 else: 9
  volume.readAt(entry.offset + headerSize, game.payloadSize(entry))

proc materializer(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): VextPayloadMaterializer =
  result = proc(): seq[byte] = resourceBytes(sources, game, entry)

proc storedMaterializer(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): VextPayloadMaterializer =
  result = proc(): seq[byte] = storedResourceBytes(sources, game, entry)

proc gameResourceTree*(sources: VextSourceCollection, game: SciGame): VextResourceTree =
  let root = VextResourceNode(path: "/game", typeId: SierraSciGameTypeId,
    kind: vrnkGroup, metadata: @[
      stringMetadata("sci.resource-map", case game.version
        of srmvSci0: "SCI0"
        of srmvSci1: "SCI1"
        of srmvSci11: "SCI1.1"),
      integerMetadata("resource.count", game.entries.len)])
  var groups: array[SciResourceKind, VextResourceNode]
  var soundsGroup, samplesGroup: VextResourceNode
  var present: set[SciResourceKind]
  for entry in game.entries: present.incl entry.kind
  for kind in SciResourceKind:
    if kind notin present: continue
    if kind == srkSound:
      soundsGroup = VextResourceNode(path: root.path & "/sounds",
        typeId: SierraSciGameTypeId & ".sounds", kind: vrnkGroup)
      groups[kind] = VextResourceNode(path: soundsGroup.path & "/sequences",
        typeId: SierraSciGameTypeId & ".sound-sequences", kind: vrnkGroup)
      soundsGroup.children.add groups[kind]
      root.children.add soundsGroup
    else:
      groups[kind] = VextResourceNode(path: root.path & "/" & ResourceKindNames[ord(kind)],
        typeId: SierraSciGameTypeId & "." & ResourceKindNames[ord(kind)], kind: vrnkGroup)
      root.children.add groups[kind]
  var totals, encountered: Table[(int, int), int]
  for entry in game.entries:
    totals[(entry.typeNumber, entry.number)] =
      totals.getOrDefault((entry.typeNumber, entry.number)) + 1
  var sci11FallbackPalette: seq[VextRgb]
  if game.version == srmvSci11:
    for paletteEntry in game.entries:
      if paletteEntry.kind == srkPalette and paletteEntry.number == 999:
        try:
          sci11FallbackPalette = parseSci11Palette(
            resourceBytes(sources, game, paletteEntry))
        except ValueError:
          discard
        break
  for entry in game.entries:
    let e = entry
    let key = (e.typeNumber, e.number)
    let copyIndex = encountered.getOrDefault(key)
    encountered[key] = copyIndex + 1
    let path = groups[e.kind].path & "/" & $e.number &
      (if totals[key] > 1: "-copy-" & $copyIndex else: "")
    let supportedCompression = e.valid and (e.compressionMethod in [0, 1, 18, 19, 20] or
      game.version == srmvSci0 and e.compressionMethod == 2)
    var warning = e.warning
    if e.valid and not supportedCompression:
      warning = "compression method " & $e.compressionMethod & " is not documented sufficiently for decoding"
    var metadata = @[integerMetadata("resource.type", e.typeNumber),
      integerMetadata("resource.number", e.number), integerMetadata("volume", e.volume),
      integerMetadata("volume.offset", e.offset), integerMetadata("stored.size", max(0, game.payloadSize(e))),
      integerMetadata("uncompressed.size", e.decompressedSize),
      integerMetadata("compression.method", e.compressionMethod),
      stringMetadata("payload.representation", if supportedCompression:
        "decompressed" else: "stored-compressed")]
    if warning.len > 0: metadata.add stringMetadata("decode.warning", warning)
    let node = VextResourceNode(path: path,
      typeId: SierraSciGameTypeId &
        (if e.kind == srkSound: ".sound-sequence" else: ".resource"),
      kind: vrnkOpaque, rawDataAvailable: e.valid,
      failureFormat: if warning.len > 0: SierraSciGameTypeId else: "",
      failureMessage: warning, metadata: metadata, defaultExportPriority: 10)
    if supportedCompression:
      node.lazyPayload = VextPayloadRef(length: e.decompressedSize,
        materializer: materializer(sources, game, e))
      var payloadDecoded = false
      try:
        let bytes = resourceBytes(sources, game, e)
        payloadDecoded = true
        if e.kind == srkFont:
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/font", typeId: SierraSciGameTypeId & ".font",
              kind: vrnkFont, font: decodeSciFont(bytes, "SCI font " & $e.number), defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw", typeId: SierraSciGameTypeId & ".font-data",
              kind: vrnkOpaque, rawDataAvailable: true, lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkCursor:
          let hotspot = sciCursorHotspot(bytes, game.version != srmvSci0)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/image", typeId: SierraSciGameTypeId & ".cursor",
              kind: vrnkRaster, raster: decodeSciCursor(bytes, game.version != srmvSci0), metadata: @[
                integerMetadata("hotspot.x", hotspot.x), integerMetadata("hotspot.y", hotspot.y)],
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw", typeId: SierraSciGameTypeId & ".cursor-data",
              kind: vrnkOpaque, rawDataAvailable: true, lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkPicture and game.version == srmvSci0:
          let picture = renderSci0Picture(bytes)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/visual",
              typeId: SierraSciGameTypeId & ".picture-visual", kind: vrnkRaster,
              raster: picture.visual, defaultExportPriority: 10),
            VextResourceNode(path: path & "/priority",
              typeId: SierraSciGameTypeId & ".picture-priority", kind: vrnkRaster,
              raster: picture.priority, defaultExportPriority: 10),
            VextResourceNode(path: path & "/control",
              typeId: SierraSciGameTypeId & ".picture-control", kind: vrnkRaster,
              raster: picture.control, defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".picture-data", kind: vrnkOpaque,
              rawDataAvailable: true, lazyPayload: node.lazyPayload,
              defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkPicture and game.version == srmvSci11:
          let picture = renderSci11Picture(bytes, sci11FallbackPalette)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/visual",
              typeId: SierraSciGameTypeId & ".picture-visual", kind: vrnkRaster,
              raster: picture.visual,
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/priority",
              typeId: SierraSciGameTypeId & ".picture-priority", kind: vrnkRaster,
              raster: picture.priority, defaultExportPriority: 10),
            VextResourceNode(path: path & "/control",
              typeId: SierraSciGameTypeId & ".picture-control", kind: vrnkRaster,
              raster: picture.control,
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".picture-data", kind: vrnkOpaque,
              rawDataAvailable: true, lazyPayload: node.lazyPayload,
              defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkSound and game.version == srmvSci0 and
            bytes.len > 0 and bytes[0] == 2:
          let sample = parseSci0DigitalSample(bytes)
          if samplesGroup.isNil:
            samplesGroup = VextResourceNode(path: soundsGroup.path & "/samples",
              typeId: SierraSciGameTypeId & ".digital-samples", kind: vrnkGroup)
            soundsGroup.children.add samplesGroup
          samplesGroup.children.add VextResourceNode(
            path: samplesGroup.path & "/" & $e.number &
              (if totals[key] > 1: "-copy-" & $copyIndex else: ""),
            typeId: SierraSciGameTypeId & ".digital-sample", kind: vrnkAudio,
            audioKind: varkSound, sound: sample.sound, metadata: @[
              integerMetadata("source.resource", e.number),
              integerMetadata("sample-rate", sample.sampleRate),
              integerMetadata("samples", sample.pcm.len),
              integerMetadata("duration-ms",
                sample.pcm.len * 1000 div sample.sampleRate),
              integerMetadata("sample-header.offset", sample.headerOffset)],
            defaultExportPriority: 10)
        elif e.kind == srkVocabulary and e.number == 0:
          let vocabulary = parseSciVocabulary(bytes)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/all",
              typeId: SierraSciGameTypeId & ".vocabulary-listing",
              kind: vrnkText, text: vocabulary.completeListing, metadata: @[
                integerMetadata("words", vocabulary.words.len)],
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".vocabulary-data",
              kind: vrnkOpaque, rawDataAvailable: true,
              lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
          let classes = VextResourceNode(path: path & "/classes",
            typeId: SierraSciGameTypeId & ".vocabulary-classes", kind: vrnkGroup)
          for classInfo in SciVocabularyClasses:
            let listing = vocabulary.classListing(classInfo.bit)
            if listing.len > "word\tgroup\n".len:
              classes.children.add VextResourceNode(
                path: classes.path & "/" & classInfo.name,
                typeId: SierraSciGameTypeId & ".vocabulary-class",
                kind: vrnkText, text: listing, metadata: @[
                  integerMetadata("class-mask", classInfo.bit)],
                defaultExportPriority: 10)
          node.children.insert(classes, 1)
        elif e.kind == srkVocabulary and e.number == 900:
          let grammar = parseSciGrammar(bytes)
          var mainVocabulary: SciVocabulary
          var haveMainVocabulary = false
          for vocabularyEntry in game.entries:
            if vocabularyEntry.kind == srkVocabulary and
                vocabularyEntry.number == 0:
              try:
                mainVocabulary = parseSciVocabulary(
                  resourceBytes(sources, game, vocabularyEntry))
                haveMainVocabulary = true
              except ValueError:
                discard
              break
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/rules",
              typeId: SierraSciGameTypeId & ".grammar-listing",
              kind: vrnkText, text: grammar.listing, metadata: @[
                integerMetadata("rules", grammar.rules.len)],
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".grammar-data",
              kind: vrnkOpaque, rawDataAvailable: true,
              lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          if haveMainVocabulary:
            node.children.insert(VextResourceNode(path: path & "/grammar",
              typeId: SierraSciGameTypeId & ".annotated-grammar",
              kind: vrnkText,
              text: grammar.annotatedListing(mainVocabulary),
              defaultExportPriority: 20), 1)
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkVocabulary and e.number == 901:
          let suffixes = parseSciSuffixes(bytes)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/suffixes",
              typeId: SierraSciGameTypeId & ".suffix-listing",
              kind: vrnkText, text: suffixes.suffixListing, metadata: @[
                integerMetadata("rules", suffixes.len)],
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".suffix-data",
              kind: vrnkOpaque, rawDataAvailable: true,
              lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkVocabulary and
            (e.number == 995 or e.number == 997 or e.number == 998 or
              e.number == 999):
          let table = parseSciStringTable(bytes)
          let listingPath = case e.number
            of 995: "help"
            of 997: "selectors"
            of 998: "opcodes"
            else: "kernel-functions"
          let listing = case e.number
            of 995: table.helpListing
            of 997: table.namedListing("selector")
            of 998: table.namedListing("opcode", 2)
            else: table.namedListing("kernel-function")
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/" & listingPath,
              typeId: SierraSciGameTypeId & ".debug-listing",
              kind: vrnkText, text: listing, metadata: @[
                integerMetadata("records", table.records.len)],
              defaultExportPriority: 10),
            VextResourceNode(path: path & "/raw",
              typeId: SierraSciGameTypeId & ".debug-data",
              kind: vrnkOpaque, rawDataAvailable: true,
              lazyPayload: node.lazyPayload, defaultExportPriority: 10)]
          node.lazyPayload = VextPayloadRef()
        elif e.kind == srkView and game.version in {srmvSci0, srmvSci11}:
          let view = if game.version == srmvSci0: parseSci0View(bytes)
            else: parseSci11View(bytes, sci11FallbackPalette)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children.add VextResourceNode(path: path & "/raw",
            typeId: SierraSciGameTypeId & ".view-data", kind: vrnkOpaque,
            rawDataAvailable: true, lazyPayload: node.lazyPayload, defaultExportPriority: 10)
          node.lazyPayload = VextPayloadRef()
          for loopIndex, loop in view.loops:
            let loopNode = VextResourceNode(path: path & "/loops/" & $loopIndex,
              typeId: SierraSciGameTypeId & ".view-loop", kind: vrnkGroup,
              metadata: @[integerMetadata("cel.count", loop.cels.len),
                stringMetadata("mirrored", $loop.mirrored)])
            loopNode.children.add VextResourceNode(
              path: loopNode.path & "/animation",
              typeId: SierraSciGameTypeId & ".view-animation",
              kind: vrnkRaster, raster: loop.animation, metadata: @[
                integerMetadata("frame.count", loop.cels.len),
                integerMetadata("preview.frame-duration-ms", 100),
                stringMetadata("timing.source", "synthetic-preview")],
              defaultExportPriority: 20)
            for celIndex, cel in loop.cels:
              loopNode.children.add VextResourceNode(path: loopNode.path & "/cels/" & $celIndex,
                typeId: SierraSciGameTypeId & ".view-cel", kind: vrnkRaster,
                raster: cel.raster(loop.mirrored), metadata: @[
                  integerMetadata("placement.x", cel.xOffset), integerMetadata("placement.y", cel.yOffset),
                  integerMetadata("transparent.colour", cel.transparentColour)], defaultExportPriority: 10)
            node.children.add loopNode
      except ValueError as error:
        node.failureFormat = SierraSciGameTypeId
        node.failureMessage = error.msg
        node.metadata.add stringMetadata("decode.warning", error.msg)
        if e.compressionMethod != 0 and not payloadDecoded:
          # A SCI0-style map does not by itself distinguish SCI0 from SCI01,
          # where the same method number can name a different codec. Failed
          # codec validation must leave the stored bytes recoverable.
          node.lazyPayload = VextPayloadRef(length: max(0, game.payloadSize(e)),
            materializer: storedMaterializer(sources, game, e))
          for item in node.metadata.mitems:
            if item.key == "payload.representation":
              item = stringMetadata("payload.representation", "stored-compressed")
    elif e.valid:
      node.lazyPayload = VextPayloadRef(length: max(0, game.payloadSize(e)),
        materializer: storedMaterializer(sources, game, e))
    groups[e.kind].children.add node
  result.roots = @[root]
