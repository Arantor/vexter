## Generic count-prefixed RGBA8 palette parsing.

import std/strutils
import ../archetypes/[palette, raster]

const
  Rgba8PaletteTypeId* = "rgba8.palette"
  Rgba8PaletteResourcePath* = "/palette"
  MaximumRgba8PaletteColours* = 65536

proc parseRgba8Palette*(data: openArray[byte]): VextPalette =
  if data.len < 4:
    raise newException(ValueError, "RGBA8 palette is missing its colour count")
  let count = uint64(data[0]) or (uint64(data[1]) shl 8) or
    (uint64(data[2]) shl 16) or (uint64(data[3]) shl 24)
  if count == 0:
    raise newException(ValueError, "RGBA8 palette must contain at least one colour")
  if count > MaximumRgba8PaletteColours.uint64:
    raise newException(ValueError, "RGBA8 palette contains too many colours")
  if count * 4 + 4 != data.len.uint64:
    raise newException(ValueError,
      "RGBA8 palette size does not match its declared colour count")
  for index in 0 ..< int(count):
    let offset = 4 + index * 4
    result.colours.add VextRgba(r: data[offset], g: data[offset + 1],
      b: data[offset + 2], a: data[offset + 3])
  result.validate

proc isRgba8Palette*(data: openArray[byte]): bool =
  try:
    discard parseRgba8Palette(data)
    true
  except ValueError:
    false

proc hasRgba8PaletteExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".pal")
