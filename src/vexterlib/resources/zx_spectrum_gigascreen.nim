## Decoder for a ZX Gigascreen bitmap with two attribute sets.

import ../archetypes/raster
import ./zx_spectrum_screen

const
  ZxSpectrumGigascreenTypeId* = "zx-spectrum.gigascreen"
  ZxSpectrumGigascreenResourcePath* = "/screen"
  ZxSpectrumGigascreenPaletteAPath* = "/screen/palette-a"
  ZxSpectrumGigascreenPaletteBPath* = "/screen/palette-b"
  ZxSpectrumGigascreenAveragedPath* = "/screen/averaged"
  ZxSpectrumGigascreenSize* = 7680

type ZxSpectrumGigascreen* = object
  paletteA*, paletteB*: VextIndexedImage
  averaged*: VextTrueColourImage

proc decodeZxSpectrumGigascreen*(data: openArray[byte]): ZxSpectrumGigascreen =
  if data.len != ZxSpectrumGigascreenSize:
    raise newException(ValueError,
      "ZX Gigascreen must contain exactly 7680 bytes")

  var screen = newSeq[byte](ZxSpectrumScreenSize)
  for index in 0 ..< 6144:
    screen[index] = data[index]
  for index in 0 ..< 768:
    screen[6144 + index] = data[6144 + index]
  result.paletteA = decodeZxSpectrumScreenImage(screen)
  for index in 0 ..< 768:
    screen[6144 + index] = data[6912 + index]
  result.paletteB = decodeZxSpectrumScreenImage(screen)

  result.averaged = VextTrueColourImage(
    width: ZxSpectrumScreenWidth,
    height: ZxSpectrumScreenHeight,
    pixels: newSeq[VextRgb](ZxSpectrumScreenWidth * ZxSpectrumScreenHeight))
  for index in 0 ..< result.averaged.pixels.len:
    let
      colourA = result.paletteA.palette[int(result.paletteA.pixels[index])]
      colourB = result.paletteB.palette[int(result.paletteB.pixels[index])]
    result.averaged.pixels[index] = VextRgb(
      r: uint8((int(colourA.r) + int(colourB.r)) div 2),
      g: uint8((int(colourA.g) + int(colourB.g)) div 2),
      b: uint8((int(colourA.b) + int(colourB.b)) div 2))
