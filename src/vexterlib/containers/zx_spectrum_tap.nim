## Parser and screen-resource extraction for ZX Spectrum TAP containers.

import std/[strformat, strutils]
import ../resources/zx_spectrum_screen
import ../resources/zx_spectrum_basic

const
  ZxSpectrumTapTypeId* = "zx-spectrum.tap"
  ZxSpectrumTapCodeTypeId* = "zx-spectrum.code"
  ZxSpectrumTapCodeResourcePath* = "/code"
  ZxSpectrumTapNumberArrayTypeId* = "zx-spectrum.number-array"
  ZxSpectrumTapNumberArrayResourcePath* = "/number-array"
  ZxSpectrumTapCharacterArrayTypeId* = "zx-spectrum.character-array"
  ZxSpectrumTapCharacterArrayResourcePath* = "/character-array"
  ZxSpectrumTapHeaderBlockSize* = 19
  ZxSpectrumTapHeaderFlag* = 0x00'u8
  ZxSpectrumTapDataFlag* = 0xff'u8
  ZxSpectrumTapCodeType* = 3'u8
  ZxSpectrumTapProgramType* = 0'u8
  ZxSpectrumTapNumberArrayType* = 1'u8
  ZxSpectrumTapCharacterArrayType* = 2'u8
  ZxSpectrumTapScreenAddress* = 16384
  ZxSpectrumTapCodeParameter2* = 32768

type
  ZxSpectrumTapBlock = object
    bytes: seq[byte]

  ZxSpectrumTapScreen* = object
    name*: string
    data*: seq[byte]

  ZxSpectrumTapBasic* = object
    name*: string
    data*: seq[byte]

  ZxSpectrumTapCode* = object
    name*: string
    startAddress*: int
    declaredLength*: int
    parameter2*: int
    data*: seq[byte]

  ZxSpectrumTapRecordKind* = enum
    ztrkProgram
    ztrkNumberArray
    ztrkCharacterArray
    ztrkScreen
    ztrkCode

  ZxSpectrumTapRecord* = object
    kind*: ZxSpectrumTapRecordKind
    name*: string
    startAddress*: int
    declaredLength*: int
    parameter2*: int
    data*: seq[byte]

proc littleEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc parseBlocks(data: openArray[byte]): seq[ZxSpectrumTapBlock] =
  var offset = 0
  while offset < data.len:
    if data.len - offset < 2:
      raise newException(ValueError, "truncated ZX Spectrum TAP block length")
    let blockSize = littleEndianWord(data, offset)
    offset += 2
    if blockSize < 2:
      raise newException(ValueError,
        "ZX Spectrum TAP block must include a flag and checksum")
    if blockSize > data.len - offset:
      raise newException(ValueError, "truncated ZX Spectrum TAP block")

    var checksum = 0'u8
    for index in offset ..< offset + blockSize:
      checksum = checksum xor data[index]
    if checksum != 0:
      raise newException(ValueError, "invalid ZX Spectrum TAP block checksum")

    result.add ZxSpectrumTapBlock(bytes: @data[offset ..< offset + blockSize])
    offset += blockSize

  if result.len == 0:
    raise newException(ValueError, "ZX Spectrum TAP contains no blocks")

proc asciiName(headerBytes: openArray[byte]): string =
  ## Non-ASCII filename bytes are ignored until Spectrum tokenising is added.
  for index in 2 .. 11:
    if headerBytes[index] <= 0x7f:
      result.add char(headerBytes[index])
  result = result.strip(leading = false, trailing = true, chars = {' '})

