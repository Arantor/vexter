import std/unittest
import vexterlib

proc emptyFzx(lastCharacter: int): seq[byte] =
  let count = lastCharacter - 31
  let tableEnd = 3 + count * 3 + 2
  result = @[9'u8, 2, byte(lastCharacter)]
  for index in 0 ..< count:
    let entryOffset = 3 + index * 3
    let relative = tableEnd - entryOffset
    result.add byte(relative)
    result.add byte(relative shr 8)
    result.add 5 # shift 0, width 6
  result.add 2; result.add 0

proc sampleFzx(): seq[byte] =
  const lastCharacter = 59
  let count = lastCharacter - 31
  let tableEnd = 3 + count * 3 + 2
  var bitmaps: seq[byte]
  result = @[9'u8, 2, lastCharacter]
  for index in 0 ..< count:
    let code = index + 32
    let entryOffset = 3 + index * 3
    let definitionOffset = tableEnd + bitmaps.len
    let kern = if code == 59: 1 else: 0
    let relative = definitionOffset - entryOffset
    let packed = relative or (kern shl 14)
    result.add byte(packed); result.add byte(packed shr 8)
    if code == 33:
      result.add 0x10 # shift 1, width 1
      bitmaps.add @[0x80'u8, 0x80, 0x80, 0x80, 0, 0x80]
    elif code == 59:
      result.add 0x31 # shift 3, width 2
      bitmaps.add @[0x80'u8, 0x80]
    else:
      result.add 5 # shift 0, width 6, blank definition
  let terminalRelative = 2 + bitmaps.len
  result.add byte(terminalRelative); result.add byte(terminalRelative shr 8)
  result.add bitmaps

suite "FZX bitmap fonts":
  test "documented metrics, relative offsets, rows, and universal kern decode":
    let data = sampleFzx()
    let source = parseFzx(data)
    check source.height == 9
    check source.tracking == 2
    check source.lastCharacter == 59
    check source.glyphs.len == 28
    check source.glyphs[0].characterCode == 32
    check source.glyphs[0].width == 6
    check source.glyphs[0].rowCount == 0
    let exclamation = source.glyphs[1]
    check exclamation.shift == 1
    check exclamation.width == 1
    check exclamation.rowCount == 6
    check exclamation.bitmap == @[0x80'u8, 0x80, 0x80, 0x80, 0, 0x80]
    let semicolon = source.glyphs[59 - 32]
    check semicolon.kern == 1
    let font = decodeFzx(source, "Synthetic control")
    check font.lineHeight == 9
    check font.baseline == 9
    check font.glyphs[1].bearingY == 8
    check font.glyphs[1].advanceX == 3
    check font.glyphs[59 - 32].bearingX == -1
    check font.glyphs[59 - 32].advanceX == 3
    check font.glyphs[1].bitmap.coverage ==
      @[255'u8, 255, 255, 255, 0, 255]

  test "inspection exposes an exportable generic font and FZX metadata":
    let data = sampleFzx()
    let inspection = inspectSource("Sinclair.fzx", data)
    check inspection.selectedFormat.typeId == FzxTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    let resource = inspection.resources.findFontResource(FzxFontResourcePath)
    check resource != nil
    check resource.kind == vrnkFont
    check resource.font.glyphs.len == 28
    check resource.font.mappings.len == 28
    check resource.metadata[0].key == "height"
    check resource.metadata[0].value.integerValue == 9
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "Sinclair"))
    check exported.outputFormat == "bmfont"
    check exported.artifacts.artifacts[0].suggestedFilename == "Sinclair.fnt"
    check exported.artifacts.artifacts.len >= 2

  test "extensionless structural detection remains deliberately possible":
    let candidates = detectFormats("font.bin", emptyFzx(32))
    check candidates.len == 1
    check candidates[0].typeId == FzxTypeId
    check candidates[0].confidence == vdcPossible

  test "positions above printable ASCII remain source indices, not invented Unicode":
    let font = decodeFzx(parseFzx(emptyFzx(128)))
    check font.glyphs.len == 97
    check font.glyphs[^1].sourceIndex == 128
    check font.mappings.len == 96

  test "truncation, bad terminal offsets, reversed definitions, and partial rows fail":
    expect ValueError: discard parseFzx(@[9'u8, 2, 32])
    var terminal = emptyFzx(32)
    terminal[6] = 1
    expect ValueError: discard parseFzx(terminal)

    var reversed = emptyFzx(33)
    # Character 32 starts at table end, but character 33 starts one byte before it.
    reversed[6] = byte((reversed.len - 1) - 6)
    reversed[7] = 0
    expect ValueError: discard parseFzx(reversed)

    var partial = @[9'u8, 1, 32, 5, 0, 8, 3, 0, 0xff]
    expect ValueError: discard parseFzx(partial)
