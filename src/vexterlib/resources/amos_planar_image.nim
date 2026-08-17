## Reusable decoder for planar images stored in AMOS sprite and icon banks.

import ../archetypes/raster

const
  AmosSpriteResourceTypeId* = "amos.sprite"
  AmosIconResourceTypeId* = "amos.icon"
  AmosPaletteEntries* = 32

type
  AmosPlanarImage* = object
    widthWords*: int
    height*: int
    depth*: int
    hotspotX*: int
    hotspotY*: int
    planeData*: seq[byte]

proc decodeAmosPlanarImage*(source: AmosPlanarImage,
    palette: openArray[VextRgb]): VextIndexedImage =
  if source.widthWords <= 0 or source.height <= 0:
    raise newException(ValueError, "AMOS image dimensions must be positive")
  if source.depth < 1 or source.depth > 5:
    raise newException(ValueError, "AMOS image depth must be between 1 and 5")
  let expectedSize = source.widthWords * 2 * source.height * source.depth
  if source.planeData.len != expectedSize:
    raise newException(ValueError, "AMOS image has an invalid planar data size")
  if palette.len < (1 shl source.depth):
    raise newException(ValueError, "AMOS image palette is too small for its depth")

  result = VextIndexedImage(
    width: source.widthWords * 16,
    height: source.height,
    palette: @palette,
    pixels: newSeq[uint8](source.widthWords * 16 * source.height))

  for y in 0 ..< source.height:
    for x in 0 ..< result.width:
      var paletteIndex = 0'u8
      for plane in 0 ..< source.depth:
        let wordOffset = ((plane * source.height + y) *
          source.widthWords + x div 16) * 2
        let word = (uint16(source.planeData[wordOffset]) shl 8) or
          uint16(source.planeData[wordOffset + 1])
        let bit = (word shr (15 - x mod 16)) and 1
        paletteIndex = paletteIndex or uint8(bit shl plane)
      result.pixels[y * result.width + x] = paletteIndex
