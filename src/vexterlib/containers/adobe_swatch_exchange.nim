## Adobe Swatch Exchange (ASE) palette parsing.

import std/[math, strutils]
import ../archetypes/[palette, raster]

const
  AdobeSwatchExchangeTypeId* = "adobe.swatch-exchange"
  AdobeSwatchExchangeResourcePath* = "/palette"
  AdobeSwatchExchangeMagic* = "ASEF"
  MaximumAdobeSwatchBlocks* = 1_000_000
  MaximumAdobeSwatchColours* = 65536

type AdobeSwatchExchange* = object
  versionMajor*, versionMinor*: int
  blockCount*: int
  rgbColourCount*: int
  unsupportedColourCount*: int
  palette*: VextPalette

proc beWord(data: openArray[byte], offset: int): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated Adobe ASE WORD")
  int(data[offset]) shl 8 or int(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "truncated Adobe ASE DWORD")
  uint32(data[offset]) shl 24 or uint32(data[offset + 1]) shl 16 or
    uint32(data[offset + 2]) shl 8 or uint32(data[offset + 3])

proc checkedInt(value: uint32, description: string): int =
  if uint64(value) > uint64(high(int)):
    raise newException(ValueError, description & " exceeds host limits")
  int(value)

proc ascii(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or length > data.len - offset:
    raise newException(ValueError, "truncated Adobe ASE ASCII field")
  result = newString(length)
  for index in 0 ..< length: result[index] = char(data[offset + index])

proc skipName(data: openArray[byte], offset: var int, limit: int) =
  if offset + 2 > limit:
    raise newException(ValueError, "truncated Adobe ASE name length")
  let units = beWord(data, offset)
  offset += 2
  if units < 1 or units > (limit - offset) div 2:
    raise newException(ValueError, "invalid Adobe ASE name length")
  let terminator = offset + (units - 1) * 2
  if data[terminator] != 0 or data[terminator + 1] != 0:
    raise newException(ValueError, "Adobe ASE name is not null terminated")
  offset += units * 2

proc beFloat(data: openArray[byte], offset: int): float32 =
  cast[float32](beDword(data, offset))

proc rgbComponent(value: float32): uint8 =
  if value.classify in {fcNan, fcInf, fcNegInf} or value < 0 or value > 1:
    raise newException(ValueError,
      "Adobe ASE RGB component must be a finite value from 0 through 1")
  uint8(round(float(value) * 255.0))

proc parseColourBlock(data: openArray[byte], start, limit: int,
    result: var AdobeSwatchExchange) =
  var offset = start
  skipName(data, offset, limit)
  if offset + 4 > limit:
    raise newException(ValueError, "truncated Adobe ASE colour space")
  let colourSpace = ascii(data, offset, 4)
  offset += 4
  let components = case colourSpace
    of "RGB ", "LAB ": 3
    of "CMYK": 4
    of "Gray": 1
    else: 0
  if components == 0:
    raise newException(ValueError, "unknown Adobe ASE colour space")
  if components * 4 + 2 > limit - offset:
    raise newException(ValueError, "truncated Adobe ASE colour values")
  if colourSpace == "RGB ":
    if result.palette.colours.len >= MaximumAdobeSwatchColours:
      raise newException(ValueError, "Adobe ASE contains too many RGB colours")
    result.palette.colours.add VextRgba(
      r: rgbComponent(beFloat(data, offset)),
      g: rgbComponent(beFloat(data, offset + 4)),
      b: rgbComponent(beFloat(data, offset + 8)), a: 255)
    inc result.rgbColourCount
  else:
    inc result.unsupportedColourCount
  offset += components * 4
  let colourType = beWord(data, offset)
  if colourType notin 0 .. 2:
    raise newException(ValueError, "invalid Adobe ASE colour type")
  # Any remaining bytes are documented application-specific block data.

proc parseAdobeSwatchExchange*(data: openArray[byte]): AdobeSwatchExchange =
  if data.len < 12 or ascii(data, 0, 4) != AdobeSwatchExchangeMagic:
    raise newException(ValueError, "invalid Adobe Swatch Exchange signature")
  result.versionMajor = beWord(data, 4)
  result.versionMinor = beWord(data, 6)
  if result.versionMajor != 1 or result.versionMinor != 0:
    raise newException(ValueError, "unsupported Adobe Swatch Exchange version")
  result.blockCount = checkedInt(beDword(data, 8), "Adobe ASE block count")
  if result.blockCount > MaximumAdobeSwatchBlocks:
    raise newException(ValueError, "Adobe ASE contains too many blocks")

  var offset = 12
  for blockIndex in 0 ..< result.blockCount:
    if offset + 6 > data.len:
      raise newException(ValueError, "truncated Adobe ASE block header")
    let blockType = beWord(data, offset)
    let blockLength = checkedInt(beDword(data, offset + 2),
      "Adobe ASE block length")
    offset += 6
    if blockLength > data.len - offset:
      raise newException(ValueError, "truncated Adobe ASE block")
    let limit = offset + blockLength
    # The supplied RGB sample and article identify value 1 as a colour block.
    # Other length-delimited block types (including groups) need no decoding
    # to recover the ordered swatches.
    if blockType == 1:
      parseColourBlock(data, offset, limit, result)
    offset = limit
  if offset != data.len:
    raise newException(ValueError, "unexpected data after Adobe ASE blocks")
  if result.palette.colours.len > 0: result.palette.validate

proc isAdobeSwatchExchange*(data: openArray[byte]): bool =
  try:
    discard parseAdobeSwatchExchange(data)
    true
  except ValueError:
    false

proc hasAdobeSwatchExchangeExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".ase")
