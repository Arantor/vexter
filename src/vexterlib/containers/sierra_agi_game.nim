## Sierra AGI v2/v3 directory-backed packages.
## Format facts are derived from the AGI Wiki chapters supplied in agi-spec/.

import std/[algorithm, strutils]
import ../byte_sources
import ../archetypes/raster
import ../metadata
import ../resource_tree
import ../resources/sierra_agi_view
import ../resources/sierra_agi_picture

const SierraAgiGameTypeId* = "sierra.agi-game"

type
  AgiVersion* = enum av2, av3
  AgiResourceKind* = enum arkLogic, arkPicture, arkView, arkSound
  AgiEntry* = object
    kind*: AgiResourceKind
    number*, volume*, offset*: int
    storedSize*, unpackedSize*: int
    compressed*, picturePacked*, valid*: bool
    warning*: string
  AgiGame* = object
    version*: AgiVersion
    root*, prefix*: string
    entries*: seq[AgiEntry]
    directoryPaths*: seq[string]
    wordsPath*, objectPath*: string

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
  if source.isNil: raise newException(ValueError, "missing AGI member: " & path)
  # Related-source openers are intentionally lazy. Detection may inspect
  # hundreds of entries, so do not retain one operating-system handle per
  # read until the whole inspection session is closed.
  defer: source.close()
  source.readAll()

proc volumePath(sources: VextSourceCollection, game: AgiGame,
    volume: int): string =
  uniquePath(sources, joined(game.root, game.prefix & "VOL." & $volume))

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at + 2 > data.len: raise newException(ValueError, "truncated AGI integer")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc directoryEntries(data: openArray[byte], first, last: int,
    kind: AgiResourceKind): seq[AgiEntry] =
  if first < 0 or last < first or last > data.len or (last - first) mod 3 != 0:
    raise newException(ValueError, "invalid AGI directory framing")
  var at = first
  while at < last:
    let number = (at - first) div 3
    if not (data[at] == 0xff and data[at + 1] == 0xff and data[at + 2] == 0xff):
      result.add AgiEntry(kind: kind, number: number,
        volume: int(data[at]) shr 4,
        offset: ((int(data[at]) and 0x0f) shl 16) or
          (int(data[at + 1]) shl 8) or int(data[at + 2]))
    at += 3

proc inspectEntry(sources: VextSourceCollection, game: AgiGame,
    entry: var AgiEntry) =
  let path = sources.volumePath(game, entry.volume)
  if path.len == 0:
    entry.warning = "missing or ambiguous volume file"
    return
  let volume = sources.readRelated(path)
  let headerSize = if game.version == av2: 5 else: 7
  if entry.offset < 0 or entry.offset > volume.len - headerSize:
    entry.warning = "directory offset is outside volume bounds"
    return
  if volume[entry.offset] != 0x12 or volume[entry.offset + 1] != 0x34:
    entry.warning = "resource header signature is not $12 $34"
    return
  let marker = int(volume[entry.offset + 2])
  if (marker and 0x7f) != entry.volume:
    entry.warning = "resource header volume does not match directory entry"
    return
  entry.picturePacked = game.version == av3 and (marker and 0x80) != 0
  entry.unpackedSize = le16(volume, entry.offset + 3)
  entry.storedSize = if game.version == av2: entry.unpackedSize
    else: le16(volume, entry.offset + 5)
  entry.compressed = game.version == av3 and not entry.picturePacked and
    entry.storedSize != entry.unpackedSize
  if entry.storedSize < 0 or entry.offset + headerSize > volume.len - entry.storedSize:
    entry.warning = "stored resource extends beyond volume bounds"
    return
  entry.valid = true

