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

proc renderBitmapFontGlyphGrid*(font: VextBitmapFont, maximumWidth: int,
    selectedGlyph = -1): VextTrueColourImage =
  font.validate
  if maximumWidth <= 0:
    raise newException(ValueError, "font glyph-grid width must be positive")
  var minimumBearingX = 0
  var contentWidth = 1
  for glyph in font.glyphs:
    minimumBearingX = min(minimumBearingX, glyph.bearingX)
    contentWidth = max(contentWidth,
      max(glyph.advanceX, glyph.bearingX + width(glyph.bitmap)))
  let leftInset = 3 - minimumBearingX
  let cellWidth = max(8, leftInset + contentWidth + 3)
  let cellHeight = max(8, font.lineHeight + 6)
  let columns = max(1, maximumWidth div cellWidth)
  let rows = max(1, (font.glyphs.len + columns - 1) div columns)
  result = VextTrueColourImage(width: max(1, min(maximumWidth,
    columns * cellWidth)), height: rows * cellHeight,
    pixels: newSeq[VextRgb](max(1, min(maximumWidth,
      columns * cellWidth)) * rows * cellHeight),
    alpha: newSeq[uint8](max(1, min(maximumWidth,
      columns * cellWidth)) * rows * cellHeight))
  template mark(x, y: int, markColour: VextRgb, opacity: uint8) =
    block:
      let markX = x
      let markY = y
      if markX >= 0 and markX < result.width and markY >= 0 and
          markY < result.height:
        let markOffset = markY * result.width + markX
        result.pixels[markOffset] = markColour
        result.alpha[markOffset] = opacity
  for index, glyph in font.glyphs:
    let cellX = (index mod columns) * cellWidth
    let cellY = (index div columns) * cellHeight
    let baselineY = cellY + 3 + font.baseline
    for x in cellX + 1 ..< min(result.width, cellX + cellWidth - 1):
      mark(x, baselineY, VextRgb(r: 40, g: 160, b: 255), 150)
      if font.ascent > 0:
        mark(x, baselineY - font.ascent,
          VextRgb(r: 80, g: 220, b: 140), 110)
      if font.descent > 0:
        mark(x, baselineY + font.descent,
          VextRgb(r: 255, g: 100, b: 100), 110)
    if index == selectedGlyph:
      for x in cellX ..< min(result.width, cellX + cellWidth):
        mark(x, cellY, VextRgb(r: 255, g: 200, b: 20), 255)
        mark(x, cellY + cellHeight - 1,
          VextRgb(r: 255, g: 200, b: 20), 255)
      for y in cellY ..< cellY + cellHeight:
        mark(cellX, y, VextRgb(r: 255, g: 200, b: 20), 255)
        mark(cellX + cellWidth - 1, y,
          VextRgb(r: 255, g: 200, b: 20), 255)
    let destinationX = cellX + leftInset + glyph.bearingX
    let destinationY = baselineY - glyph.bearingY
    for y in 0 ..< height(glyph.bitmap):
      for x in 0 ..< width(glyph.bitmap):
        result.blend(destinationX + x, destinationY + y,
          glyph.bitmap.rgbaAt(x, y))
