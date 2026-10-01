## JASC PaintShop Pro text palette parsing.

import std/[strutils, unicode]
import ../archetypes/[palette, raster]

const
  JascPaletteTypeId* = "jasc.palette"
  JascPaletteResourcePath* = "/palette"
  JascPaletteMagic* = "JASC-PAL"
  JascPaletteVersion* = "0100"
  MaximumJascPaletteColours* = 65536

proc text(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc decimalComponent(value: string): uint8 =
  var parsed: int
  try:
    parsed = parseInt(value)
  except ValueError:
    raise newException(ValueError,
      "JASC palette components must be decimal integers")
  if parsed < 0 or parsed > 255:
    raise newException(ValueError,
      "JASC palette components must be between 0 and 255")
  uint8(parsed)

proc parseJascPalette*(data: openArray[byte]): VextPalette =
  let contents = text(data)
  if validateUtf8(contents) != -1:
    raise newException(ValueError, "JASC palette text must be valid UTF-8")
  let lines = contents.splitLines
  if lines.len < 3 or lines[0] != JascPaletteMagic:
    raise newException(ValueError,
      "JASC palette must begin with its magic identifier")
  if lines[1] != JascPaletteVersion:
    raise newException(ValueError, "unsupported JASC palette version")
  var count: int
  try:
    count = parseInt(lines[2])
  except ValueError:
    raise newException(ValueError,
      "JASC palette colour count must be a decimal integer")
  if count <= 0 or count > MaximumJascPaletteColours:
    raise newException(ValueError, "JASC palette colour count is out of range")
  if lines.len < count + 3:
    raise newException(ValueError, "JASC palette contains too few colours")
  for index in 0 ..< count:
    let fields = strutils.splitWhitespace(lines[index + 3])
    if fields.len != 3:
      raise newException(ValueError,
        "JASC palette colours must contain exactly three components")
    result.colours.add VextRgba(r: decimalComponent(fields[0]),
      g: decimalComponent(fields[1]), b: decimalComponent(fields[2]), a: 255)
  for index in count + 3 ..< lines.len:
    if lines[index].len > 0:
      raise newException(ValueError, "JASC palette contains trailing data")
  result.validate

proc isJascPalette*(data: openArray[byte]): bool =
  try:
    discard parseJascPalette(data)
    true
  except ValueError:
    false

proc hasJascPaletteExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".pal")
