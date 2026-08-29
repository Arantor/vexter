import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte(value shr 8 and 0xff)

proc addDword(data: var seq[byte], value: int) =
  for shift in [0, 8, 16, 24]: data.add byte(value shr shift and 0xff)

proc setDword(data: var seq[byte], offset, value: int) =
  for index, shift in [0, 8, 16, 24]:
    data[offset + index] = byte(value shr shift and 0xff)

proc newPaletteChunk(size, first, last: int,
    colours: openArray[VextRgba]): seq[byte] =
  result.addDword(0)
  result.addWord(0x2019)
  result.addDword(size)
  result.addDword(first)
  result.addDword(last)
  for unused in 0 ..< 8: result.add 0
  for colour in colours:
    result.addWord(0)
    result.add @[colour.r, colour.g, colour.b, colour.a]
  result.setDword(0, result.len)

proc oldPaletteChunk(): seq[byte] =
  result.addDword(0)
  result.addWord(0x0004)
  result.addWord(1)
  result.add 0
  result.add 2
  result.add @[byte 200, 201, 202, 210, 211, 212]
  result.setDword(0, result.len)

proc unknownChunk(): seq[byte] =
  result.addDword(6)
  result.addWord(0x2004)

proc aseFile(chunks: openArray[seq[byte]], depth = 8): seq[byte] =
  result = newSeq[byte](128)
  result[4] = 0xe0
  result[5] = 0xa5
  result[6] = 1
  result[8] = 1
  result[10] = 1
  result[12] = byte(depth)
  result[18] = 100
  result[28] = 3
  result[32] = 4
  let frameStart = result.len
  result.addDword(0)
  result.addWord(0xf1fa)
  result.addWord(chunks.len)
  result.addWord(75)
  result.addWord(0)
  result.addDword(chunks.len)
  for chunk in chunks: result.add chunk
  result.setDword(frameStart, result.len - frameStart)
  result.setDword(0, result.len)

proc metadataValue(resource: VextResourceNode, key: string): VextMetadataValue =
  for entry in resource.metadata:
    if entry.key == key: return entry.value

suite "Aseprite files":
  test "new palette chunks preserve RGBA and ranged updates":
    let initial = newPaletteChunk(3, 0, 2, [
      VextRgba(r: 1, g: 2, b: 3, a: 4),
      VextRgba(r: 5, g: 6, b: 7, a: 8),
      VextRgba(r: 9, g: 10, b: 11, a: 12)])
    let update = newPaletteChunk(3, 1, 1, [
      VextRgba(r: 20, g: 21, b: 22, a: 23)])
    let inspection = inspectSource("palette.aseprite",
      aseFile([unknownChunk(), initial, update]))
    check inspection.selectedFormat.typeId == AsepriteTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == AsepritePaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 1, g: 2, b: 3, a: 4),
      VextRgba(r: 20, g: 21, b: 22, a: 23),
      VextRgba(r: 9, g: 10, b: 11, a: 12)]
    check resource.metadataValue("frames").integerValue == 1
    check resource.metadataValue("chunks").integerValue == 3
    check resource.metadataValue("palette-chunks").integerValue == 2
    check resource.defaultExportFormat == "palette-swatch"

  test "new palette takes precedence over compatibility old palette":
    let modern = newPaletteChunk(1, 0, 0,
      [VextRgba(r: 1, g: 2, b: 3, a: 4)])
    let source = parseAseprite(aseFile([oldPaletteChunk(), modern]))
    check source.palette.colours == @[
      VextRgba(r: 1, g: 2, b: 3, a: 4)]

  test "old palette is available when no new chunk exists":
    let source = parseAseprite(aseFile([oldPaletteChunk()]))
    check source.palette.colours.len == 256
    check source.palette.colours[0] ==
      VextRgba(r: 200, g: 201, b: 202, a: 255)
    check source.palette.colours[1] ==
      VextRgba(r: 210, g: 211, b: 212, a: 255)

  test "structural errors are rejected":
    var wrongSize = aseFile([unknownChunk()])
    wrongSize[0] = 1
    expect ValueError: discard parseAseprite(wrongSize)
    expect ValueError: discard parseAseprite(aseFile([unknownChunk()], 24))
    var badChunk = unknownChunk()
    badChunk.setDword(0, 100)
    expect ValueError: discard parseAseprite(aseFile([badChunk]))
