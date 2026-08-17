## Validation and extraction for AMOS bank sets.

import std/[os, strutils]
import ./[amos_bank, amos_sprite_icon_bank]

const
  AmosBankSetMagic* = "AmBs"
  AmosBankSetTypeId* = "amos.bank-set"
  AmosBankSetHeaderSize* = 6

type
  AmosBankSetEntryKind* = enum
    absekGeneric
    absekSprite
    absekIcon

  AmosBankSetEntry* = object
    kind*: AmosBankSetEntryKind
    genericBank*: AmosBank
    spriteIconBank*: AmosSpriteIconBank

  AmosBankSet* = object
    banks*: seq[AmosBankSetEntry]

  AmosBankSetParseResult* = object
    bankSet*: AmosBankSet
    bytesRead*: int

proc magicAt(data: openArray[byte], offset: int): string =
  if offset > data.len - 4:
    return ""
  result = newString(4)
  for index in 0 ..< 4:
    result[index] = char(data[offset + index])

proc bigEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc parseAmosBankSetPrefix*(data: openArray[byte]): AmosBankSetParseResult =
  if data.len < AmosBankSetHeaderSize or data.magicAt(0) != AmosBankSetMagic:
    raise newException(ValueError, "invalid or truncated AMOS bank set")

  let bankCount = bigEndianWord(data, 4)
  var offset = AmosBankSetHeaderSize
  for index in 0 ..< bankCount:
    if offset > data.len - 4:
      raise newException(ValueError, "truncated AMOS bank set member")
    case data.magicAt(offset)
    of AmosBankMagic:
      let parsed = parseAmosBankPrefix(data.toOpenArray(offset, data.high))
      result.bankSet.banks.add AmosBankSetEntry(
        kind: absekGeneric,
        genericBank: parsed.bank)
      offset += parsed.bytesRead
    of AmosSpriteBankMagic, AmosIconBankMagic:
      let parsed = parseAmosSpriteIconBankPrefix(
        data.toOpenArray(offset, data.high))
      result.bankSet.banks.add AmosBankSetEntry(
        kind: if parsed.bank.kind == asibkSprite: absekSprite else: absekIcon,
        spriteIconBank: parsed.bank)
      offset += parsed.bytesRead
    else:
      raise newException(ValueError,
        "unsupported bank identifier in AMOS bank set")
  result.bytesRead = offset

proc parseAmosBankSet*(data: openArray[byte]): AmosBankSet =
  let parsed = parseAmosBankSetPrefix(data)
  if parsed.bytesRead != data.len:
    raise newException(ValueError, "unexpected data after AMOS bank set")
  parsed.bankSet

proc isAmosBankSet*(data: openArray[byte]): bool =
  try:
    discard parseAmosBankSet(data)
    true
  except ValueError:
    false

proc hasAmosBankSetExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".abs"

