## AngelCode BMFont text descriptor and PNG atlas exporter.

import std/[strutils]
import ../archetypes/[font, raster]
import ../artifacts
import ./png

const
  DefaultBmFontAtlasSize* = 1024
  BmFontGlyphPadding* = 1

type
  PackedGlyph = object
    page*, x*, y*, width*, height*: int

  AtlasPage = object
    usedHeight: int
    image: VextTrueColourImage

proc textBytes(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for index, character in value: result[index] = byte(character)

proc quoted(value: string): string =
  result = value.replace("\\", "\\\\").replace("\"", "\\\"")

proc nextPowerOfTwo(value: int): int =
  result = 1
  while result < value: result = result shl 1

proc exportBmFont*(font: VextBitmapFont, suggestedName = "font",
    maximumAtlasSize = DefaultBmFontAtlasSize): VextArtifactSet =
  font.validate
  if maximumAtlasSize <= BmFontGlyphPadding * 2:
    raise newException(ValueError, "BMFont atlas size is too small")
  let stem = if suggestedName.len > 0: suggestedName else: "font"
  var packed = newSeq[PackedGlyph](font.glyphs.len)
  var pages: seq[AtlasPage]
  var page = -1
  var cursorX, cursorY, shelfHeight: int
  proc newPage() =
    pages.add AtlasPage(image: VextTrueColourImage(
      width: maximumAtlasSize, height: maximumAtlasSize,
      pixels: newSeq[VextRgb](maximumAtlasSize * maximumAtlasSize),
      alpha: newSeq[uint8](maximumAtlasSize * maximumAtlasSize)))
    page = pages.high
    cursorX = BmFontGlyphPadding
    cursorY = BmFontGlyphPadding
    shelfHeight = 0
  newPage()
  for index, glyph in font.glyphs:
    let width = width(glyph.bitmap)
    let height = height(glyph.bitmap)
    if width == 0 or height == 0:
      packed[index] = PackedGlyph(page: 0)
      continue
    if width + BmFontGlyphPadding * 2 > maximumAtlasSize or
        height + BmFontGlyphPadding * 2 > maximumAtlasSize:
      raise newException(ValueError, "bitmap glyph is larger than the BMFont atlas")
    if cursorX + width + BmFontGlyphPadding > maximumAtlasSize:
      cursorX = BmFontGlyphPadding
      cursorY += shelfHeight + BmFontGlyphPadding
      shelfHeight = 0
    if cursorY + height + BmFontGlyphPadding > maximumAtlasSize:
      pages[page].usedHeight = cursorY + shelfHeight
      newPage()
    packed[index] = PackedGlyph(page: page, x: cursorX, y: cursorY,
      width: width, height: height)
    for y in 0 ..< height:
      for x in 0 ..< width:
        let colour = glyph.bitmap.rgbaAt(x, y)
        let destination = (cursorY + y) * maximumAtlasSize + cursorX + x
        pages[page].image.pixels[destination] = VextRgb(
          r: colour.r, g: colour.g, b: colour.b)
        pages[page].image.alpha[destination] = colour.a
    cursorX += width + BmFontGlyphPadding
    shelfHeight = max(shelfHeight, height)
  pages[page].usedHeight = max(pages[page].usedHeight, cursorY + shelfHeight)

  # BMFont declares one scale for every page, so all pages share the largest
  # used power-of-two height.
  var pageHeight = 1
  for atlas in pages:
    pageHeight = max(pageHeight, atlas.usedHeight + BmFontGlyphPadding)
  pageHeight = min(maximumAtlasSize, nextPowerOfTwo(pageHeight))
  for atlas in pages.mitems:
    atlas.image.height = pageHeight
    atlas.image.pixels.setLen(atlas.image.width * pageHeight)
    atlas.image.alpha.setLen(atlas.image.width * pageHeight)

  var descriptor = "info face=\"" & quoted(font.name) & "\" size=" &
    $font.lineHeight & " bold=0 italic=0 charset=\"\" unicode=1 stretchH=100" &
    " smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n"
  descriptor.add "common lineHeight=" & $font.lineHeight & " base=" &
    $font.baseline & " scaleW=" & $pages[0].image.width & " scaleH=" &
    $pages[0].image.height & " pages=" & $pages.len &
    " packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0\n"
  for index in 0 .. pages.high:
    descriptor.add "page id=" & $index & " file=\"" & stem & "-" &
      $index & ".png\"\n"
  descriptor.add "chars count=" & $font.mappings.len & "\n"
  for mapping in font.mappings:
    let glyph = font.glyphs[mapping.glyphIndex]
    let position = packed[mapping.glyphIndex]
    descriptor.add "char id=" & $mapping.codePoint & " x=" & $position.x &
      " y=" & $position.y & " width=" & $position.width & " height=" &
      $position.height & " xoffset=" & $glyph.bearingX & " yoffset=" &
      $(font.baseline - glyph.bearingY) & " xadvance=" & $glyph.advanceX &
      " page=" & $position.page & " chnl=15\n"
  var horizontalKernings = 0
  for pair in font.kerning:
    if pair.amountX != 0: inc horizontalKernings
  descriptor.add "kernings count=" & $horizontalKernings & "\n"
  for pair in font.kerning:
    if pair.amountX != 0:
      descriptor.add "kerning first=" & $pair.leftCodePoint & " second=" &
        $pair.rightCodePoint & " amount=" & $pair.amountX & "\n"

  result.artifacts.add VextArtifact(suggestedFilename: stem & ".fnt",
    mediaType: "text/plain; charset=utf-8", data: textBytes(descriptor))
  for index, atlas in pages:
    result.artifacts.add exportPng(atlas.image,
      stem & "-" & $index & ".png").artifacts[0]