proc discoverAgiGames*(sources: VextSourceCollection): seq[AgiGame] =
  ## Discovers structurally plausible roots. Duplicate case-folded members are
  ## deliberately ignored, since choosing either would be host-dependent.
  var roots: seq[string]
  for item in sources.relatedSources:
    let name = item.relativePath.basename.toUpperAscii
    let root = item.relativePath.dirname
    if name == "LOGDIR" and root notin roots: roots.add root
    elif (name == "DIRS" or (name.endsWith("DIR") and name notin
        ["LOGDIR", "PICDIR", "VIEWDIR", "SNDDIR"])) and root notin roots:
      roots.add root
  for root in roots:
    var game = AgiGame(root: root)
    let v2Names = ["LOGDIR", "PICDIR", "VIEWDIR", "SNDDIR"]
    var v2Paths: seq[string]
    var complete = true
    for name in v2Names:
      let path = uniquePath(sources, joined(root, name))
      if path.len == 0: complete = false
      v2Paths.add path
    try:
      if complete:
        game.version = av2
        game.directoryPaths = v2Paths
        for kind in AgiResourceKind:
          let data = sources.readRelated(v2Paths[ord(kind)])
          game.entries.add directoryEntries(data, 0, data.len, kind)
      else:
        var combined = ""
        for item in sources.relatedSources:
          if item.relativePath.dirname == root:
            let upper = item.relativePath.basename.toUpperAscii
            if upper == "DIRS" or (upper.endsWith("DIR") and upper notin v2Names):
              if combined.len > 0: combined = ""; break
              combined = item.relativePath
        if combined.len == 0: continue
        game.version = av3
        game.directoryPaths = @[combined]
        let base = combined.basename
        game.prefix = if base.cmpIgnoreCase("dirs") == 0: ""
          else: base[0 ..< base.len - 3]
        let data = sources.readRelated(combined)
        if data.len < 8: continue
        var offsets: array[5, int]
        for index in 0 .. 3: offsets[index] = le16(data, index * 2)
        offsets[4] = data.len
        if offsets[0] != 8: continue
        for index in 0 .. 3:
          if offsets[index] > offsets[index + 1]:
            raise newException(ValueError, "invalid AGI v3 directory offsets")
          game.entries.add directoryEntries(data, offsets[index],
            offsets[index + 1], AgiResourceKind(index))
      var valid = 0
      for entry in game.entries.mitems:
        sources.inspectEntry(game, entry)
        if entry.valid: inc valid
      if valid == 0: continue
      game.wordsPath = uniquePath(sources, joined(root, "WORDS.TOK"))
      game.objectPath = uniquePath(sources, joined(root, "OBJECT"))
      result.add move(game)
    except CatchableError:
      discard

proc agiLzwDecode*(input: openArray[byte], expected: int): seq[byte] =
  var prefix: array[2048, int]
  var suffix: array[2048, byte]
  var stack: array[2048, byte]
  var bitPos, width = 0
  width = 9
  var next = 258
  var previous = -1
  template nextCode(): int =
    block:
      var decoded = -1
      if bitPos + width <= input.len * 8:
        decoded = 0
        for bit in 0 ..< width:
          decoded = decoded or (((int(input[(bitPos + bit) shr 3]) shr
            ((bitPos + bit) and 7)) and 1) shl bit)
        bitPos += width
      decoded
  while result.len < expected:
    let value = nextCode()
    if value < 0 or value == 257: break
    if value == 256:
      width = 9; next = 258; previous = -1
      continue
    if value > next or value >= 2048: raise newException(ValueError, "invalid AGI LZW code")
    var current = value
    var top = 0
    if current == next:
      if previous < 0: raise newException(ValueError, "invalid AGI LZW first code")
      current = previous
      while current >= 256:
        stack[top] = suffix[current]; inc top; current = prefix[current]
      let first = byte(current)
      stack[top] = first; inc top
      for index in countdown(top - 1, 0): result.add stack[index]
      result.add first
      if next < 2048: prefix[next] = previous; suffix[next] = first; inc next
    else:
      while current >= 256:
        if top >= stack.len: raise newException(ValueError, "cyclic AGI LZW dictionary")
        stack[top] = suffix[current]; inc top; current = prefix[current]
      let first = byte(current)
      stack[top] = first; inc top
      for index in countdown(top - 1, 0): result.add stack[index]
      if previous >= 0 and next < 2048:
        prefix[next] = previous; suffix[next] = first; inc next
    previous = value
    if next == (1 shl width) and width < 11: inc width
  if result.len != expected:
    raise newException(ValueError, "AGI LZW output length mismatch")

