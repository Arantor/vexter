## Validation and identification for generic standalone AMOS banks.

import std/[os, strutils]

const
  AmosBankMagic* = "AmBk"
  AmosBankTypeId* = "amos.bank"
  AmosBankResourceTypeId* = "amos.bank-data"
  AmosBankHeaderSize* = 20
  AmosBankStoredLengthOverhead* = 8
  AmosBankLengthMask* = 0x0fffffff'u32

type
  AmosBank* = object
    number*: int
    flags*: int
    bankType*: string
    dataLength*: int

proc bigEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc bigEndianDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or
    (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or
    uint32(data[offset + 3])

proc parseAmosBank*(data: openArray[byte]): AmosBank =
  if data.len < AmosBankHeaderSize:
    raise newException(ValueError, "truncated generic AMOS bank")
  for index, value in AmosBankMagic:
    if data[index] != byte(value):
      raise newException(ValueError, "invalid generic AMOS bank identifier")

  result.number = bigEndianWord(data, 4)
  result.flags = bigEndianWord(data, 6)
  let storedLength = int(bigEndianDword(data, 8) and AmosBankLengthMask)
  if storedLength < AmosBankStoredLengthOverhead:
    raise newException(ValueError, "invalid generic AMOS bank length")
  result.dataLength = storedLength - AmosBankStoredLengthOverhead
  if result.dataLength != data.len - AmosBankHeaderSize:
    raise newException(ValueError,
      "generic AMOS bank data length does not match its header")

  for offset in 12 ..< 20:
    if data[offset] > 0x7f:
      raise newException(ValueError, "AMOS bank type is not ASCII")
    result.bankType.add char(data[offset])
  result.bankType = result.bankType.strip(
    leading = false, trailing = true, chars = {' '})

proc isAmosBank*(data: openArray[byte]): bool =
  try:
    discard parseAmosBank(data)
    true
  except ValueError:
    false

proc hasAmosBankExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".abk"

