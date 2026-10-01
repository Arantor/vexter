## ZX Spectrum Next raw Layer 2 palette parsing.

import std/strutils
import ../archetypes/[palette, raster]

const
  ZxSpectrumNextPaletteTypeId* = "zx-spectrum-next.palette"
  ZxSpectrumNextPaletteResourcePath* = "/palette"
  ZxSpectrumNextSmallPaletteColours* = 16
  ZxSpectrumNextFullPaletteColours* = 256
  ZxSpectrumNextRgb333SmallSize* = 32
  ZxSpectrumNextRgb332Size* = 256
  ZxSpectrumNextRgb333Size* = 512
  ZxSpectrumNextRgb333MaskSize* = 513
  NextComponent8 = [0x00'u8, 0x24, 0x49, 0x6d,
    0x92, 0xb6, 0xdb, 0xff]

type ZxSpectrumNextPalette* = object
  bitsPerColour*: int
  transparentIndex*: int
  palette*: VextPalette

proc decodeZxSpectrumNextRgb332*(packed: byte): VextRgba =
  let red = int((packed shr 5) and 0x07)
  let green = int((packed shr 2) and 0x07)
  let blueHigh = int(packed and 0x03)
  let blueLow = ((blueHigh shr 1) or blueHigh) and 0x01
  VextRgba(r: NextComponent8[red], g: NextComponent8[green],
    b: NextComponent8[blueHigh shl 1 or blueLow], a: 255)

proc parseZxSpectrumNextPalette*(data: openArray[byte]):
    ZxSpectrumNextPalette =
  if data.len notin [ZxSpectrumNextRgb333SmallSize,
      ZxSpectrumNextRgb332Size, ZxSpectrumNextRgb333Size,
      ZxSpectrumNextRgb333MaskSize]:
    raise newException(ValueError,
      "ZX Spectrum Next palette must contain exactly 32, 256, 512, or 513 bytes")

  result.transparentIndex = -1
  result.bitsPerColour = if data.len == ZxSpectrumNextRgb332Size: 8 else: 9
  let colourCount = if data.len == ZxSpectrumNextRgb333SmallSize:
    ZxSpectrumNextSmallPaletteColours else: ZxSpectrumNextFullPaletteColours
  for index in 0 ..< colourCount:
    let packed = data[index * (if result.bitsPerColour == 8: 1 else: 2)]
    if result.bitsPerColour == 8:
      result.palette.colours.add decodeZxSpectrumNextRgb332(packed)
    else:
      let red = int((packed shr 5) and 0x07)
      let green = int((packed shr 2) and 0x07)
      let blueHigh = int(packed and 0x03)
      let lowByte = data[index * 2 + 1]
      if lowByte > 1:
        raise newException(ValueError,
          "ZX Spectrum Next nine-bit palette low-blue bytes must be 0 or 1")
      let blue = blueHigh shl 1 or int(lowByte)
      result.palette.colours.add VextRgba(r: NextComponent8[red],
        g: NextComponent8[green], b: NextComponent8[blue], a: 255)
  if data.len == ZxSpectrumNextRgb333MaskSize:
    result.transparentIndex = int(data[ZxSpectrumNextRgb333Size])
    result.palette.colours[result.transparentIndex].a = 0
  result.palette.validate

proc isZxSpectrumNextPalette*(data: openArray[byte]): bool =
  try:
    discard parseZxSpectrumNextPalette(data)
    true
  except ValueError:
    false

proc hasZxSpectrumNextPaletteExtension*(filename: string): bool =
  let lower = filename.toLowerAscii
  lower.endsWith(".nxp") or lower.endsWith(".npl") or lower.endsWith(".pal")

proc hasZxSpectrumNextNxpExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".nxp")

proc hasZxSpectrumNextNplExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".npl")
