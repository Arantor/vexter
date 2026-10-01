## Common ZX Spectrum Next Layer 2 raw image parsing.

import std/[os, strutils]
import ../archetypes/[palette, raster]
import ./zx_spectrum_next_palette

const
  ZxSpectrumNextImageTypeId* = "zx-spectrum-next.layer2-image"
  ZxSpectrumNextImageResourcePath* = "/image"
  ZxSpectrumNextImageSize* = 81920
  ZxSpectrumNextSmallImageSize* = 49152
  ZxSpectrumNextSmallEmbeddedPaletteSize* = 49664
  ZxSpectrumNextEmbeddedPaletteSize* = 512
  ZxSpectrumNextImageHeight* = 256
  ZxSpectrumNextImageWidth256* = 320
  ZxSpectrumNextImageWidth16* = 640
  ZxSpectrumNextSmallImageWidth* = 256
  ZxSpectrumNextSmallImageHeight* = 192

type
  ZxSpectrumNextImageLayout* = enum
    znilColumnMajor256
    znilRowMajor192

  ZxSpectrumNextImageSource* = object
    data*: seq[byte]
    layout*: ZxSpectrumNextImageLayout
    embeddedPalette*: VextPalette

proc hasZxSpectrumNextImageExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".nxi"

proc hasZxSpectrumNextSl2Extension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".sl2"

proc isZxSpectrumNextSl2Image*(data: openArray[byte]): bool =
  data.len == ZxSpectrumNextSmallImageSize

proc isZxSpectrumNextImage*(data: openArray[byte]): bool =
  data.len in [ZxSpectrumNextSmallImageSize,
    ZxSpectrumNextSmallEmbeddedPaletteSize, ZxSpectrumNextImageSize]

proc parseZxSpectrumNextImage*(data: openArray[byte]):
    ZxSpectrumNextImageSource =
  if not data.isZxSpectrumNextImage:
    raise newException(ValueError,
      "ZX Spectrum Next Layer 2 image must contain exactly 49152, 49664, or 81920 bytes")
  if data.len == ZxSpectrumNextImageSize:
    result.layout = znilColumnMajor256
    result.data = @data
  else:
    result.layout = znilRowMajor192
    var imageOffset = 0
    if data.len == ZxSpectrumNextSmallEmbeddedPaletteSize:
      result.embeddedPalette = parseZxSpectrumNextPalette(
        data.toOpenArray(0, ZxSpectrumNextEmbeddedPaletteSize - 1)).palette
      if result.embeddedPalette.colours.len != ZxSpectrumNextFullPaletteColours:
        raise newException(ValueError,
          "embedded NXI palette must contain 256 colours")
      imageOffset = ZxSpectrumNextEmbeddedPaletteSize
    result.data = @(data.toOpenArray(imageOffset, data.high))

proc storageOrderName*(source: ZxSpectrumNextImageSource): string =
  case source.layout
  of znilColumnMajor256: "column-major"
  of znilRowMajor192: "row-major"

proc synthesizedZxSpectrumNextPalette*(): VextPalette =
  for index in 0 .. 255:
    result.colours.add decodeZxSpectrumNextRgb332(byte(index))

proc decodeZxSpectrumNextImage*(source: ZxSpectrumNextImageSource,
    palette: VextPalette): VextIndexedImage =
  if palette.colours.len notin [ZxSpectrumNextSmallPaletteColours,
      ZxSpectrumNextFullPaletteColours]:
    raise newException(ValueError,
      "ZX Spectrum Next Layer 2 image requires a 16- or 256-colour palette")
  for colour in palette.colours: result.palette.add colour.rgb
  case source.layout
  of znilRowMajor192:
    result.width = ZxSpectrumNextSmallImageWidth
    result.height = ZxSpectrumNextSmallImageHeight
    result.pixels = source.data
    if palette.colours.len == ZxSpectrumNextSmallPaletteColours:
      for value in result.pixels:
        if value >= ZxSpectrumNextSmallPaletteColours.byte:
          raise newException(ValueError,
            "256x192 NXI pixel exceeds its 16-colour companion palette")
  of znilColumnMajor256:
    result.height = ZxSpectrumNextImageHeight
    result.width = if palette.colours.len == ZxSpectrumNextSmallPaletteColours:
      ZxSpectrumNextImageWidth16 else: ZxSpectrumNextImageWidth256
    result.pixels = newSeq[byte](result.width * result.height)
    for sourceX in 0 ..< ZxSpectrumNextImageWidth256:
      for y in 0 ..< ZxSpectrumNextImageHeight:
        let packed = source.data[sourceX * ZxSpectrumNextImageHeight + y]
        if palette.colours.len == ZxSpectrumNextFullPaletteColours:
          result.pixels[y * result.width + sourceX] = packed
        else:
          let output = y * result.width + sourceX * 2
          result.pixels[output] = packed shr 4
          result.pixels[output + 1] = packed and 0x0f
