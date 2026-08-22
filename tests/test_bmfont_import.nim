import std/[strutils, unittest]
import vexterlib

proc mono(width, height: int, coverage: seq[uint8]): VextGlyphBitmap =
  VextGlyphBitmap(kind: vgbkMonochrome, width: width, height: height,
    coverage: coverage)

proc bytes(text: string): seq[byte] =
  for value in text: result.add byte(value)

proc imported(exported: VextArtifactSet): VextInspection =
  let descriptor = exported.artifacts[0].data
  let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
    for artifact in exported.artifacts:
      if artifact.suggestedFilename == path: return artifact.data
  inspectSource(exported.artifacts[0].suggestedFilename, descriptor,
    companionResolver = resolver)

suite "BMFont import":
  test "text descriptors and PNG pages reconstruct generic font metrics":
    let source = VextBitmapFont(name: "Round trip", lineHeight: 5, baseline: 3,
      ascent: 3, descent: 2,
      glyphs: @[
        VextBitmapGlyph(sourceIndex: 65, bitmap: mono(2, 2,
          @[255'u8, 0, 128, 255]), bearingX: -1, bearingY: 2, advanceX: 3),
        VextBitmapGlyph(sourceIndex: 66, bitmap: VextGlyphBitmap(
          kind: vgbkTrueColour,
          trueColourImage: VextTrueColourImage(width: 1, height: 1,
            pixels: @[VextRgb(r: 7, g: 8, b: 9)], alpha: @[64'u8])),
          bearingX: 1, bearingY: 3, advanceX: 2)],
      mappings: @[
        VextGlyphMapping(codePoint: 65, glyphIndex: 0),
        VextGlyphMapping(codePoint: 66, glyphIndex: 1)],
      kerning: @[VextFontKerning(leftCodePoint: 65, rightCodePoint: 66,
        amountX: -1)])
    let inspection = imported(exportBmFont(source, "roundtrip", 16))
    check inspection.selectedFormat.typeId == BmFontTypeId
    let font = inspection.resources.findFontResource(BmFontResourcePath).font
    check font.name == "Round trip"
    check font.lineHeight == 5
    check font.baseline == 3
    check font.glyphs[0].bearingX == -1
    check font.glyphs[0].bearingY == 2
    check font.glyphs[0].advanceX == 3
    check font.glyphs[0].bitmap.kind == vgbkMonochrome
    check font.glyphs[0].bitmap.coverage == @[255'u8, 0, 128, 255]
    check font.glyphs[1].bitmap.kind == vgbkTrueColour
    check font.glyphs[1].bitmap.trueColourImage.pixels[0] ==
      VextRgb(r: 7, g: 8, b: 9)
    check font.glyphs[1].bitmap.trueColourImage.alpha == @[64'u8]
    check font.kerningFor(65, 66) == (-1, 0)

  test "multiple atlas pages are resolved by declared page ID":
    var source = VextBitmapFont(name: "pages", lineHeight: 4, baseline: 3)
    for index in 0 ..< 5:
      source.glyphs.add VextBitmapGlyph(sourceIndex: 65 + index,
        bitmap: mono(3, 3, newSeq[uint8](9)), advanceX: 3)
      source.mappings.add VextGlyphMapping(codePoint: 65 + index,
        glyphIndex: index)
    let exported = exportBmFont(source, "pages", 8)
    check exported.artifacts.len > 2
    let font = imported(exported).resources.findFontResource("/font").font
    check font.glyphs.len == 5
    check font.mappings.len == 5

  test "an explicitly selected colour channel becomes mono coverage":
    let descriptor = BmFontSource(encoding: bfeText, face: "mask",
      lineHeight: 1, baseline: 1, scaleWidth: 2, scaleHeight: 1,
      declaredPages: 1, pages: @[BmFontPage(id: 0, filename: "mask.png")],
      declaredCharacters: 1, characters: @[BmFontCharacter(id: 65,
        x: 0, y: 0, width: 2, height: 1, xAdvance: 2, page: 0,
        channel: 4)])
    let page = VextTrueColourImage(width: 2, height: 1,
      pixels: @[VextRgb(r: 32, g: 200, b: 100),
        VextRgb(r: 240, g: 1, b: 2)])
    let font = decodeBmFont(descriptor, @[page])
    check font.glyphs[0].bitmap.kind == vgbkMonochrome
    check font.glyphs[0].bitmap.coverage == @[32'u8, 240]

  test "a baseline beyond declared lineHeight normalizes the generic line box":
    let text = "info face=\"real-world\" size=32\n" &
      "common lineHeight=19 base=20 scaleW=1 scaleH=1 pages=1 packed=0\n" &
      "page id=0 file=\"page.png\"\nchars count=1\n" &
      "char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 " &
      "xadvance=1 page=0 chnl=0\nkernings count=0\n"
    let descriptor = parseBmFont(text.bytes)
    check descriptor.lineHeight == 19
    check descriptor.baseline == 20
    let font = decodeBmFont(descriptor, @[VextTrueColourImage(width: 1,
      height: 1, pixels: @[VextRgb(r: 255, g: 255, b: 255)],
      alpha: @[255'u8])])
    check font.lineHeight == 20
    check font.baseline == 20

  test "style metadata is retained and non-Unicode IDs are not invented mappings":
    let text = "info face=\"legacy\" size=12 bold=1 italic=1 charset=\"OEM\" " &
      "unicode=0 stretchH=125 smooth=1 aa=2 padding=1,2,3,4 " &
      "spacing=5,6 outline=2\n" &
      "common lineHeight=2 base=1 scaleW=2 scaleH=1 pages=1 packed=1 " &
      "alphaChnl=1 redChnl=2 greenChnl=3 blueChnl=4\n" &
      "page id=0 file=\"page.png\"\nchars count=2\n" &
      "char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 " &
      "xadvance=1 page=0 chnl=15\n" &
      "char id=200 x=1 y=0 width=1 height=1 xoffset=0 yoffset=0 " &
      "xadvance=1 page=0 chnl=15\nkernings count=1\n" &
      "kerning first=65 second=200 amount=-1\n"
    let descriptor = parseBmFont(text.bytes)
    check descriptor.charset == "OEM"
    check descriptor.bold == 1
    check descriptor.italic == 1
    check descriptor.stretchHeight == 125
    check descriptor.padding == [1, 2, 3, 4]
    check descriptor.spacing == [5, 6]
    check descriptor.outline == 2
    check descriptor.packed == 1
    check descriptor.alphaChannel == 1
    check descriptor.redChannel == 2
    check descriptor.greenChannel == 3
    check descriptor.blueChannel == 4
    let page = VextTrueColourImage(width: 2, height: 1,
      pixels: @[VextRgb(r: 255, g: 255, b: 255),
        VextRgb(r: 255, g: 255, b: 255)])
    let font = decodeBmFont(descriptor, @[page])
    check font.glyphs.len == 2
    check font.glyphs[1].sourceIndex == 200
    check font.mappings == @[VextGlyphMapping(codePoint: 65, glyphIndex: 0)]
    check font.kerning.len == 0

    let unicodeDescriptor = parseBmFont(text.replace("unicode=0",
      "unicode=1").bytes)
    let unicodeFont = decodeBmFont(unicodeDescriptor, @[page])
    check unicodeFont.mappings.len == 2
    check unicodeFont.kerning.len == 1

  test "XML and binary variants are distinguished and retained opaque":
    for control in ["<?xml version=\"1.0\"?><font></font>", "BMF\x03"]:
      let data = control.bytes
      let inspection = inspectSource("control.fnt", data)
      check inspection.selectedFormat.typeId == BmFontTypeId
      check inspection.resources.leafResources[0].kind == vrnkOpaque
      check inspection.resources.leafResources[0].data == data

  test "count discrepancies are retained while structural faults are rejected":
    let valid = "info face=\"x\" size=8\n" &
      "common lineHeight=8 base=7 scaleW=8 scaleH=8 pages=1 packed=0\n" &
      "page id=0 file=\"page.png\"\nchars count=1\n" &
      "char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 " &
      "xadvance=1 page=0 chnl=15\nkernings count=0\n"
    let badCount = parseBmFont(valid.replace("chars count=1",
      "chars count=2").bytes)
    check badCount.declaredCharacters == 2
    check badCount.characters.len == 1
    let unsafe = valid.replace("page.png", "../page.png")
    let unsafeBytes = unsafe.bytes
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] = @[]
    expect ValueError:
      discard inspectSource("unsafe.fnt", unsafeBytes,
        companionResolver = resolver)
