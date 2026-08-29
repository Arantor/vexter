## GIMP Palette (GPL) text format parsing.

import std/[strutils, unicode]
import ../archetypes/[palette, raster]

const
  GimpPaletteTypeId* = "gimp.palette"
  GimpPaletteResourcePath* = "/palette"
  GimpPaletteMagic* = "GIMP Palette"
  MaximumGimpPaletteColours* = 65536

type GimpPalette* = object
  name*: string
  columns*: int
  version*: int
  hasAlpha*: bool
  palette*: VextPalette

proc text(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc parseComponent(value: string): uint8 =
  var component: int
  try:
    component = parseInt(value)
  except ValueError:
    raise newException(ValueError,
      "GIMP palette colour components must be decimal integers")
  if component < 0 or component > 255:
    raise newException(ValueError,
      "GIMP palette colour components must be between 0 and 255")
  uint8(component)

proc parseGimpPalette*(data: openArray[byte]): GimpPalette =
  let contents = text(data)
  if validateUtf8(contents) != -1:
    raise newException(ValueError, "GIMP palette text must be valid UTF-8")
  let lines = contents.splitLines
  if lines.len == 0 or lines[0] != GimpPaletteMagic:
    raise newException(ValueError,
      "GIMP palette must begin with its magic identifier")

  result.columns = 0
  result.version = 1
  var bodyStart = 1
  if lines.len > 1 and lines[1].startsWith("Name: "):
    result.version = 2
    result.name = lines[1]["Name: ".len .. ^1].strip
    bodyStart = 2

  if lines.len > bodyStart and lines[bodyStart] == "Channels: RGBA":
    result.hasAlpha = true
    inc bodyStart

  if result.version == 2 and lines.len > bodyStart and
      lines[bodyStart].startsWith("Columns: "):
    let value = lines[bodyStart]["Columns: ".len .. ^1]
    try:
      result.columns = parseInt(value)
    except ValueError:
      raise newException(ValueError,
        "GIMP palette column count must be an integer")
    if result.columns < 0 or result.columns > 255:
      raise newException(ValueError,
        "GIMP palette column count must be between 0 and 255")
    inc bodyStart

  for lineIndex in bodyStart ..< lines.len:
    let line = lines[lineIndex]
    if line.len == 0 or line[0] == '#': continue
    let fields = strutils.splitWhitespace(line)
    if fields.len < 3:
      raise newException(ValueError,
        "GIMP palette colour must contain red, green, and blue components")
    if result.hasAlpha and fields.len < 4:
      raise newException(ValueError,
        "RGBA GIMP palette colour must contain an alpha component")
    if result.palette.colours.len >= MaximumGimpPaletteColours:
      raise newException(ValueError, "GIMP palette contains too many colours")
    result.palette.colours.add VextRgba(
      r: parseComponent(fields[0]), g: parseComponent(fields[1]),
      b: parseComponent(fields[2]),
      a: if result.hasAlpha: parseComponent(fields[3]) else: 255)

  if result.palette.colours.len == 0:
    raise newException(ValueError, "GIMP palette must contain at least one colour")
  result.palette.validate

proc isGimpPalette*(data: openArray[byte]): bool =
  try:
    discard parseGimpPalette(data)
    true
  except ValueError:
    false

proc hasGimpPaletteExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".gpl")
