## Conversion of AngelCode BMFont text descriptors and atlas pages.

import ../archetypes/[font, raster]
import ../containers/bmfont

const
  BmFontResourceTypeId* = "bitmap-font.bmfont-font"
  BmFontResourcePath* = "/font"

proc decodeBmFont*(source: BmFontSource,
    pages: openArray[VextTrueColourImage]): VextBitmapFont =
  if source.encoding notin {bfeText, bfeBinary} or
      pages.len != source.declaredPages:
    raise newException(ValueError, "BMFont descriptor pages are incomplete")
  let normalizedLineHeight = max(source.lineHeight, source.baseline)
  result = VextBitmapFont(name: source.face, lineHeight: normalizedLineHeight,
    baseline: source.baseline, ascent: source.baseline,
    descent: normalizedLineHeight - source.baseline)
  for character in source.characters:
    let page = pages[character.page]
    if page.width != source.scaleWidth or page.height != source.scaleHeight:
      raise newException(ValueError, "BMFont atlas dimensions disagree with common record")
    var colours = newSeq[VextRgb](character.width * character.height)
    var alpha = newSeq[uint8](colours.len)
    let maskChannel = character.channel in [1, 2, 4, 8]
    var monochrome = true
    for y in 0 ..< character.height:
      for x in 0 ..< character.width:
        let sourceOffset = (character.y + y) * page.width + character.x + x
        let destination = y * character.width + x
        colours[destination] = page.pixels[sourceOffset]
        let pageAlpha = if page.alpha.len == 0: 255'u8
          else: page.alpha[sourceOffset]
        alpha[destination] = case character.channel
          of 1: colours[destination].b
          of 2: colours[destination].g
          of 4: colours[destination].r
          of 8: pageAlpha
          else: pageAlpha
        if not maskChannel and
            colours[destination] != VextRgb(r: 255, g: 255, b: 255):
          monochrome = false
    let bitmap = if monochrome:
      VextGlyphBitmap(kind: vgbkMonochrome, width: character.width,
        height: character.height, coverage: alpha)
    else:
      VextGlyphBitmap(kind: vgbkTrueColour,
        trueColourImage: VextTrueColourImage(width: character.width,
          height: character.height, pixels: colours, alpha: alpha))
    result.glyphs.add VextBitmapGlyph(sourceIndex: character.id,
      bitmap: bitmap, bearingX: character.xOffset,
      bearingY: source.baseline - character.yOffset,
      advanceX: character.xAdvance)
    if source.unicode == 1 or character.id in 32 .. 127:
      result.mappings.add VextGlyphMapping(codePoint: character.id,
        glyphIndex: result.glyphs.high)
  for pair in source.kernings:
    if result.glyphIndexFor(pair.first) >= 0 and
        result.glyphIndexFor(pair.second) >= 0:
      result.kerning.add VextFontKerning(leftCodePoint: pair.first,
        rightCodePoint: pair.second, amountX: pair.amount)
  result.validate
