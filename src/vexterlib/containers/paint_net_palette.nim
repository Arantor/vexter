## Paint.NET text palette parsing.

import std/strutils
import ../archetypes/[palette, raster]

const
  PaintNetPaletteTypeId* = "paint-net.palette"
  PaintNetPaletteResourcePath* = "/palette"
  PaintNetPaletteMagic* = ";paint.net Palette File"
  MaximumPaintNetPaletteColours* = 65536

type PaintNetPalette* = object
  name*: string
  description*: string
  declaredColourCount*: int
  palette*: VextPalette

proc text(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc hexNibble(value: char): int =
  case value
  of '0' .. '9': ord(value) - ord('0')
  of 'a' .. 'f': ord(value) - ord('a') + 10
  of 'A' .. 'F': ord(value) - ord('A') + 10
  else: -1

proc hexByte(value: string, offset: int): uint8 =
  let high = hexNibble(value[offset])
  let low = hexNibble(value[offset + 1])
  if high < 0 or low < 0:
    raise newException(ValueError,
      "Paint.NET palette colour contains a non-hexadecimal digit")
  uint8(high shl 4 or low)

proc parsePaintNetPalette*(data: openArray[byte]): PaintNetPalette =
  let contents = text(data)
  var lines = contents.splitLines
  if lines.len == 0 or lines[0] != PaintNetPaletteMagic:
    raise newException(ValueError,
      "Paint.NET palette must begin with its magic comment")

  result.declaredColourCount = -1
  var alpha: seq[uint8]
  var hasTransparency = false
  for lineIndex in 1 ..< lines.len:
    let line = lines[lineIndex]
    if line.len == 0: continue
    if line[0] == ';':
      let comment = line[1 .. ^1]
      if comment.startsWith("Palette Name:"):
        let value = comment["Palette Name:".len .. ^1].strip
        if result.name.len == 0 and value.len > 0: result.name = value
      elif comment.startsWith("Description:"):
        let value = comment["Description:".len .. ^1].strip
        if result.description.len == 0 and value.len > 0:
          result.description = value
      elif comment.startsWith("Colors:"):
        let value = comment["Colors:".len .. ^1].strip
        try:
          let count = parseInt(value)
          if count >= 0: result.declaredColourCount = count
        except ValueError:
          discard
      continue
    if line.len != 8:
      raise newException(ValueError,
        "Paint.NET palette colour must contain exactly eight ARGB hex digits")
    if result.palette.colours.len >= MaximumPaintNetPaletteColours:
      raise newException(ValueError, "Paint.NET palette contains too many colours")
    let a = hexByte(line, 0)
    result.palette.colours.add VextRgb(
      r: hexByte(line, 2), g: hexByte(line, 4), b: hexByte(line, 6))
    alpha.add a
    if a != 255: hasTransparency = true

  if result.palette.colours.len == 0:
    raise newException(ValueError,
      "Paint.NET palette must contain at least one colour")
  if hasTransparency: result.palette.alpha = move(alpha)
  result.palette.validate

proc isPaintNetPalette*(data: openArray[byte]): bool =
  try:
    discard parsePaintNetPalette(data)
    true
  except ValueError:
    false

proc hasPaintNetPaletteExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".txt")
