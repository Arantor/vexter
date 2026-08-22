## Standalone PP11/PP20 PowerPacker decompression.
##
## Ported from Ancient Format Decompressor's PPDecompressor,
## Copyright (c) 2017 Teemu Suutari, under the BSD 2-Clause License.

const
  PowerPackerTypeId* = "archive.powerpacker"
  PowerPackerMaxUnpackedSize = 512 * 1024 * 1024
  PowerPackerModes = [
    0x09090909'u32, 0x090a0a0a, 0x090a0b0b,
    0x090a0c0c, 0x090a0c0d]

type PowerPackerArchive* = object
  version*: string
  modeTable*: array[4, int]
  unpackedSize*: int
  startShift*: int
  data*: seq[byte]

proc ascii(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "truncated PowerPacker text field")
  for index in offset ..< offset + length:
    result.add char(data[index])

proc be32(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset > data.len - 4:
    raise newException(ValueError, "truncated PowerPacker 32-bit value")
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc parsePowerPacker*(data: openArray[byte]): PowerPackerArchive =
  if data.len < 16:
    raise newException(ValueError, "PowerPacker data is too short")
  result.version = ascii(data, 0, 4)
  if result.version notin ["PP11", "PP20"]:
    raise newException(ValueError, "PowerPacker data must begin with PP11 or PP20")
  let mode = be32(data, 4)
  if mode notin PowerPackerModes:
    raise newException(ValueError, "unsupported PowerPacker efficiency table")
  for index in 0 ..< 4:
    result.modeTable[index] = int((mode shr ((3 - index) * 8)) and 0xff)
  let trailer = be32(data, data.len - 4)
  result.unpackedSize = int(trailer shr 8)
  result.startShift = int(trailer and 0xff)
  if result.unpackedSize <= 0 or
      result.unpackedSize > PowerPackerMaxUnpackedSize:
    raise newException(ValueError, "invalid PowerPacker unpacked size")
  if result.startShift >= 32:
    raise newException(ValueError, "invalid PowerPacker initial bit shift")
  if data.len mod 4 != 0:
    raise newException(ValueError, "PowerPacker stream is not longword-aligned")
  result.data = @data

proc isPowerPacker*(data: openArray[byte]): bool =
  try:
    discard parsePowerPacker(data)
    true
  except ValueError:
    false

proc unpackPowerPacker*(archive: PowerPackerArchive): seq[byte] =
  var
    inputOffset = archive.data.len - 4
    bitBuffer: uint32
    bitCount = 0
    streamValid = true

  proc fillBits(): bool =
    if inputOffset < 12:
      return false
    inputOffset -= 4
    bitBuffer = be32(archive.data, inputOffset)
    bitCount = 32
    true

  if not fillBits():
    raise newException(ValueError, "truncated PowerPacker bitstream")
  bitBuffer = bitBuffer shr archive.startShift
  bitCount -= archive.startShift

  proc readBit(): int =
    if not streamValid:
      return 0
    if bitCount == 0 and not fillBits():
      streamValid = false
      return 0
    result = int(bitBuffer and 1)
    bitBuffer = bitBuffer shr 1
    dec bitCount

  proc readBits(count: int): int =
    for unused in 0 ..< count:
      result = (result shl 1) or readBit()

  result = newSeq[byte](archive.unpackedSize)
  var outputOffset = result.len
  while streamValid:
    if readBit() == 0:
      var count = 1
      while streamValid:
        let value = readBits(2)
        count += value
        if value < 3: break
      if not streamValid or count > outputOffset:
        streamValid = false
      else:
        for unused in 0 ..< count:
          dec outputOffset
          result[outputOffset] = byte(readBits(8))
    if outputOffset == 0:
      break
    let mode = readBits(2)
    var count, distance: int
    if mode == 3:
      let distanceBits = if readBit() != 0: archive.modeTable[mode] else: 7
      distance = readBits(distanceBits) + 1
      count = 5
      while streamValid:
        let value = readBits(3)
        count += value
        if value < 7: break
    else:
      count = mode + 2
      distance = readBits(archive.modeTable[mode]) + 1
    if count > outputOffset or distance > result.len - outputOffset:
      streamValid = false
    else:
      var sourceOffset = outputOffset + distance
      for unused in 0 ..< count:
        dec outputOffset
        dec sourceOffset
        result[outputOffset] = result[sourceOffset]
  if not streamValid or outputOffset != 0:
    raise newException(ValueError, "invalid PowerPacker compressed stream")

proc unpackPowerPacker*(data: openArray[byte]): seq[byte] =
  unpackPowerPacker(parsePowerPacker(data))
