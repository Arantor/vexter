import std/[strutils, unittest]
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)

proc addLong(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 24) and 0xff)

proc setLong(data: var seq[byte], offset, value: int) =
  for index in 0 ..< 4:
    data[offset + index] = byte((value shr (index * 8)) and 0xff)

proc makePatch(): seq[byte] =
  result.addWord(2)
  result.addWord(3)
  result.addWord(0xffff) # Signed left offset -1.
  result.addWord(4)
  result.addLong(16)
  result.addLong(23)
  result.add @[0'u8, 2, 0, 1, 2, 0, 255]
  result.add @[1'u8, 2, 0, 3, 4, 0, 255]

proc makePatch(base: int): seq[byte] =
  result = makePatch()
  result[19] = byte(base)
  result[20] = byte(base + 1)
  result[26] = byte(base + 2)
  result[27] = byte(base + 3)

proc addName(data: var seq[byte], name: string) =
  for index in 0 ..< 8:
    data.add if index < name.len: byte(name[index]) else: 0

proc makePnames(names: openArray[string]): seq[byte] =
  result.addLong(names.len)
  for name in names: result.addName(name)

proc makeTextureDirectory(name: string, width, height: int,
    patches: openArray[tuple[x, y, patch, step, colourMap: int]]): seq[byte] =
  result.addLong(1)
  result.addLong(8)
  result.addName(name)
  result.addLong(0)
  result.addWord(width)
  result.addWord(height)
  result.addLong(0)
  result.addWord(patches.len)
  for patch in patches:
    result.addWord(patch.x)
    result.addWord(patch.y)
    result.addWord(patch.patch)
    result.addWord(patch.step)
    result.addWord(patch.colourMap)

proc makePalettes(): seq[byte] =
  for palette in 0 ..< DoomPaletteCount:
    for colour in 0 ..< DoomPaletteColours:
      result.add byte(colour)
      result.add byte(palette)
      result.add byte(255 - colour)

proc makeSound(sampleRate: int, samples: openArray[byte]): seq[byte] =
  result.addWord(3)
  result.addWord(sampleRate)
  result.addWord(samples.len)
  result.addWord(0)
  result.add samples

proc makeVertices(vertices: openArray[tuple[x, y: int]]): seq[byte] =
  for vertex in vertices:
    result.addWord(vertex.x)
    result.addWord(vertex.y)

proc makeLine(startVertex, endVertex, flags, rightSide,
    leftSide: int): seq[byte] =
  result.addWord(startVertex)
  result.addWord(endVertex)
  result.addWord(flags)
  result.addWord(0) # Type.
  result.addWord(0) # Tag.
  result.addWord(rightSide)
  result.addWord(leftSide)

proc makeSide(sector: int): seq[byte] =
  result = newSeq[byte](28)
  result.addWord(sector)

proc makeSector(floorHeight, ceilingHeight: int): seq[byte] =
  result.addWord(floorHeight)
  result.addWord(ceilingHeight)
  result.setLen(26)

proc metadataInteger(node: VextResourceNode, key: string): int =
  for entry in node.metadata:
    if entry.key == key:
      return entry.value.integerValue
  raise newException(ValueError, "metadata key was not found: " & key)

proc makeWad(lumps: openArray[tuple[name: string, data: seq[byte]]],
    kind = "PWAD"): seq[byte] =
  for value in kind: result.add byte(value)
  result.addLong(lumps.len)
  result.addLong(0)
  var offsets: seq[int]
  for lump in lumps:
    offsets.add result.len
    result.add lump.data
  let directoryOffset = result.len
  result.setLong(8, directoryOffset)
  for index, lump in lumps:
    result.addLong(offsets[index])
    result.addLong(lump.data.len)
    for nameIndex in 0 ..< 8:
      result.add if nameIndex < lump.name.len: byte(lump.name[nameIndex]) else: 0

suite "DOOM WAD":
  test "structural parser preserves directory order and duplicate names":
    let data = makeWad([
      (name: "DUP", data: @[1'u8]),
      (name: "DUP", data: @[2'u8]),
      (name: "EMPTY", data: newSeq[byte]())], "IWAD")
    let wad = parseDoomWad(data)
    check wad.kind == dwkIwad
    check wad.entries.len == 3
    check wad.entries[0].name == "DUP"
    check wad.entries[1].name == "DUP"
    check wad.entries[0].entryBytes(data) == @[1'u8]
    check wad.entries[1].entryBytes(data) == @[2'u8]
    check wad.entries[2].size == 0

  test "directory and lump bounds are validated":
    var badDirectory = makeWad([(name: "ONE", data: @[1'u8])])
    badDirectory.setLong(8, badDirectory.len)
    expect ValueError: discard parseDoomWad(badDirectory)

    var badLump = makeWad([(name: "ONE", data: @[1'u8])])
    let directoryOffset = int(badLump[8]) or (int(badLump[9]) shl 8)
    badLump.setLong(directoryOffset, badLump.len + 1)
    expect ValueError: discard parseDoomWad(badLump)

  test "PLAYPAL exposes all palettes and drives flat and patch pixels":
    var flat = newSeq[byte](DoomFlatSize)
    for index in 0 ..< flat.len: flat[index] = byte(index mod 256)
    let data = makeWad([
      (name: "PLAYPAL", data: makePalettes()),
      (name: "F_START", data: newSeq[byte]()),
      (name: "FLOOR1", data: flat),
      (name: "F_END", data: newSeq[byte]()),
      (name: "SPRTA0", data: makePatch()),
      (name: "DUP", data: @[7'u8]),
      (name: "DUP", data: @[8'u8])])
    let inspection = inspectSource("synthetic.wad", data)
    check inspection.selectedFormat.typeId == DoomWadTypeId
    check inspection.resources.roots.len == 1
    let lumps = inspection.resources.roots[0].children[0]
    check lumps.children.len == 7
    check lumps.children[0].children.len == DoomPaletteCount
    check lumps.children[0].children[0].kind == vrnkPalette
    check lumps.children[0].children[13].palette.colours[42] ==
      VextRgb(r: 42, g: 13, b: 213)

    let flatNode = inspection.resources.findRasterResource(
      "/wad/lumps/2-FLOOR1")
    check not flatNode.isNil
    check flatNode.raster.image.width == 64
    check flatNode.raster.image.height == 64
    check flatNode.raster.image.pixelAt(63, 0) == 63

    let patchNode = inspection.resources.findRasterResource(
      "/wad/lumps/4-SPRTA0")
    check not patchNode.isNil
    check patchNode.raster.image.width == 2
    check patchNode.raster.image.height == 3
    check patchNode.raster.image.pixelAt(0, 0) == 1
    check patchNode.raster.image.pixelAt(0, 1) == 2
    check patchNode.raster.image.alphaAt(0, 2) == 0
    check patchNode.raster.image.alphaAt(1, 0) == 0
    check patchNode.raster.image.pixelAt(1, 1) == 3
    check patchNode.metadata[4].value.integerValue == -1
    check patchNode.metadata[5].value.integerValue == 4
    check patchNode.exportFormatsFor[0].id == "png"
    let exported = exportResource(inspection.resources, VextExportRequest(
      resourcePath: patchNode.path, suggestedName: "sprite"))
    check exported.outputFormat == "png"
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].data[0 ..< 8] ==
      @[137'u8, 80, 78, 71, 13, 10, 26, 10]
    check lumps.children[5].path == "/wad/lumps/5-DUP"
    check lumps.children[6].path == "/wad/lumps/6-DUP"

  test "malformed PLAYPAL remains available with a warning":
    let data = makeWad([
      (name: "PLAYPAL", data: @[0'u8]),
      (name: "OTHER", data: @[1'u8])])
    let inspection = inspectSource("bad.wad", data)
    let playpal = inspection.resources.roots[0].children[0].children[0]
    check playpal.kind == vrnkOpaque
    check playpal.rawDataAvailable
    check playpal.failureFormat == DoomWadPaletteTypeId
    check inspection.warnings.len == 1

  test "malformed flat remains available with a warning":
    let data = makeWad([
      (name: "PLAYPAL", data: makePalettes()),
      (name: "F_START", data: newSeq[byte]()),
      (name: "BADFLAT", data: @[1'u8]),
      (name: "F_END", data: newSeq[byte]())])
    let inspection = inspectSource("bad-flat.wad", data)
    let flat = inspection.resources.roots[0].children[0].children[2]
    check flat.kind == vrnkOpaque
    check flat.rawDataAvailable
    check flat.failureFormat == DoomWadFlatTypeId
    check inspection.warnings.len == 1

  test "patch parser rejects posts outside the declared height":
    var patch = makePatch()
    patch[16] = 2
    expect ValueError: discard parseDoomPatch(patch)

  test "DS lumps expose generic sounds and export as WAV":
    let data = makeWad([
      (name: "DSPISTOL", data: makeSound(11025,
        @[0'u8, 127, 128, 255])),
      (name: "dsdoor", data: makeSound(8000, @[128'u8, 129]))])
    let inspection = inspectSource("sounds.wad", data)
    check inspection.warnings.len == 0
    let pistol = inspection.resources.roots[0].children[0].children[0]
    check pistol.path == "/wad/lumps/0-DSPISTOL"
    check pistol.typeId == DoomWadSoundTypeId
    check pistol.kind == vrnkAudio
    check pistol.audioKind == varkSound
    check pistol.sound.sampleRate == 11025
    check pistol.sound.buffer.bitsPerSample == 8
    check pistol.sound.buffer.channels == @[@[-128'i32, -1, 0, 127]]
    check pistol.metadata[4].value.integerValue == 3
    check pistol.metadata[5].value.integerValue == 11025
    check pistol.metadata[6].value.integerValue == 4
    check pistol.exportFormatsFor[0].id == "wav"
    let exported = exportResource(inspection.resources, VextExportRequest(
      resourcePath: pistol.path, suggestedName: "pistol"))
    check exported.outputFormat == "wav"
    check exported.artifacts.artifacts[0].suggestedFilename == "pistol.wav"
    check decodeWav(parseWav(exported.artifacts.artifacts[0].data)) ==
      pistol.sound
    let door = inspection.resources.roots[0].children[0].children[1]
    check door.kind == vrnkAudio
    check door.sound.sampleRate == 8000
    let sounds = inspection.resources.roots[0].children[1]
    check sounds.path == "/wad/sounds"
    check sounds.children.len == 2
    check sounds.children[0].path == "/wad/sounds/0-DSPISTOL"
    check sounds.children[0].sound == pistol.sound
    check sounds.children[1].path == "/wad/sounds/1-dsdoor"
    check sounds.children[1].sound.sampleRate == 8000

  test "malformed DS lumps remain raw with decoder warnings":
    var wrongFormat = makeSound(11025, @[128'u8])
    wrongFormat[0] = 2
    var badCount = makeSound(11025, @[128'u8])
    badCount[4] = 2
    var reserved = makeSound(11025, @[128'u8])
    reserved[6] = 1
    let data = makeWad([
      (name: "DSFORMAT", data: wrongFormat),
      (name: "DSCOUNT", data: badCount),
      (name: "DSRESERV", data: reserved)])
    let inspection = inspectSource("bad-sounds.wad", data)
    check inspection.warnings.len == 3
    for node in inspection.resources.roots[0].children[0].children:
      check node.kind == vrnkOpaque
      check node.rawDataAvailable
      check node.failureFormat == DoomWadSoundTypeId
    let sounds = inspection.resources.roots[0].children[1]
    check sounds.path == "/wad/sounds"
    check sounds.children.len == 3
    for node in sounds.children:
      check node.kind == vrnkOpaque
      check node.failureFormat == DoomWadSoundTypeId

  test "sprite namespaces expose an ordered derived sprite collection":
    let data = makeWad([
      (name: "PLAYPAL", data: makePalettes()),
      (name: "S_START", data: newSeq[byte]()),
      (name: "TROOA0", data: makePatch(1)),
      (name: "TROOA0", data: makePatch(10)),
      (name: "BROKEN", data: @[1'u8]),
      (name: "S_END", data: newSeq[byte]()),
      (name: "OUTSIDE", data: makePatch(20))])
    let inspection = inspectSource("sprites.wad", data)
    check inspection.warnings.len == 1
    let sprites = inspection.resources.roots[0].children[1]
    check sprites.path == "/wad/sprites"
    check sprites.children.len == 3
    check sprites.children[0].path == "/wad/sprites/2-TROOA0"
    check sprites.children[1].path == "/wad/sprites/3-TROOA0"
    check sprites.children[0].raster.image.pixelAt(0, 0) == 1
    check sprites.children[1].raster.image.pixelAt(0, 0) == 10
    check sprites.children[2].path == "/wad/sprites/4-BROKEN"
    check sprites.children[2].kind == vrnkOpaque
    check sprites.children[2].failureFormat == DoomWadPatchTypeId
    check inspection.resources.findRasterResource(
      "/wad/lumps/6-OUTSIDE").raster.image.pixelAt(0, 0) == 20

  test "PNAMES and both texture directories produce composited rasters":
    let texture1 = makeTextureDirectory("WALLONE", 3, 3, [
      (x: 0, y: 0, patch: 0, step: 1, colourMap: 0),
      (x: 1, y: -1, patch: 1, step: 1, colourMap: 0)])
    let texture2 = makeTextureDirectory("WALLTWO", 2, 3, [
      (x: 0, y: 0, patch: 0, step: 2, colourMap: 3)])
    let data = makeWad([
      (name: "PLAYPAL", data: makePalettes()),
      (name: "PNAMES", data: makePnames(["patcha", "PATCHB"])),
      (name: "TEXTURE1", data: texture1),
      (name: "PATCHA", data: makePatch(1)),
      (name: "PATCHB", data: makePatch(20)),
      (name: "PATCHB", data: makePatch(10)),
      (name: "TEXTURE2", data: texture2)])
    let inspection = inspectSource("textures.wad", data)
    check inspection.warnings.len == 0

    let wallOne = inspection.resources.findRasterResource(
      "/wad/textures/2-TEXTURE1/0-WALLONE")
    check not wallOne.isNil
    check wallOne.raster.image.width == 3
    check wallOne.raster.image.height == 3
    check wallOne.raster.image.pixelAt(0, 0) == 1
    check wallOne.raster.image.pixelAt(1, 0) == 11
    check wallOne.raster.image.pixelAt(2, 0) == 12
    check wallOne.raster.image.pixelAt(2, 1) == 13
    check wallOne.raster.image.alphaAt(0, 2) == 0
    check wallOne.metadata[8].value.integerValue == 0
    check wallOne.metadata[13].value.stringValue == "patcha"
    check wallOne.metadata[14].value.integerValue == 3
    check wallOne.metadata[20].value.stringValue == "PATCHB"
    check wallOne.metadata[21].value.integerValue == 5

    let wallTwo = inspection.resources.findRasterResource(
      "/wad/textures/6-TEXTURE2/0-WALLTWO")
    check not wallTwo.isNil
    check wallTwo.raster.image.pixelAt(1, 1) == 3
    check wallTwo.raster.image.pixelAt(1, 2) == 4
    check wallTwo.metadata[11].value.integerValue == 2
    check wallTwo.metadata[12].value.integerValue == 3

  test "unresolved texture recipes remain inspectable failures":
    let texture = makeTextureDirectory("MISSING", 2, 2, [
      (x: -1, y: 2, patch: 1, step: 1, colourMap: 0)])
    let data = makeWad([
      (name: "PLAYPAL", data: makePalettes()),
      (name: "PNAMES", data: makePnames(["ONLYONE"])),
      (name: "TEXTURE1", data: texture)])
    let inspection = inspectSource("missing.wad", data)
    let failed = inspection.resources.roots[0].children[1].children[0].children[0]
    check failed.path == "/wad/textures/2-TEXTURE1/0-MISSING"
    check failed.kind == vrnkOpaque
    check failed.failureFormat == DoomWadTextureTypeId
    check "outside PNAMES" in failed.failureMessage
    check failed.metadata[8].value.integerValue == -1
    check failed.metadata[9].value.integerValue == 2
    check inspection.warnings.len == 1

  test "texture directory offsets and patch tables are bounded":
    var badOffset = makeTextureDirectory("BROKEN", 2, 2,
      newSeq[tuple[x, y, patch, step, colourMap: int]]())
    badOffset.setLong(4, badOffset.len)
    expect ValueError: discard parseDoomTextureDirectory(badOffset)

    var badPnames = makePnames(["ONE"])
    badPnames.add 1
    expect ValueError: discard parseDoomPatchNames(badPnames)

  test "classic map lumps render an all-map-style overhead preview":
    let vertices = makeVertices([
      (x: 0, y: 0), (x: 100, y: 0),
      (x: 0, y: 10), (x: 100, y: 10),
      (x: 0, y: 20), (x: 100, y: 20),
      (x: 0, y: 30), (x: 100, y: 30),
      (x: 0, y: 40), (x: 100, y: 40),
      (x: 0, y: 50), (x: 100, y: 50)])
    var lines: seq[byte]
    lines.add makeLine(0, 1, 0, 0, -1) # One-sided: red.
    lines.add makeLine(2, 3, 1 shl 5, 0, 1) # Secret: red.
    lines.add makeLine(4, 5, 0, 0, 1) # Floor change: brown.
    lines.add makeLine(6, 7, 0, 0, 2) # Ceiling change: yellow.
    lines.add makeLine(8, 9, 1 shl 7, 0, 3) # Not on map: omitted.
    lines.add makeLine(10, 11, 0, 0, 3) # Equal heights: gray.
    var sides: seq[byte]
    for sector in 0 .. 3: sides.add makeSide(sector)
    var sectors: seq[byte]
    sectors.add makeSector(0, 128)
    sectors.add makeSector(64, 128)
    sectors.add makeSector(0, 192)
    sectors.add makeSector(0, 128)
    let data = makeWad([
      (name: "E1M1", data: newSeq[byte]()),
      (name: "THINGS", data: newSeq[byte]()),
      (name: "LINEDEFS", data: lines),
      (name: "SIDEDEFS", data: sides),
      (name: "VERTEXES", data: vertices),
      (name: "SEGS", data: newSeq[byte]()),
      (name: "SSECTORS", data: newSeq[byte]()),
      (name: "NODES", data: newSeq[byte]()),
      (name: "SECTORS", data: sectors),
      (name: "REJECT", data: newSeq[byte]()),
      (name: "BLOCKMAP", data: newSeq[byte]())])
    let inspection = inspectSource("map.wad", data)
    check inspection.warnings.len == 0
    let automap = inspection.resources.findRasterResource(
      "/wad/maps/0-E1M1/automap")
    check not automap.isNil
    check automap.typeId == DoomWadAutomapTypeId
    check automap.raster.kind == vrkTrueColourImage
    let image = automap.raster.trueColourImage
    check image.width == 117
    check image.height == 67
    check image.colourAt(58, 58) == VextRgb(r: 255, g: 0, b: 0)
    check image.colourAt(58, 48) == VextRgb(r: 255, g: 0, b: 0)
    check image.colourAt(58, 38) == VextRgb(r: 160, g: 80, b: 0)
    check image.colourAt(58, 28) == VextRgb(r: 255, g: 255, b: 0)
    check image.colourAt(58, 18) == VextRgb(r: 0, g: 0, b: 0)
    check image.colourAt(58, 8) == VextRgb(r: 128, g: 128, b: 128)
    check automap.metadataInteger("map.lump.linedefs.records") == 6
    check automap.metadataInteger("map.lump.nodes.records") == 0
    check automap.metadataInteger("map.bounds.maximum-x") == 100
    check automap.metadataInteger("map.hidden-linedefs") == 1
    let exported = exportResource(inspection.resources, VextExportRequest(
      resourcePath: automap.path, suggestedName: "E1M1"))
    check exported.outputFormat == "png"

  test "partial or invalid map geometry remains an inspectable failure":
    var badLines = makeLine(0, 2, 0, 0, -1)
    let data = makeWad([
      (name: "MAP01", data: newSeq[byte]()),
      (name: "LINEDEFS", data: badLines),
      (name: "VERTEXES", data: makeVertices([(x: 0, y: 0)])),
      (name: "TEXTURE1", data: @[0'u8, 0, 0, 0])])
    let inspection = inspectSource("bad-map.wad", data)
    check inspection.warnings.len == 1
    let failed = inspection.resources.roots[0].children[^1].children[0].children[0]
    check failed.path == "/wad/maps/0-MAP01/automap"
    check failed.kind == vrnkOpaque
    check failed.failureFormat == DoomWadAutomapTypeId
    check "missing vertex" in failed.failureMessage
