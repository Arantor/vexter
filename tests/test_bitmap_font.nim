import std/[strutils, unittest]
import vexterlib

proc asString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc mono(width, height: int, coverage: seq[uint8]): VextGlyphBitmap =
  VextGlyphBitmap(kind: vgbkMonochrome, width: width, height: height,
    coverage: coverage)

proc sampleFont(): VextBitmapFont =
  VextBitmapFont(name: "Test \"Face\"", lineHeight: 6, baseline: 4,
    ascent: 4, descent: 2, fallbackCodePoint: 63,
    glyphs: @[
      VextBitmapGlyph(name: "A", bitmap: mono(2, 3,
        @[255'u8, 0, 128, 255, 255, 255]), bearingX: -1, bearingY: 3,
        advanceX: 3),
      VextBitmapGlyph(name: "space", bitmap: mono(0, 0, @[]), advanceX: 2),
      VextBitmapGlyph(name: "question", bitmap: mono(1, 1, @[255'u8]),
        bearingY: 1, advanceX: 2),
      VextBitmapGlyph(name: "AA", bitmap: mono(3, 1,
        @[255'u8, 255, 255]), bearingY: 1, advanceX: 4)],
    mappings: @[
      VextGlyphMapping(codePoint: 65, glyphIndex: 0),
      VextGlyphMapping(codePoint: 32, glyphIndex: 1),
      VextGlyphMapping(codePoint: 63, glyphIndex: 2),
      VextGlyphMapping(codePoint: 0x2603, glyphIndex: 0)],
    kerning: @[VextFontKerning(leftCodePoint: 65, rightCodePoint: 65,
      amountX: -1, amountY: 2)],
    substitutions: @[VextFontSubstitution(sourceCodePoint: 97,
      replacementCodePoint: 65)],
    ligatures: @[VextFontLigature(components: @[65, 65], glyphIndex: 3)])

suite "generic bitmap fonts and BMFont export":
  test "default mappings are conventional but bounded by available glyphs":
    let mappings = defaultGlyphMappings(3)
    check mappings == @[
      VextGlyphMapping(codePoint: 32, glyphIndex: 0),
      VextGlyphMapping(codePoint: 33, glyphIndex: 1),
      VextGlyphMapping(codePoint: 34, glyphIndex: 2)]

  test "font validation preserves mappings outside ASCII and rich features":
    let font = sampleFont()
    font.validate
    check font.glyphIndexFor(0x2603) == 0
    check font.glyphIndexFor(97) == 0
    check font.glyphIndexFor(0x9999) == 2
    check font.kerningFor(65, 65) == (-1, 2)
    let run = font.glyphRun("AAa")
    check run.len == 2
    check run[0].glyphIndex == 3
    check run[1].glyphIndex == 0

  test "BMFont exports metrics, Unicode aliases, kerning, and white-alpha PNG":
    let exported = exportBmFont(sampleFont(), "sample", 16)
    check exported.artifacts.len == 2
    check exported.artifacts[0].suggestedFilename == "sample.fnt"
    check exported.artifacts[1].suggestedFilename == "sample-0.png"
    let descriptor = exported.artifacts[0].data.asString
    check "face=\"Test \\\"Face\\\"\"" in descriptor
    check "common lineHeight=6 base=4 scaleW=16" in descriptor
    check "chars count=4" in descriptor
    check "char id=65 " in descriptor
    check "char id=9731 " in descriptor
    check "xoffset=-1 yoffset=1 xadvance=3" in descriptor
    check "kernings count=1" in descriptor
    check "kerning first=65 second=65 amount=-1" in descriptor
    let atlas = decodePng(parsePng(exported.artifacts[1].data)).trueColourImage
    check atlas.width == 16
    check atlas.rgbaAt(1, 1) == VextRgba(r: 255, g: 255, b: 255, a: 255)
    check atlas.rgbaAt(2, 1) == VextRgba(r: 255, g: 255, b: 255, a: 0)
    check atlas.rgbaAt(1, 2) == VextRgba(r: 255, g: 255, b: 255, a: 128)

  test "small atlases spill to consistently sized multiple pages":
    var font = VextBitmapFont(name: "pages", lineHeight: 4, baseline: 3)
    for index in 0 ..< 5:
      font.glyphs.add VextBitmapGlyph(bitmap: mono(3, 3,
        newSeq[uint8](9)), advanceX: 3)
      font.mappings.add VextGlyphMapping(codePoint: 32 + index,
        glyphIndex: index)
    let exported = exportBmFont(font, "pages", 8)
    check exported.artifacts.len > 2
    let descriptor = exported.artifacts[0].data.asString
    check "pages=" & $(exported.artifacts.len - 1) in descriptor
    var height = 0
    for artifact in exported.artifacts[1 .. ^1]:
      let page = parsePng(artifact.data)
      if height == 0: height = page.height
      check page.width == 8
      check page.height == height

  test "coloured glyphs retain RGB and alpha in the atlas":
    let font = VextBitmapFont(name: "colour", lineHeight: 2, baseline: 1,
      glyphs: @[VextBitmapGlyph(bitmap: VextGlyphBitmap(
        kind: vgbkTrueColour,
        trueColourImage: VextTrueColourImage(width: 1, height: 1,
          pixels: @[VextRgb(r: 7, g: 8, b: 9)], alpha: @[64'u8])),
        bearingY: 1, advanceX: 1)],
      mappings: @[VextGlyphMapping(codePoint: 65, glyphIndex: 0)])
    let atlas = decodePng(parsePng(exportBmFont(font, "colour", 8).
      artifacts[1].data)).trueColourImage
    check atlas.rgbaAt(1, 1) == VextRgba(r: 7, g: 8, b: 9, a: 64)

  test "preview uses ligatures, substitutions, metrics, and wrapping":
    let font = sampleFont()
    let ligature = renderBitmapFontText(font, "AA", 20)
    check ligature.width == 4
    check ligature.height == 6
    check ligature.alphaAt(0, 3) == 255
    let wrapped = renderBitmapFontText(font, "A A", 4)
    check wrapped.height > font.lineHeight
    let substituted = renderBitmapFontText(font, "a", 20)
    check substituted.alphaAt(0, 2) == 255

  test "default preview follows the font's available letter case":
    proc caseFont(first, last: int): VextBitmapFont =
      result = VextBitmapFont(lineHeight: 1, baseline: 1,
        glyphs: @[VextBitmapGlyph(bitmap: mono(0, 0, @[]), advanceX: 1)])
      result.mappings.add VextGlyphMapping(codePoint: 32, glyphIndex: 0)
      for codePoint in first .. last:
        result.mappings.add VextGlyphMapping(codePoint: codePoint, glyphIndex: 0)
    let uppercase = caseFont(ord('A'), ord('Z')).defaultPreviewText
    check uppercase == "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
    check uppercase.find({'a'..'z'}) < 0
    let lowercase = caseFont(ord('a'), ord('z')).defaultPreviewText
    check lowercase == "the quick brown fox jumps over the lazy dog"
    check lowercase.find({'A'..'Z'}) < 0

    var uppercaseWithLowercaseOutlier = caseFont(ord('A'), ord('Z'))
    uppercaseWithLowercaseOutlier.mappings.add VextGlyphMapping(
      codePoint: ord('x'), glyphIndex: 0)
    let outlierPreview = uppercaseWithLowercaseOutlier.defaultPreviewText
    check outlierPreview == "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
    check 'x' notin outlierPreview

    let halfUppercase = caseFont(ord('A'), ord('M')).defaultPreviewText
    check halfUppercase.find({'a'..'z'}) < 0

  test "glyph grid exposes every glyph with guides and selection":
    let grid = renderBitmapFontGlyphGrid(sampleFont(), 40, 0)
    check grid.width > 0
    check grid.height >= sampleFont().lineHeight
    var selectionPixels, guidePixels: int
    for index, colour in grid.pixels:
      if grid.alpha[index] == 0: continue
      if colour == VextRgb(r: 255, g: 200, b: 20): inc selectionPixels
      if colour == VextRgb(r: 40, g: 160, b: 255): inc guidePixels
    check selectionPixels > 0
    check guidePixels > 0

  test "font resources naturally export compound BMFont artifacts":
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/font",
      typeId: "test.font", kind: vrnkFont, font: sampleFont())])
    check tree.fontResources.len == 1
    check tree.findFontResource("/font") == tree.roots[0]
    check tree.roots[0].defaultExportFormat == "bmfont"
    let exported = exportResource(tree, VextExportRequest(suggestedName: "font"))
    check exported.outputFormat == "bmfont"
    check exported.artifacts.artifacts.len == 2

    let collisions = VextResourceTree(roots: @[
      VextResourceNode(path: "/x:y", kind: vrnkFont, font: sampleFont()),
      VextResourceNode(path: "/x?y", kind: vrnkFont, font: sampleFont())])
    let bulk = exportAllResources(collisions, VextExportAllRequest())
    check bulk.exports[0].artifacts.artifacts[0].suggestedFilename == "x_y.fnt"
    check bulk.exports[1].artifacts.artifacts[0].suggestedFilename == "x_y-2.fnt"
    check "file=\"x_y-2-0.png\"" in
      bulk.exports[1].artifacts.artifacts[0].data.asString
    check bulk.exports[1].artifacts.artifacts[1].suggestedFilename ==
      "x_y-2-0.png"

  test "invalid mappings and bitmap buffers fail before export":
    var bad = sampleFont()
    bad.mappings.add VextGlyphMapping(codePoint: 65, glyphIndex: 2)
    expect ValueError: bad.validate
    bad = sampleFont()
    bad.glyphs[0].bitmap.coverage.setLen(1)
    expect ValueError: discard exportBmFont(bad)