proc parseZxSpectrumTapRecords*(data: openArray[byte]):
    seq[ZxSpectrumTapRecord] =
  ## Validates every TAP block and returns supported header/data records in
  ## their physical tape order. Array records remain valid but unrepresented.
  let blocks = parseBlocks(data)
  var index = 0
  while index < blocks.len:
    let header = blocks[index].bytes
    if header.len == ZxSpectrumTapHeaderBlockSize and
        header[0] == ZxSpectrumTapHeaderFlag:
      let declaredLength = littleEndianWord(header, 12)
      if index + 1 >= blocks.len:
        raise newException(ValueError,
          "ZX Spectrum TAP header is missing its data block")
      let payloadBlock = blocks[index + 1].bytes
      if payloadBlock[0] != ZxSpectrumTapDataFlag:
        raise newException(ValueError,
          "ZX Spectrum TAP header is not followed by a data block")
      if payloadBlock.len != declaredLength + 2:
        raise newException(ValueError,
          "ZX Spectrum TAP data length does not match its header")

      let
        startAddress = littleEndianWord(header, 14)
        parameter2 = littleEndianWord(header, 16)
        payload = @payloadBlock[1 ..< payloadBlock.high]
      if header[1] == ZxSpectrumTapProgramType:
        discard decodeZxSpectrumBasic(payload)
        result.add ZxSpectrumTapRecord(kind: ztrkProgram,
          name: asciiName(header), declaredLength: declaredLength,
          startAddress: startAddress, parameter2: parameter2, data: payload)
      elif header[1] == ZxSpectrumTapNumberArrayType:
        result.add ZxSpectrumTapRecord(kind: ztrkNumberArray,
          name: asciiName(header), declaredLength: declaredLength,
          startAddress: startAddress, parameter2: parameter2, data: payload)
      elif header[1] == ZxSpectrumTapCharacterArrayType:
        result.add ZxSpectrumTapRecord(kind: ztrkCharacterArray,
          name: asciiName(header), declaredLength: declaredLength,
          startAddress: startAddress, parameter2: parameter2, data: payload)
      elif header[1] == ZxSpectrumTapCodeType:
        let recordKind = if declaredLength == ZxSpectrumScreenSize and
            startAddress == ZxSpectrumTapScreenAddress:
          ztrkScreen
        else:
          ztrkCode
        result.add ZxSpectrumTapRecord(kind: recordKind,
          name: asciiName(header), declaredLength: declaredLength,
          startAddress: startAddress, parameter2: parameter2, data: payload)
      index += 2
    else:
      inc index

proc parseZxSpectrumTapScreens*(data: openArray[byte]): seq[ZxSpectrumTapScreen] =
  ## Extracts CODE records with the canonical screen length and load address.
  for record in parseZxSpectrumTapRecords(data):
    if record.kind == ztrkScreen:
      result.add ZxSpectrumTapScreen(name: record.name, data: record.data)

proc parseZxSpectrumTapBasic*(data: openArray[byte]): seq[ZxSpectrumTapBasic] =
  ## Validates the TAP and extracts adjacent Program header/data records. The
  ## decoder uses the BASIC line boundary, so any saved variables may remain in
  ## the returned payload without being rendered as source.
  for record in parseZxSpectrumTapRecords(data):
    if record.kind == ztrkProgram:
      result.add ZxSpectrumTapBasic(name: record.name, data: record.data)

proc parseZxSpectrumTapCode*(data: openArray[byte]): seq[ZxSpectrumTapCode] =
  ## Validates the TAP and extracts CODE records which are not Spectrum screen
  ## dumps. Screen-shaped CODE records continue through the raster pathway.
  for record in parseZxSpectrumTapRecords(data):
    if record.kind == ztrkCode:
      result.add ZxSpectrumTapCode(
        name: record.name,
        startAddress: record.startAddress,
        declaredLength: record.declaredLength,
        parameter2: record.parameter2,
        data: record.data)

proc isZxSpectrumTap*(data: openArray[byte]): bool =
  try:
    discard parseZxSpectrumTapRecords(data)
    true
  except ValueError:
    false

proc zxSpectrumTapScreenPaths*(data: openArray[byte]): seq[string] =
  let screens = parseZxSpectrumTapScreens(data)
  if screens.len == 1:
    return @[ZxSpectrumScreenResourcePath]
  for index in 0 ..< screens.len:
    result.add &"{ZxSpectrumScreenResourcePath}/{index + 1}"

proc extractZxSpectrumTapScreen*(data: openArray[byte], path: string): seq[byte] =
  let screens = parseZxSpectrumTapScreens(data)
  if screens.len == 1 and path == ZxSpectrumScreenResourcePath:
    return screens[0].data
  for index in 0 ..< screens.len:
    if path == &"{ZxSpectrumScreenResourcePath}/{index + 1}":
      return screens[index].data
  raise newException(ValueError, "resource was not found: " & path)
