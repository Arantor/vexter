## Metric-aware, wrapping bitmap-font rendering used by frontends.

import ../archetypes/[font, raster]

proc blend(destination: var VextTrueColourImage, x, y: int,
    source: VextRgba) =
  if x < 0 or x >= destination.width or y < 0 or y >= destination.height or
      source.a == 0: return
  let index = y * destination.width + x
  let oldAlpha = int(destination.alpha[index])
  let sourceAlpha = int(source.a)
  let outputAlpha = sourceAlpha + (oldAlpha * (255 - sourceAlpha) + 127) div 255
  if outputAlpha == 0: return
  template component(oldValue, newValue: uint8): uint8 =
    uint8((int(newValue) * sourceAlpha * 255 + int(oldValue) * oldAlpha *
      (255 - sourceAlpha) + outputAlpha * 127) div (outputAlpha * 255))
  destination.pixels[index] = VextRgb(
    r: component(destination.pixels[index].r, source.r),
    g: component(destination.pixels[index].g, source.g),
    b: component(destination.pixels[index].b, source.b))
  destination.alpha[index] = uint8(outputAlpha)

proc renderBitmapFontText*(font: VextBitmapFont, text: string,
    maximumWidth: int): VextTrueColourImage =
  font.validate
  if maximumWidth <= 0:
    raise newException(ValueError, "font preview width must be positive")
  var lines: seq[seq[VextGlyphRunItem]] = @[@[]]
  var widths = @[0]
  var previous = -1
  for item in font.glyphRun(text):
    if item.firstCodePoint == 10:
      lines.add @[]; widths.add 0; previous = -1
      continue
    let kernX = if previous >= 0:
        font.kerningFor(previous, item.firstCodePoint).x else: 0
    let advance = kernX + font.glyphs[item.glyphIndex].advanceX
    if lines[^1].len > 0 and widths[^1] + advance > maximumWidth:
      lines.add @[]; widths.add 0; previous = -1
    let appliedKern = if previous >= 0:
        font.kerningFor(previous, item.firstCodePoint).x else: 0
    widths[^1] += appliedKern + font.glyphs[item.glyphIndex].advanceX
    lines[^1].add item
    previous = item.lastCodePoint
  result.width = max(1, min(maximumWidth, max(1, block:
    var widest = 0
    for width in widths: widest = max(widest, width)
    widest)))
  result.height = max(1, lines.len * font.lineHeight)
  result.pixels = newSeq[VextRgb](result.width * result.height)
  result.alpha = newSeq[uint8](result.width * result.height)
  for lineIndex, line in lines:
    var penX = 0
    var previous = -1
    for item in line:
      let glyph = font.glyphs[item.glyphIndex]
      if previous >= 0:
        penX += font.kerningFor(previous, item.firstCodePoint).x
      let destinationX = penX + glyph.bearingX
      let destinationY = lineIndex * font.lineHeight + font.baseline - glyph.bearingY
      for y in 0 ..< height(glyph.bitmap):
        for x in 0 ..< width(glyph.bitmap):
          result.blend(destinationX + x, destinationY + y,
            glyph.bitmap.rgbaAt(x, y))
      penX += glyph.advanceX
      previous = item.lastCodePoint
