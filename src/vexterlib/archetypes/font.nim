## Generic bitmap-font values, independent of any source or export format.

import std/unicode
import ./raster

type
  VextGlyphBitmapKind* = enum
    vgbkMonochrome
    vgbkIndexed
    vgbkTrueColour

  VextGlyphBitmap* = object
    case kind*: VextGlyphBitmapKind
    of vgbkMonochrome:
      width*, height*: int
      coverage*: seq[uint8]
    of vgbkIndexed:
      indexedImage*: VextIndexedImage
    of vgbkTrueColour:
      trueColourImage*: VextTrueColourImage

  VextBitmapGlyph* = object
    name*: string
    sourceIndex*: int
    bitmap*: VextGlyphBitmap
    bearingX*, bearingY*: int
    advanceX*, advanceY*: int

  VextGlyphMapping* = object
    codePoint*: int
    glyphIndex*: int

  VextFontKerning* = object
    leftCodePoint*, rightCodePoint*: int
    amountX*, amountY*: int

  VextFontSubstitution* = object
    sourceCodePoint*, replacementCodePoint*: int

  VextFontLigature* = object
    components*: seq[int]
    glyphIndex*: int

  VextBitmapFont* = object
    name*: string
    glyphs*: seq[VextBitmapGlyph]
    mappings*: seq[VextGlyphMapping]
    lineHeight*: int
    baseline*: int
    ascent*, descent*, leading*: int
    fallbackCodePoint*: int
    kerning*: seq[VextFontKerning]
    substitutions*: seq[VextFontSubstitution]
    ligatures*: seq[VextFontLigature]

  VextGlyphRunItem* = object
    glyphIndex*: int
    firstCodePoint*, lastCodePoint*: int

proc defaultGlyphMappings*(glyphCount: int, firstCodePoint = 32,
    lastCodePoint = 127): seq[VextGlyphMapping] =
  ## Supplies the conventional mapping only when a source format has none.
  if glyphCount < 0 or firstCodePoint < 0 or lastCodePoint < firstCodePoint:
    raise newException(ValueError, "invalid default glyph mapping range")
  for index in 0 ..< min(glyphCount, lastCodePoint - firstCodePoint + 1):
    result.add VextGlyphMapping(codePoint: firstCodePoint + index,
      glyphIndex: index)

proc width*(bitmap: VextGlyphBitmap): int =
  case bitmap.kind
  of vgbkMonochrome: bitmap.width
  of vgbkIndexed: bitmap.indexedImage.width
  of vgbkTrueColour: bitmap.trueColourImage.width

proc height*(bitmap: VextGlyphBitmap): int =
  case bitmap.kind
  of vgbkMonochrome: bitmap.height
  of vgbkIndexed: bitmap.indexedImage.height
  of vgbkTrueColour: bitmap.trueColourImage.height

proc validate*(font: VextBitmapFont) =
  if font.lineHeight <= 0 or font.baseline < 0 or
      font.baseline > font.lineHeight:
    raise newException(ValueError, "bitmap font has invalid line metrics")
  for glyph in font.glyphs:
    let width = width(glyph.bitmap)
    let height = height(glyph.bitmap)
    if width < 0 or height < 0:
      raise newException(ValueError, "bitmap glyph dimensions cannot be negative")
    case glyph.bitmap.kind
    of vgbkMonochrome:
      if glyph.bitmap.coverage.len != width * height:
        raise newException(ValueError, "monochrome glyph coverage has the wrong length")
    of vgbkIndexed:
      if glyph.bitmap.indexedImage.pixels.len != width * height or
          glyph.bitmap.indexedImage.palette.len == 0:
        raise newException(ValueError, "indexed glyph bitmap is invalid")
      discard glyph.bitmap.indexedImage.hasAlpha
    of vgbkTrueColour:
      if glyph.bitmap.trueColourImage.pixels.len != width * height:
        raise newException(ValueError, "true-colour glyph bitmap is invalid")
      discard glyph.bitmap.trueColourImage.hasAlpha
  var mapped: seq[int]
  for mapping in font.mappings:
    if mapping.codePoint < 0 or mapping.codePoint > 0x10ffff or
        mapping.codePoint in 0xd800 .. 0xdfff:
      raise newException(ValueError, "font mapping is not a Unicode scalar value")
    if mapping.glyphIndex < 0 or mapping.glyphIndex >= font.glyphs.len:
      raise newException(ValueError, "font mapping references a missing glyph")
    if mapping.codePoint in mapped:
      raise newException(ValueError, "font contains a duplicate character mapping")
    mapped.add mapping.codePoint
  if font.fallbackCodePoint != 0 and font.fallbackCodePoint notin mapped:
    raise newException(ValueError,
      "font fallback character does not have a mapping")
  for pair in font.kerning:
    if pair.leftCodePoint notin mapped or pair.rightCodePoint notin mapped:
      raise newException(ValueError, "font kerning references an unmapped character")
  for substitution in font.substitutions:
    if substitution.sourceCodePoint < 0 or substitution.sourceCodePoint > 0x10ffff or
        substitution.replacementCodePoint notin mapped:
      raise newException(ValueError, "font substitution is invalid")
  for ligature in font.ligatures:
    if ligature.components.len < 2 or ligature.glyphIndex < 0 or
        ligature.glyphIndex >= font.glyphs.len:
      raise newException(ValueError, "font ligature is invalid")
    for component in ligature.components:
      if component < 0 or component > 0x10ffff or
          component in 0xd800 .. 0xdfff:
        raise newException(ValueError,
          "font ligature contains a non-Unicode component")

