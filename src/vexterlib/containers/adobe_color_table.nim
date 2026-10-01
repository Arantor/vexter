## Adobe Color Table (ACT) fixed RGB8 palette parsing.

import std/strutils
import ../archetypes/[palette, raster]

const
  AdobeColorTableTypeId* = "adobe.color-table"
  AdobeColorTableResourcePath* = "/palette"
  AdobeColorTableColours* = 256
  AdobeColorTableSize* = AdobeColorTableColours * 3

proc parseAdobeColorTable*(data: openArray[byte]): VextPalette =
  if data.len != AdobeColorTableSize:
    raise newException(ValueError,
      "Adobe Color Table must contain exactly 768 RGB bytes")
  for index in 0 ..< AdobeColorTableColours:
    result.colours.add VextRgba(r: data[index * 3],
      g: data[index * 3 + 1], b: data[index * 3 + 2], a: 255)
  result.validate

proc isAdobeColorTable*(data: openArray[byte]): bool =
  data.len == AdobeColorTableSize

proc hasAdobeColorTableExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".act")
