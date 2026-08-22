import std/[sequtils, strutils, unittest]
import vexterlib

proc putWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc putLong(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc hunk(payload: seq[byte]): seq[byte] =
  let longwords = (payload.len + 3) div 4
  result = newSeq[byte](32 + longwords * 4 + 4)
  result.putLong(0, 1011)
  result.putLong(8, 1)
  result.putLong(16, 0)
  result.putLong(20, longwords)
  result.putLong(24, 1002)
  result.putLong(28, longwords)
  for index, value in payload: result[32 + index] = value
  result.putLong(32 + longwords * 4, 1010)

proc baseFontPayload(colour = false): seq[byte] =
  result = newSeq[byte](if colour: 210 else: 160)
  result[0] = 0x70; result[2] = 0x4e; result[3] = 0x75
  result.putWord(18, 0x0f80)
  result.putWord(20, 7)
  for index, value in "Test.font": result[26 + index] = byte(value)
  const tf = 58
  result.putWord(tf + 20, 2)
  result[tf + 22] = if colour: byte(FsfColorFont) else: 0
  result[tf + 23] = 0x62 # disk, proportional, designed
  result.putWord(tf + 24, 3)
  result.putWord(tf + 26, 0)
  result[tf + 32] = 65; result[tf + 33] = 66
  result.putWord(tf + 38, 2)
  result.putLong(tf + 40, 130)
  result.putLong(tf + 44, 142)
  result.putLong(tf + 48, 148)
  for index in 0 .. 2:
    result.putWord(130 + index * 4, index * 2)
    result.putWord(132 + index * 4, 2)
    result.putWord(142 + index * 2, index + 2)
    result.putWord(148 + index * 2, if index == 1: 0xffff else: 0)
  if colour:
    const ctf = tf + 52
    result.putWord(ctf, 1)
    result[ctf + 2] = 2; result[ctf + 3] = 2
    result[ctf + 4] = 0; result[ctf + 5] = 3
    result[ctf + 6] = 3
    result.putLong(ctf + 8, 160)
    result.putLong(ctf + 12, 180)
    result.putLong(ctf + 16, 184)
    result.putWord(162, 4); result.putLong(164, 168)
    result.putWord(168, 0x000); result.putWord(170, 0xf00)
    result.putWord(172, 0x0f0); result.putWord(174, 0x00f)
    result[180] = 0xa0; result[182] = 0xa0
    result[184] = 0x60; result[186] = 0x60
  else:
    result.putLong(tf + 34, 154)
    result[154] = 0xa0; result[156] = 0x60

proc fontIndex(path: string, tagged = false): seq[byte] =
  result = newSeq[byte](264)
  result.putWord(0, if tagged: 0x0f02 else: 0x0f00)
  result.putWord(2, 1)
  for index, value in path: result[4 + index] = byte(value)
  result.putWord(260, 2)
  result[262] = if tagged: byte(FsfColorFont) else: 0
  result[263] = 0x62
  if tagged:
    result.putWord(258, 2)
    result.putLong(242, 0x80000001)
    result.putLong(246, 0x00480048)
    result.putLong(250, 0)
    result.putLong(254, 0)

suite "Amiga bitmap diskfonts":
  test "monochrome strikes retain metrics and the unmapped default glyph":
    let data = hunk(baseFontPayload())
    let source = parseAmigaDiskfont(data)
    check source.name == "Test.font"
    check source.glyphs.len == 3
    check source.glyphs[1].kern == -1
    let font = decodeAmigaDiskfont(source)
    check font.lineHeight == 2
    check font.baseline == 1
    check font.glyphs.len == 3
    check font.mappings.len == 2
    check font.glyphs[1].bearingX == -1
    check font.glyphs[1].advanceX == 3
    check font.glyphs[0].bitmap.coverage == @[255'u8, 0, 0, 255]
    check detectFormats("8", data)[0].typeId == AmigaDiskfontTypeId

  test "ColorFont planes and xRGB palette become transparent indexed glyphs":
    let source = parseAmigaDiskfont(hunk(baseFontPayload(true)))
    check source.depth == 2
    check source.palette == @[0'u16, 0xf00, 0x0f0, 0x00f]
    let font = decodeAmigaDiskfont(source)
    check font.glyphs[0].bitmap.kind == vgbkIndexed
    let image = font.glyphs[0].bitmap.indexedImage
    check image.pixels == @[1'u8, 2, 1, 2]
    check image.alpha == @[255'u8, 255, 255, 255]
    check font.glyphs[2].bitmap.indexedImage.alpha == @[0'u8, 0, 0, 0]

  test "inspection exposes BMFont export and ColorFont metadata":
    let inspection = inspectSource("8C.Test", hunk(baseFontPayload(true)))
    let resource = inspection.resources.findFontResource("/font")
    check resource != nil
    check resource.font.glyphs.len == 3
    check resource.metadata[^1].key == "colour.palette-size"
    check resource.metadata[^1].value.integerValue == 4
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "Test"))
    check exported.outputFormat == "bmfont"
    check exported.artifacts.artifacts.len == 2

  test ".font indexes resolve validated size descriptors as children":
    let sizeData = hunk(baseFontPayload())
    let indexData = fontIndex("Test/2")
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      if path == "Test/2": sizeData else: @[]
    let inspection = inspectSource("Test.font", indexData,
      companionResolver = resolver)
    check inspection.selectedFormat.typeId == AmigaDiskfontIndexTypeId
    check inspection.resources.roots.len == 1
    check inspection.resources.roots[0].kind == vrnkGroup
    check inspection.resources.roots[0].children.len == 1
    check inspection.resources.roots[0].children[0].path == "/font/2"
    check inspection.resources.roots[0].children[0].kind == vrnkFont
    check inspection.warnings.len == 0

  test "tagged indexes retain tags and invalid companions become warnings":
    let tagged = parseAmigaDiskfontIndex(fontIndex("Colour/2", true))
    check tagged.tagged
    check tagged.entries[0].tags.len == 2
    check tagged.entries[0].tags[0].identifier == 0x80000001'u32
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      hunk(baseFontPayload())
    let inspection = inspectSource("Colour.font",
      fontIndex("Colour/2", true), companionResolver = resolver)
    check inspection.resources.roots[0].children.len == 0
    check inspection.warnings.len == 1
    check "do not match" in inspection.warnings[0].message

  test "tagged device DPI and Amiga path separators reach child metadata":
    let sizeData = hunk(baseFontPayload(true))
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      if path == "Test/2": sizeData else: @[]
    let inspection = inspectSource("Test.font", fontIndex("Test\\2", true),
      companionResolver = resolver)
    check inspection.warnings.len == 0
    check inspection.resources.roots[0].children.len == 1
    let group = inspection.resources.roots[0]
    let font = group.children[0]
    check group.metadata.anyIt(it.key == "index.entry.0.dpi.x" and
      it.value.integerValue == 72)
    check group.metadata.anyIt(it.key == "index.entry.0.dpi.y" and
      it.value.integerValue == 72)
    check font.metadata.anyIt(it.key == "index.filename" and
      it.value.stringValue == "Test\\2")
    check font.metadata.anyIt(it.key == "dpi.x" and
      it.value.integerValue == 72)
    check font.metadata.anyIt(it.key == "dpi.y" and
      it.value.integerValue == 72)

  test "unsafe and missing companion paths never become resources":
    var called = false
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      called = true
      @[]
    let inspection = inspectSource("Bad.font", fontIndex("../escape"),
      companionResolver = resolver)
    check not called
    check inspection.resources.fontResources.len == 0
    check inspection.warnings.len == 1
