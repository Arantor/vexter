## Validation and bank-appendix extraction for tokenised AMOS programs.

import std/[os, strutils]
import ./amos_bank_set

const
  AmosProgramTypeId* = "amos.program"
  AmosListingResourceTypeId* = "amos.tokenised-listing"
  AmosProgramHeaderSize* = 16
  AmosProgramListingLengthSize* = 4
  AmosProgramContentOffset* = AmosProgramHeaderSize +
    AmosProgramListingLengthSize
  AmosProfessionalHeaderPrefix* = "AMOS Pro"
  AmosBasicHeaderPrefix* = "AMOS Basic"

type
  AmosProgram* = object
    header*: string
    listingLength*: int
    listingData*: seq[byte]
    bankSet*: AmosBankSet

proc bigEndianDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or
    (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or
    uint32(data[offset + 3])

proc parseAmosProgram*(data: openArray[byte]): AmosProgram =
  if data.len < AmosProgramContentOffset + AmosBankSetHeaderSize:
    raise newException(ValueError, "truncated AMOS program")

  result.header = newString(AmosProgramHeaderSize)
  for index in 0 ..< AmosProgramHeaderSize:
    if data[index] > 0x7f:
      raise newException(ValueError, "AMOS program header is not ASCII")
    result.header[index] = char(data[index])
  if not (result.header.startsWith(AmosProfessionalHeaderPrefix) or
      result.header.startsWith(AmosBasicHeaderPrefix)):
    raise newException(ValueError, "invalid AMOS program header")
  result.header = result.header.strip(
    leading = false, trailing = true, chars = {' ', '\0'})

  let encodedLength = bigEndianDword(data, AmosProgramHeaderSize)
  if encodedLength > uint32(data.len - AmosProgramContentOffset):
    raise newException(ValueError, "truncated tokenised AMOS listing")
  result.listingLength = int(encodedLength)
  let bankSetOffset = AmosProgramContentOffset + result.listingLength
  if bankSetOffset > data.len - AmosBankSetHeaderSize:
    raise newException(ValueError, "AMOS program is missing its bank appendix")
  result.listingData = @data[AmosProgramContentOffset ..< bankSetOffset]
  result.bankSet = parseAmosBankSet(
    data.toOpenArray(bankSetOffset, data.high))

proc isAmosProgram*(data: openArray[byte]): bool =
  try:
    discard parseAmosProgram(data)
    true
  except ValueError:
    false

proc hasAmosProgramExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".amos"
