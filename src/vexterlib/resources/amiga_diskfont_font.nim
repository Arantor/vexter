## Conversion of Amiga diskfont strikes to the generic bitmap-font model.

import ../archetypes/[font, raster]
import ../containers/amiga_diskfont

const
  AmigaDiskfontResourceTypeId* = "amiga.bitmap-diskfont-font"
  AmigaDiskfontResourcePath* = "/font"

proc decodeAmigaDiskfont*(source: AmigaDiskfontSource): VextBitmapFont =
  result = VextBitmapFont(name: source.name, lineHeight: source.ySize,
    baseline: source.baseline + 1, ascent: source.baseline + 1,
    descent: source.ySize - source.baseline - 1)
  var pickedBits: seq[int]
  for bit in 0 .. 7:
    if (source.planePick and (1 shl bit)) != 0: pickedBits.add bit
  for glyphSource in source.glyphs:
    var glyph = VextBitmapGlyph(sourceIndex: glyphSource.sourceIndex,
      bearingX: glyphSource.kern, bearingY: source.baseline + 1,
      advanceX: glyphSource.spacing)
    if source.depth == 1 and (source.style and FsfColorFont) == 0:
      var coverage = newSeq[uint8](glyphSource.width * source.ySize)
      for y in 0 ..< source.ySize:
        for x in 0 ..< glyphSource.width:
          let bit = glyphSource.bitOffset + x
          if (source.planes[0][y * source.modulo + bit div 8] and
              byte(0x80 shr (bit mod 8))) != 0:
            coverage[y * glyphSource.width + x] = 255
      glyph.bitmap = VextGlyphBitmap(kind: vgbkMonochrome,
        width: glyphSource.width, height: source.ySize, coverage: coverage)
    else:
      var palette: seq[VextRgb]
      for packed in source.palette:
        palette.add VextRgb(r: uint8((packed shr 8) and 0xf) * 17,
          g: uint8((packed shr 4) and 0xf) * 17,
          b: uint8(packed and 0xf) * 17)
      var pixels = newSeq[uint8](glyphSource.width * source.ySize)
      var alpha = newSeq[uint8](pixels.len)
      for y in 0 ..< source.ySize:
        for x in 0 ..< glyphSource.width:
          let sourceBit = glyphSource.bitOffset + x
          var colour = source.planeOnOff
          for plane in 0 ..< source.depth:
            if plane >= pickedBits.len: break
            if (source.planes[plane][y * source.modulo + sourceBit div 8] and
                byte(0x80 shr (sourceBit mod 8))) != 0:
              colour = colour or (1 shl pickedBits[plane])
            else:
              colour = colour and not (1 shl pickedBits[plane])
          if colour >= palette.len:
            raise newException(ValueError,
              "Amiga ColorFont pixel references a missing palette colour")
          let destination = y * glyphSource.width + x
          pixels[destination] = uint8(colour)
          alpha[destination] = if colour == 0: 0 else: 255
      glyph.bitmap = VextGlyphBitmap(kind: vgbkIndexed,
        indexedImage: VextIndexedImage(width: glyphSource.width,
          height: source.ySize, palette: palette, pixels: pixels, alpha: alpha))
    result.glyphs.add glyph
    # Diskfonts carry byte positions, not a declared Unicode encoding. Apply
    # the project-wide printable-ASCII default and retain every other position
    # solely as a source index until an explicit mapping is available.
    if glyphSource.sourceIndex >= 32 and glyphSource.sourceIndex <= 127 and
        glyphSource.sourceIndex <= source.highCharacter:
      result.mappings.add VextGlyphMapping(codePoint: glyphSource.sourceIndex,
        glyphIndex: result.glyphs.high)
  result.validate
