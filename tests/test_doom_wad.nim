import std/unittest
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

proc makePalettes(): seq[byte] =
  for palette in 0 ..< DoomPaletteCount:
    for colour in 0 ..< DoomPaletteColours:
      result.add byte(colour)
      result.add byte(palette)
      result.add byte(255 - colour)

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
