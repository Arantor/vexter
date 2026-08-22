## Conversion of FZX character definitions to the generic bitmap-font model.

import ../archetypes/font
import ../containers/fzx

const
  FzxFontResourceTypeId* = "zx-spectrum.fzx-bitmap-font"
  FzxFontResourcePath* = "/font"

proc decodeFzx*(source: FzxFontSource, name = "FZX font"): VextBitmapFont =
  result = VextBitmapFont(name: name, lineHeight: source.height,
    baseline: source.height, ascent: source.height)
  for glyphSource in source.glyphs:
    var coverage = newSeq[uint8](glyphSource.width * glyphSource.rowCount)
    let rowBytes = if glyphSource.width <= 8: 1 else: 2
    for y in 0 ..< glyphSource.rowCount:
      for x in 0 ..< glyphSource.width:
        let value = glyphSource.bitmap[y * rowBytes + x div 8]
        if (value and byte(0x80 shr (x mod 8))) != 0:
          coverage[y * glyphSource.width + x] = 255
    result.glyphs.add VextBitmapGlyph(
      sourceIndex: glyphSource.characterCode,
      bitmap: VextGlyphBitmap(kind: vgbkMonochrome,
        width: glyphSource.width, height: glyphSource.rowCount,
        coverage: coverage),
      bearingX: -glyphSource.kern,
      bearingY: source.height - glyphSource.shift,
      advanceX: glyphSource.width + source.tracking - glyphSource.kern)
    # FZX carries character positions rather than a Unicode mapping. Preserve
    # the conventional printable ASCII positions as the documented default;
    # extended/custom positions remain available through glyph.sourceIndex.
    if glyphSource.characterCode <= 127:
      result.mappings.add VextGlyphMapping(
        codePoint: glyphSource.characterCode,
        glyphIndex: result.glyphs.high)
  var maximumBottom = source.height
  for glyphSource in source.glyphs:
    maximumBottom = max(maximumBottom,
      glyphSource.shift + glyphSource.rowCount)
  result.descent = maximumBottom - source.height
  result.validate
