## Validation and extraction for standalone AMOS sprite and icon banks.

import std/[os, strutils]
import ../archetypes/raster
import ../resources/amos_planar_image

const
  AmosSpriteBankMagic* = "AmSp"
  AmosIconBankMagic* = "AmIc"
  AmosSpriteBankTypeId* = "amos.sprite-bank"
  AmosIconBankTypeId* = "amos.icon-bank"
  AmosBankPaletteSize* = AmosPaletteEntries * 2
  AmosBankImageHeaderSize* = 10

type
  AmosSpriteIconBankKind* = enum
    asibkSprite
    asibkIcon

  AmosSpriteIconBank* = object
    kind*: AmosSpriteIconBankKind
    images*: seq[AmosPlanarImage]
    palette*: seq[VextRgb]

proc bigEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc signedBigEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  let value = bigEndianWord(data, offset)
  if value >= 0x8000: value - 0x10000 else: value

proc magic(data: openArray[byte]): string =
  if data.len < 4:
    return ""
  result = newString(4)
  for index in 0 ..< 4:
    result[index] = char(data[index])

proc parseLayout(data: openArray[byte], kind: AmosSpriteIconBankKind,
    imageCount, recordsOffset, recordsEnd, paletteOffset: int):
    AmosSpriteIconBank =
  result.kind = kind
  var offset = recordsOffset
  for imageIndex in 0 ..< imageCount:
    if offset + AmosBankImageHeaderSize > recordsEnd:
      raise newException(ValueError, "truncated AMOS sprite/icon image header")
    let
      widthWords = bigEndianWord(data, offset)
      height = bigEndianWord(data, offset + 2)
      depth = bigEndianWord(data, offset + 4)
      hotspotX = signedBigEndianWord(data, offset + 6)
      hotspotY = signedBigEndianWord(data, offset + 8)
    if widthWords <= 0 or height <= 0:
      raise newException(ValueError, "AMOS image dimensions must be positive")
    if depth < 1 or depth > 5:
      raise newException(ValueError, "AMOS image depth must be between 1 and 5")
    let planeDataSize = widthWords * 2 * height * depth
    offset += AmosBankImageHeaderSize
    if planeDataSize > recordsEnd - offset:
      raise newException(ValueError, "truncated AMOS sprite/icon planar data")
    result.images.add AmosPlanarImage(
      widthWords: widthWords,
      height: height,
      depth: depth,
      hotspotX: hotspotX,
      hotspotY: hotspotY,
      planeData: @data[offset ..< offset + planeDataSize])
    offset += planeDataSize

  if offset != recordsEnd:
    raise newException(ValueError, "unexpected data in AMOS sprite/icon bank")
  for index in 0 ..< AmosPaletteEntries:
    let value = bigEndianWord(data, paletteOffset + index * 2)
    result.palette.add VextRgb(
      r: uint8((value shr 8) and 0x0f) * 17,
      g: uint8((value shr 4) and 0x0f) * 17,
      b: uint8(value and 0x0f) * 17)

proc parseAmosSpriteIconBank*(data: openArray[byte]): AmosSpriteIconBank =
  let kind = case data.magic
    of AmosSpriteBankMagic: asibkSprite
    of AmosIconBankMagic: asibkIcon
    else: raise newException(ValueError,
      "invalid AMOS sprite/icon bank identifier")

  if data.len < 6 + AmosBankPaletteSize:
    raise newException(ValueError, "truncated AMOS sprite/icon bank")
  let imageCount = bigEndianWord(data, 4)
  try:
    return parseLayout(data, kind, imageCount, 6,
      data.len - AmosBankPaletteSize, data.len - AmosBankPaletteSize)
  except ValueError:
    return parseLayout(data, kind, imageCount, 6 + AmosBankPaletteSize,
      data.len, 6)

proc isAmosSpriteIconBank*(data: openArray[byte]): bool =
  try:
    discard parseAmosSpriteIconBank(data)
    true
  except ValueError:
    false

proc hasAmosSpriteIconBankExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".abk"

proc amosSpriteIconBankTypeId*(bank: AmosSpriteIconBank): string =
  case bank.kind
  of asibkSprite: AmosSpriteBankTypeId
  of asibkIcon: AmosIconBankTypeId