proc glyphIndexFor*(font: VextBitmapFont, codePoint: int): int =
  for mapping in font.mappings:
    if mapping.codePoint == codePoint:
      return mapping.glyphIndex
  for substitution in font.substitutions:
    if substitution.sourceCodePoint == codePoint:
      for mapping in font.mappings:
        if mapping.codePoint == substitution.replacementCodePoint:
          return mapping.glyphIndex
  if font.fallbackCodePoint != 0:
    for mapping in font.mappings:
      if mapping.codePoint == font.fallbackCodePoint:
        return mapping.glyphIndex
  -1

proc kerningFor*(font: VextBitmapFont, left, right: int): tuple[x, y: int] =
  for pair in font.kerning:
    if pair.leftCodePoint == left and pair.rightCodePoint == right:
      return (pair.amountX, pair.amountY)

proc glyphRun*(font: VextBitmapFont, text: string): seq[VextGlyphRunItem] =
  ## Applies longest-match ligatures before ordinary mappings/substitutions.
  let codePoints = text.toRunes
  var offset = 0
  while offset < codePoints.len:
    if int(codePoints[offset]) == 10:
      result.add VextGlyphRunItem(glyphIndex: -1, firstCodePoint: 10,
        lastCodePoint: 10)
      inc offset
      continue
    var selected = -1
    var selectedLength = 0
    for ligature in font.ligatures:
      if ligature.components.len <= selectedLength or
          ligature.components.len > codePoints.len - offset: continue
      var matches = true
      for index, component in ligature.components:
        if int(codePoints[offset + index]) != component:
          matches = false
          break
      if matches:
        selected = ligature.glyphIndex
        selectedLength = ligature.components.len
    if selected >= 0:
      result.add VextGlyphRunItem(glyphIndex: selected,
        firstCodePoint: int(codePoints[offset]),
        lastCodePoint: int(codePoints[offset + selectedLength - 1]))
      offset += selectedLength
    else:
      let codePoint = int(codePoints[offset])
      var resolvedCodePoint = codePoint
      var glyphIndex = -1
      for mapping in font.mappings:
        if mapping.codePoint == codePoint:
          glyphIndex = mapping.glyphIndex
          break
      if glyphIndex < 0:
        for substitution in font.substitutions:
          if substitution.sourceCodePoint == codePoint:
            resolvedCodePoint = substitution.replacementCodePoint
            glyphIndex = font.glyphIndexFor(resolvedCodePoint)
            break
      if glyphIndex < 0 and font.fallbackCodePoint != 0:
        resolvedCodePoint = font.fallbackCodePoint
        glyphIndex = font.glyphIndexFor(resolvedCodePoint)
      if glyphIndex >= 0:
        result.add VextGlyphRunItem(glyphIndex: glyphIndex,
          firstCodePoint: resolvedCodePoint, lastCodePoint: resolvedCodePoint)
      inc offset

proc rgbaAt*(bitmap: VextGlyphBitmap, x, y: int): VextRgba =
  if x < 0 or x >= width(bitmap) or y < 0 or y >= height(bitmap):
    raise newException(IndexDefect, "glyph coordinate is out of bounds")
  case bitmap.kind
  of vgbkMonochrome:
    VextRgba(r: 255, g: 255, b: 255,
      a: bitmap.coverage[y * width(bitmap) + x])
  of vgbkIndexed: bitmap.indexedImage.rgbaAt(x, y)
  of vgbkTrueColour: bitmap.trueColourImage.rgbaAt(x, y)

proc defaultPreviewText*(font: VextBitmapFont): string =
  ## Produces a stable readable sample from mappings, including non-ASCII text.
  const
    MixedSample = "The quick brown fox jumps over the lazy dog 0123456789"
    UpperSample = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789"
    LowerSample = "the quick brown fox jumps over the lazy dog 0123456789"
    NeutralSample = "0123456789"
  proc hasPreviewGlyph(codePoint: int): bool =
    # Do not let the font fallback make every character appear supported.
    for mapping in font.mappings:
      if mapping.codePoint == codePoint: return true
    for substitution in font.substitutions:
      if substitution.sourceCodePoint == codePoint:
        for mapping in font.mappings:
          if mapping.codePoint == substitution.replacementCodePoint:
            return true
    false
  var upperCount, lowerCount: int
  for codePoint in ord('A') .. ord('Z'):
    if hasPreviewGlyph(codePoint): inc upperCount
  for codePoint in ord('a') .. ord('z'):
    if hasPreviewGlyph(codePoint): inc lowerCount
  const SubstantialAlphabet = 13
  let hasUpper = upperCount >= SubstantialAlphabet
  let hasLower = lowerCount >= SubstantialAlphabet
  let preferred =
    if hasUpper and not hasLower: UpperSample
    elif hasLower and not hasUpper: LowerSample
    elif hasUpper and hasLower: MixedSample
    elif upperCount > lowerCount: UpperSample
    elif lowerCount > upperCount: LowerSample
    elif upperCount > 0: MixedSample
    else: NeutralSample
  for rune in preferred.runes:
    if hasPreviewGlyph(int(rune)):
      result.add rune.toUTF8
  result = result.strip
  if result.len == 0:
    for mapping in font.mappings:
      if mapping.codePoint >= 32 and mapping.codePoint != 127:
        result.add Rune(mapping.codePoint).toUTF8
      if result.runeLen >= 96: break
