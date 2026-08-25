## Raster decoding for Commodore 64 KoalaPainter images.

import ../archetypes/raster
import ../containers/koala_painter

const
  KoalaPainterImageTypeId* = "commodore64.koala-painter-image"
  KoalaPainterImageResourcePath* = "/image"

  ## Colodore colours by Pepto, reordered from the supplied Lospec palette's
  ## visual grouping into the C64 VIC-II colour indices used by Koala data.
  ColodorePalette* = [
    VextRgb(r: 0x00, g: 0x00, b: 0x00), # 0 black
    VextRgb(r: 0xff, g: 0xff, b: 0xff), # 1 white
    VextRgb(r: 0x81, g: 0x33, b: 0x38), # 2 red
    VextRgb(r: 0x75, g: 0xce, b: 0xc8), # 3 cyan
    VextRgb(r: 0x8e, g: 0x3c, b: 0x97), # 4 purple
    VextRgb(r: 0x56, g: 0xac, b: 0x4d), # 5 green
    VextRgb(r: 0x2e, g: 0x2c, b: 0x9b), # 6 blue
    VextRgb(r: 0xed, g: 0xf1, b: 0x71), # 7 yellow
    VextRgb(r: 0x8e, g: 0x50, b: 0x29), # 8 orange
    VextRgb(r: 0x55, g: 0x38, b: 0x00), # 9 brown
    VextRgb(r: 0xc4, g: 0x6c, b: 0x71), # 10 light red
    VextRgb(r: 0x4a, g: 0x4a, b: 0x4a), # 11 dark grey
    VextRgb(r: 0x7b, g: 0x7b, b: 0x7b), # 12 grey
    VextRgb(r: 0xa9, g: 0xff, b: 0x9f), # 13 light green
    VextRgb(r: 0x70, g: 0x6d, b: 0xeb), # 14 light blue
    VextRgb(r: 0xb2, g: 0xb2, b: 0xb2)] # 15 light grey

proc decodeKoalaPainter*(source: KoalaPainterSource): VextRaster =
  var indices = newSeq[uint8](320 * 200)
  for y in 0 ..< 200:
    let cellRow = y div 8
    let rowInCell = y mod 8
    for cellColumn in 0 ..< 40:
      let cell = cellRow * 40 + cellColumn
      let packed = source.bitmap[cell * 8 + rowInCell]
      let screen = source.screenRam[cell]
      let colour = source.colourRam[cell]
      for multicolourX in 0 ..< 4:
        let selector = int((packed shr (6 - multicolourX * 2)) and 0x03)
        let paletteIndex = case selector
          of 0: source.backgroundColour
          of 1: screen shr 4
          of 2: screen and 0x0f
          else: colour and 0x0f
        let x = cellColumn * 8 + multicolourX * 2
        indices[y * 320 + x] = paletteIndex
        indices[y * 320 + x + 1] = paletteIndex
  VextRaster(kind: vrkIndexedImage, image: VextIndexedImage(
    width: 320, height: 200, palette: @ColodorePalette, pixels: indices))
