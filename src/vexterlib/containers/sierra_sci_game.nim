## Sierra SCI0/SCI1 directory-backed resource packages.
## Format facts are derived from supplied SCI Specifications chapters 1-3.

import std/[strutils, tables]
import ../byte_sources
import ../metadata
import ../resource_tree
import ../resources/sierra_sci_graphics
import ../resources/sierra_sci_picture
import ../resources/sierra_sci_sound
import ../resources/sierra_sci_vocabulary

const SierraSciGameTypeId* = "sierra.sci-game"

type
  SciResourceMapVersion* = enum srmvSci0, srmvSci1
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

proc parseSci1Map(data: openArray[byte]): seq[SciResourceEntry] =
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
  if types.len < 2 or types[0].first != at + 3:
    raise newException(ValueError, "SCI1 resource tables do not follow the type table")
  for index in 0 ..< types.len - 1:
    let first = types[index].first
    let finish = types[index + 1].first
    if finish < first or (finish - first) mod 6 != 0:
      raise newException(ValueError, "invalid SCI1 resource table bounds")
    var previous = -1
    var entryAt = first
    while entryAt < finish:
      let number = le16(data, entryAt)
      if number <= previous:
        raise newException(ValueError, "SCI1 resource table is not sorted")
      let location = le32(data, entryAt + 2)
      result.add SciResourceEntry(kind: resourceKind(types[index].number),
        typeNumber: types[index].number, number: number,
        volume: int(location shr 28), offset: int(location and 0x0fffffff'u32))
      previous = number
      entryAt += 6
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
  let payloadSize = entry.compressedSize - 4
  if entry.compressedSize < 4 or entry.decompressedSize < 0 or
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
        game.version = srmvSci1
        game.entries = parseSci1Map(data)
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

proc resourceBytes*(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): seq[byte] =
  if not entry.valid: raise newException(ValueError, entry.warning)
  let volume = sources.related(sources.volumePath(game, entry.volume))
  if volume.isNil: raise newException(ValueError, "SCI resource volume is unavailable")
  defer: volume.close()
  let headerSize = if game.version == srmvSci0: 8 else: 9
  let payloadSize = entry.compressedSize - 4
  let stored = volume.readAt(entry.offset + headerSize, payloadSize)
  if entry.compressionMethod == 0:
    if payloadSize != entry.decompressedSize:
      raise newException(ValueError, "uncompressed SCI resource sizes disagree")
    return @stored
  if entry.compressionMethod == 1:
    return sciLzwDecode(stored, entry.decompressedSize)
  if game.version == srmvSci0 and entry.compressionMethod == 2:
    return huffmanDecode(stored, entry.decompressedSize)
  raise newException(ValueError, "SCI compression method " & $entry.compressionMethod &
    " is not documented sufficiently for decoding")

proc storedResourceBytes(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): seq[byte] =
  if not entry.valid: raise newException(ValueError, entry.warning)
  let volume = sources.related(sources.volumePath(game, entry.volume))
  if volume.isNil: raise newException(ValueError, "SCI resource volume is unavailable")
  defer: volume.close()
  let headerSize = if game.version == srmvSci0: 8 else: 9
  volume.readAt(entry.offset + headerSize, entry.compressedSize - 4)

proc materializer(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): VextPayloadMaterializer =
  result = proc(): seq[byte] = resourceBytes(sources, game, entry)

proc storedMaterializer(sources: VextSourceCollection, game: SciGame,
    entry: SciResourceEntry): VextPayloadMaterializer =
  result = proc(): seq[byte] = storedResourceBytes(sources, game, entry)

proc gameResourceTree*(sources: VextSourceCollection, game: SciGame): VextResourceTree =
  let root = VextResourceNode(path: "/game", typeId: SierraSciGameTypeId,
    kind: vrnkGroup, metadata: @[
      stringMetadata("sci.resource-map", if game.version == srmvSci0: "SCI0" else: "SCI1"),
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
  for entry in game.entries:
    let e = entry
    let key = (e.typeNumber, e.number)
    let copyIndex = encountered.getOrDefault(key)
    encountered[key] = copyIndex + 1
    let path = groups[e.kind].path & "/" & $e.number &
      (if totals[key] > 1: "-copy-" & $copyIndex else: "")
    let supportedCompression = e.valid and (e.compressionMethod in [0, 1] or
      game.version == srmvSci0 and e.compressionMethod == 2)
    var warning = e.warning
    if e.valid and not supportedCompression:
      warning = "compression method " & $e.compressionMethod & " is not documented sufficiently for decoding"
    var metadata = @[integerMetadata("resource.type", e.typeNumber),
      integerMetadata("resource.number", e.number), integerMetadata("volume", e.volume),
      integerMetadata("volume.offset", e.offset), integerMetadata("stored.size", max(0, e.compressedSize - 4)),
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
          let hotspot = sciCursorHotspot(bytes, game.version == srmvSci1)
          node.kind = vrnkGroup; node.rawDataAvailable = false
          node.children = @[
            VextResourceNode(path: path & "/image", typeId: SierraSciGameTypeId & ".cursor",
              kind: vrnkRaster, raster: decodeSciCursor(bytes, game.version == srmvSci1), metadata: @[
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
        elif e.kind == srkView and game.version == srmvSci0:
          let view = parseSci0View(bytes)
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
          node.lazyPayload = VextPayloadRef(length: max(0, e.compressedSize - 4),
            materializer: storedMaterializer(sources, game, e))
          for item in node.metadata.mitems:
            if item.key == "payload.representation":
              item = stringMetadata("payload.representation", "stored-compressed")
    elif e.valid:
      node.lazyPayload = VextPayloadRef(length: max(0, e.compressedSize - 4),
        materializer: storedMaterializer(sources, game, e))
    groups[e.kind].children.add node
  result.roots = @[root]