proc unpackV3Picture*(input: openArray[byte], expected: int): seq[byte] =
  var bit = 0
  template take(width: int): int =
    block:
      var decoded = -1
      if bit + width <= input.len * 8:
        decoded = 0
        for offset in 0 ..< width:
          decoded = (decoded shl 1) or
            ((int(input[(bit + offset) shr 3]) shr
              (7 - ((bit + offset) and 7))) and 1)
        bit += width
      decoded
  while result.len < expected:
    let command = take(8)
    if command < 0: break
    result.add byte(command)
    if command in [0xf0, 0xf2] and result.len < expected:
      let colour = take(4)
      if colour < 0: break
      result.add byte(colour)
  if result.len != expected:
    raise newException(ValueError, "AGI packed-picture output length mismatch")

proc resourceBytes*(sources: VextSourceCollection, game: AgiGame,
    entry: AgiEntry): seq[byte] =
  if not entry.valid: raise newException(ValueError, entry.warning)
  let volume = sources.readRelated(sources.volumePath(game, entry.volume))
  let header = if game.version == av2: 5 else: 7
  let stored = volume[entry.offset + header ..< entry.offset + header + entry.storedSize]
  if entry.compressed: agiLzwDecode(stored, entry.unpackedSize)
  elif entry.picturePacked: unpackV3Picture(stored, entry.unpackedSize)
  else: @stored

proc resourceMaterializer(sources: VextSourceCollection, game: AgiGame,
    entry: AgiEntry): VextPayloadMaterializer =
  result = proc(): seq[byte] = resourceBytes(sources, game, entry)

proc pictureGifMaterializer(sources: VextSourceCollection, game: AgiGame,
    entry: AgiEntry, drawingSteps: int): VextRasterMaterializer =
  result = proc(): VextRaster =
    renderAgiPicture(resourceBytes(sources, game, entry), true,
      drawingSteps).drawing

proc decodeWordsTok*(data: openArray[byte]): string =
  if data.len < 52: raise newException(ValueError, "truncated WORDS.TOK header")
  var at = 52
  var previous = ""
  var rows: seq[tuple[id: int, word: string]]
  while at < data.len:
    # Sierra vocabularies commonly end in one padding/sentinel zero. It is not
    # a zero-length word because no encrypted character or identifier follows.
    if data[at] == 0 and at + 1 == data.len: break
    let retained = int(data[at]); inc at
    if retained > previous.len: raise newException(ValueError, "invalid WORDS.TOK prefix")
    var word = previous[0 ..< retained]
    while true:
      if at >= data.len: raise newException(ValueError, "truncated WORDS.TOK word")
      let encoded = data[at]; inc at
      let last = (encoded and 0x80) != 0
      let decoded = (encoded and 0x7f) xor 0x7f
      if decoded >= 0x20 and decoded < 0x7f: word.add char(decoded)
      else: word.add "\\x" & toHex(decoded, 2)
      if last: break
    if at + 2 > data.len: raise newException(ValueError, "truncated WORDS.TOK identifier")
    let id = (int(data[at]) shl 8) or int(data[at + 1]); at += 2
    rows.add (id, word); previous = word
  rows.sort(proc(a, b: auto): int =
    result = cmp(a.id, b.id); if result == 0: result = cmp(a.word, b.word))
  result = "id\tword\n"
  for row in rows: result.add $row.id & "\t" & row.word & "\n"

proc xorCipher(data: openArray[byte], key: string): seq[byte] =
  result = newSeq[byte](data.len)
  for index, value in data: result[index] = value xor byte(key[index mod key.len])

proc escapedText(data: openArray[byte], first: int): string =
  var at = first
  while at < data.len and data[at] != 0:
    let value = data[at]
    if value >= 0x20 and value < 0x7f: result.add char(value)
    else: result.add "\\x" & toHex(value, 2)
    inc at
  if at >= data.len: raise newException(ValueError, "unterminated OBJECT name")

