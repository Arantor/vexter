## Ordered palette swatches with labelled colour-cycle range rows.

import std/strutils
import ../archetypes/[palette, raster]

const
  PaletteSwatchCellSize* = 16
  CaptionHeight = 9
  SectionGap = 4
  GlyphWidth = 5
  GlyphHeight = 7
  GlyphAdvance = 6

proc swatchColumns(colourCount: int): int =
  result = 1
  while result * result < colourCount: inc result

proc glyphRows(character: char): array[GlyphHeight, string] =
  case character
  of 'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"]
  of 'D': ["11110", "10001", "10001", "10001", "10001", "10001", "11110"]
  of 'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"]
  of 'F': ["11111", "10000", "10000", "11110", "10000", "10000", "10000"]
  of 'G': ["01110", "10001", "10000", "10111", "10001", "10001", "01110"]
  of 'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"]
  of 'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"]
  of 'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"]
  of 'R': ["11110", "10001", "10001", "11110", "10100", "10010", "10001"]
  of 'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"]
  of 'V': ["10001", "10001", "10001", "10001", "10001", "01010", "00100"]
  of 'W': ["10001", "10001", "10001", "10101", "10101", "10101", "01010"]
  of '0': ["01110", "10001", "10011", "10101", "11001", "10001", "01110"]
  of '1': ["00100", "01100", "00100", "00100", "00100", "00100", "01110"]
  of '2': ["01110", "10001", "00001", "00010", "00100", "01000", "11111"]
  of '3': ["11110", "00001", "00001", "01110", "00001", "00001", "11110"]
  of '4': ["00010", "00110", "01010", "10010", "11111", "00010", "00010"]
  of '5': ["11111", "10000", "10000", "11110", "00001", "00001", "11110"]
  of '6': ["01110", "10000", "10000", "11110", "10001", "10001", "01110"]
  of '7': ["11111", "00001", "00010", "00100", "01000", "01000", "01000"]
  of '8': ["01110", "10001", "10001", "01110", "10001", "10001", "01110"]
  of '9': ["01110", "10001", "10001", "01111", "00001", "00001", "01110"]
  of '-': ["00000", "00000", "00000", "11111", "00000", "00000", "00000"]
  of ':': ["00000", "00100", "00100", "00000", "00100", "00100", "00000"]
  else: ["00000", "00000", "00000", "00000", "00000", "00000", "00000"]

proc caption(cycle: VextColourCycleRange, index: int): string =
  "RANGE " & $(index + 1) & ": " & $cycle.low & "-" & $cycle.high & " " &
    (if cycle.direction < 0: "REVERSE " else: "FORWARD ") &
    $cycle.stepDurationMs & "MS"

proc fillRect(image: var VextTrueColourImage, left, top, width, height: int,
    colour: VextRgb, alpha = 255'u8) =
  for y in top ..< top + height:
    for x in left ..< left + width:
      let offset = y * image.width + x
      image.pixels[offset] = colour
      image.alpha[offset] = alpha

proc paletteAlpha(palette: VextPalette, index: int): uint8 =
  if palette.alpha.len == 0: 255'u8 else: palette.alpha[index]

proc drawText(image: var VextTrueColourImage, value: string, top: int) =
  let ink = VextRgb(r: 255, g: 255, b: 255)
  for characterIndex, character in value.toUpperAscii:
    let rows = glyphRows(character)
    for y, row in rows:
      for x in 0 ..< GlyphWidth:
        if row[x] == '1':
          image.pixels[(top + y) * image.width +
            characterIndex * GlyphAdvance + x] = ink

proc renderPaletteSwatch*(palette: VextPalette): VextTrueColourImage =
  palette.validate
  let
    columns = swatchColumns(palette.colours.len)
    paletteRows = (palette.colours.len + columns - 1) div columns
    paletteWidth = columns * PaletteSwatchCellSize
    paletteHeight = paletteRows * PaletteSwatchCellSize
  var width = paletteWidth
  for index, cycle in palette.colourCycles:
    width = max(width, (cycle.high - cycle.low + 1) * PaletteSwatchCellSize)
    width = max(width, caption(cycle, index).len * GlyphAdvance - 1)
  let height = paletteHeight + palette.colourCycles.len *
    (SectionGap + CaptionHeight + PaletteSwatchCellSize)
  result = VextTrueColourImage(width: width, height: height,
    pixels: newSeq[VextRgb](width * height),
    alpha: newSeq[uint8](width * height))
  result.fillRect(0, 0, width, height, VextRgb(r: 32, g: 32, b: 32))

  for index, colour in palette.colours:
    result.fillRect((index mod columns) * PaletteSwatchCellSize,
      (index div columns) * PaletteSwatchCellSize,
      PaletteSwatchCellSize, PaletteSwatchCellSize, colour,
      palette.paletteAlpha(index))

  var top = paletteHeight
  for rangeIndex, cycle in palette.colourCycles:
    top += SectionGap
    result.drawText(caption(cycle, rangeIndex), top + 1)
    top += CaptionHeight
    if cycle.direction < 0:
      var position = 0
      for colourIndex in countdown(cycle.high, cycle.low):
        result.fillRect(position * PaletteSwatchCellSize, top,
          PaletteSwatchCellSize, PaletteSwatchCellSize,
          palette.colours[colourIndex], palette.paletteAlpha(colourIndex))
        inc position
    else:
      for colourIndex in cycle.low .. cycle.high:
        result.fillRect((colourIndex - cycle.low) * PaletteSwatchCellSize, top,
          PaletteSwatchCellSize, PaletteSwatchCellSize,
          palette.colours[colourIndex], palette.paletteAlpha(colourIndex))
    top += PaletteSwatchCellSize

proc paletteOf*(image: VextIndexedImage): VextPalette =
  VextPalette(colours: image.palette, colourCycles: image.colourCycles)

proc paletteOf*(animation: VextIndexedAnimation): VextPalette =
  if animation.frames.len == 0:
    raise newException(ValueError, "indexed animation has no palette frame")
  VextPalette(colours: animation.frames[0].image.palette,
    colourCycles: animation.colourCycles)
