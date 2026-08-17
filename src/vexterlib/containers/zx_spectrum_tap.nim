## Parser and screen-resource extraction for ZX Spectrum TAP containers.

import std/[strformat, strutils]
import ../archetypes/raster
import ./zx_spectrum_screen

const
  ZxSpectrumTapTypeId* = "zx-spectrum.tap"
  ZxSpectrumTapHeaderBlockSize* = 19
  ZxSpectrumTapHeaderFlag* = 0x00'u8
  ZxSpectrumTapDataFlag* = 0xff'u8
  ZxSpectrumTapCodeType* = 3'u8
  ZxSpectrumTapScreenAddress* = 16384
  ZxSpectrumTapCodeParameter2* = 32768

type
  ZxSpectrumTapBlock = object
    bytes: seq[byte]

  ZxSpectrumTapScreen* = object
    name*: string
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

proc parseZxSpectrumTapScreens*(data: openArray[byte]): seq[ZxSpectrumTapScreen] =
  ## Validates every TAP block and extracts adjacent CODE screen records.
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

      if header[1] == ZxSpectrumTapCodeType and
          declaredLength == ZxSpectrumScreenSize and
          littleEndianWord(header, 14) == ZxSpectrumTapScreenAddress and
          littleEndianWord(header, 16) == ZxSpectrumTapCodeParameter2:
        result.add ZxSpectrumTapScreen(
          name: asciiName(header),
          data: @payloadBlock[1 ..< payloadBlock.high])
      index += 2
    else:
      inc index

proc isZxSpectrumTap*(data: openArray[byte]): bool =
  try:
    discard parseZxSpectrumTapScreens(data)
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

proc decodeZxSpectrumTapScreen*(data: openArray[byte], path: string): VextRaster =
  decodeZxSpectrumScreen(extractZxSpectrumTapScreen(data, path))