proc decodeObjectVariant(data: openArray[byte]): string =
  if data.len < 3: raise newException(ValueError, "truncated OBJECT header")
  let namesRelative = le16(data, 0)
  if namesRelative < 0 or namesRelative mod 3 != 0:
    raise newException(ValueError, "invalid OBJECT entry-table length")
  let namesStart = 3 + namesRelative
  if namesStart > data.len: raise newException(ValueError, "OBJECT names are outside file")
  result = "id\troom\tstate\tname\n"
  for index in 0 ..< namesRelative div 3:
    let at = 3 + index * 3
    let nameAt = 3 + le16(data, at)
    if nameAt < namesStart or nameAt >= data.len:
      raise newException(ValueError, "OBJECT name offset is outside names section")
    let room = int(data[at + 2])
    result.add $index & "\t" & $room & "\t" &
      (if room == 255: "carried" else: "room") & "\t" &
      escapedText(data, nameAt) & "\n"

proc decodeObject*(data: openArray[byte]): string =
  var variants: seq[seq[byte]] = @[@data, xorCipher(data, "Avis Durgan"),
    xorCipher(data, "Alex Simkin")]
  var decoded: seq[string]
  for variant in variants:
    try: decoded.add decodeObjectVariant(variant)
    except ValueError: discard
  if decoded.len == 0: raise newException(ValueError, "OBJECT structure did not validate")
  result = decoded[0]
  for item in decoded:
    if item != result:
      raise newException(ValueError, "OBJECT encryption variant is ambiguous")

proc gameResourceTree*(sources: VextSourceCollection, game: AgiGame): VextResourceTree =
  let gameNode = VextResourceNode(path: "/game", typeId: SierraAgiGameTypeId,
    kind: vrnkGroup, metadata: @[
      stringMetadata("agi.version", if game.version == av2: "2" else: "3"),
      stringMetadata("package.prefix", game.prefix)])
  let names = ["logics", "pictures", "views", "sounds"]
  var groups: array[4, VextResourceNode]
  for kind in AgiResourceKind:
    groups[ord(kind)] = VextResourceNode(path: "/game/" & names[ord(kind)],
      typeId: SierraAgiGameTypeId & "." & names[ord(kind)], kind: vrnkGroup)
    gameNode.children.add groups[ord(kind)]
  for entry in game.entries:
    let e = entry
    let path = groups[ord(e.kind)].path & "/" & $e.number
    var metadata = @[
      integerMetadata("directory.index", e.number), integerMetadata("volume", e.volume),
      integerMetadata("volume.offset", e.offset), integerMetadata("stored.size", e.storedSize),
      integerMetadata("uncompressed.size", e.unpackedSize),
      stringMetadata("compression", if e.compressed: "agi-lzw" elif e.picturePacked: "v3-picture" else: "none")]
    if e.warning.len > 0: metadata.add stringMetadata("decode.warning", e.warning)
    let node = VextResourceNode(path: path, typeId: SierraAgiGameTypeId & ".resource",
      kind: vrnkOpaque, rawDataAvailable: e.valid, failureFormat: if e.valid: "" else: SierraAgiGameTypeId,
      failureMessage: e.warning, metadata: metadata, defaultExportPriority: 10)
    if e.valid:
      node.lazyPayload = VextPayloadRef(length: e.unpackedSize,
        materializer: resourceMaterializer(sources, game, e))
    if e.valid and e.kind == arkPicture:
      try:
        let picture = renderAgiPicture(resourceBytes(sources, game, e))
        node.kind = vrnkGroup
        node.typeId = SierraAgiGameTypeId & ".picture"
        node.rawDataAvailable = false
        node.lazyPayload = VextPayloadRef()
        node.children = @[
          VextResourceNode(path: path & "/visual",
            typeId: SierraAgiGameTypeId & ".picture-visual", kind: vrnkRaster,
            raster: picture.visual,
            gifRasterMaterializer: pictureGifMaterializer(sources, game, e,
              picture.drawingSteps),
            defaultExportPriority: 10),
          VextResourceNode(path: path & "/priority",
            typeId: SierraAgiGameTypeId & ".picture-priority", kind: vrnkRaster,
            raster: picture.priority, defaultExportPriority: 10),
          VextResourceNode(path: path & "/raw",
            typeId: SierraAgiGameTypeId & ".picture-data", kind: vrnkOpaque,
            rawDataAvailable: true, lazyPayload: VextPayloadRef(length: e.unpackedSize,
              materializer: resourceMaterializer(sources, game, e)),
            defaultExportPriority: 10)]
      except ValueError as error:
        node.failureFormat = SierraAgiGameTypeId & ".picture"
        node.failureMessage = error.msg
        node.metadata.add stringMetadata("decode.warning", error.msg)
    elif e.valid and e.kind == arkView:
      try:
        let view = parseAgiView(resourceBytes(sources, game, e))
        node.kind = vrnkGroup
        node.typeId = SierraAgiGameTypeId & ".view"
        node.rawDataAvailable = false
        node.lazyPayload = VextPayloadRef()
        node.metadata.add integerMetadata("view.loop-count", view.loops.len)
        if view.description.len > 0:
          node.metadata.add stringMetadata("view.description", view.description)
        node.children.add VextResourceNode(path: path & "/raw",
          typeId: SierraAgiGameTypeId & ".view-data", kind: vrnkOpaque,
          rawDataAvailable: true, lazyPayload: VextPayloadRef(length: e.unpackedSize,
            materializer: resourceMaterializer(sources, game, e)),
          defaultExportPriority: 10)
        for loopIndex, loop in view.loops:
          let loopNode = VextResourceNode(path: path & "/loops/" & $loopIndex,
            typeId: SierraAgiGameTypeId & ".view-loop", kind: vrnkGroup,
            metadata: @[integerMetadata("view.cel-count", loop.cels.len)])
          for celIndex, cel in loop.cels:
            loopNode.children.add VextResourceNode(
              path: loopNode.path & "/cels/" & $celIndex,
              typeId: SierraAgiGameTypeId & ".view-cel", kind: vrnkRaster,
              raster: cel.raster, metadata: @[
                integerMetadata("width", cel.width), integerMetadata("height", cel.height),
                integerMetadata("transparent-colour", cel.transparentColour),
                stringMetadata("mirrored", $cel.mirrored),
                integerMetadata("mirror-loop", cel.mirrorLoop)],
              defaultExportPriority: 10)
          node.children.add loopNode
      except ValueError as error:
        node.failureFormat = SierraAgiGameTypeId & ".view"
        node.failureMessage = error.msg
        node.metadata.add stringMetadata("decode.warning", error.msg)
    groups[ord(e.kind)].children.add node
  if game.wordsPath.len > 0:
    try:
      gameNode.children.add VextResourceNode(path: "/game/vocabulary",
        typeId: SierraAgiGameTypeId & ".vocabulary", kind: vrnkText,
        text: decodeWordsTok(sources.readRelated(game.wordsPath)),
        defaultExportPriority: 10)
    except ValueError as error:
      gameNode.children.add VextResourceNode(path: "/game/vocabulary",
        typeId: SierraAgiGameTypeId & ".vocabulary", kind: vrnkOpaque,
        failureFormat: SierraAgiGameTypeId, failureMessage: error.msg)
  if game.objectPath.len > 0:
    try:
      gameNode.children.add VextResourceNode(path: "/game/inventory",
        typeId: SierraAgiGameTypeId & ".inventory", kind: vrnkText,
        text: decodeObject(sources.readRelated(game.objectPath)),
        defaultExportPriority: 10)
    except ValueError as error:
      gameNode.children.add VextResourceNode(path: "/game/inventory",
        typeId: SierraAgiGameTypeId & ".inventory", kind: vrnkOpaque,
        failureFormat: SierraAgiGameTypeId, failureMessage: error.msg)
  result.roots = @[gameNode]
