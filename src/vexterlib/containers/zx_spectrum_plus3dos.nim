## Reusable validation for the optional 128-byte +3DOS file header.

const
  Plus3DosHeaderSize* = 128
  Plus3DosSignature* = "PLUS3DOS"
  Plus3DosSoftEof* = 0x1a'u8

type Plus3DosHeader* = object
  issue*: byte
  version*: byte
  fileLength*: uint32
  basicType*: byte
  basicFileLength*: uint16
  basicParameter1*: uint16
  basicParameter2*: uint16

proc littleWord(data: openArray[byte], offset: int): uint16 =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc littleDword(data: openArray[byte], offset: int): uint32 =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc parsePlus3DosHeader*(data: openArray[byte]): Plus3DosHeader =
  if data.len < Plus3DosHeaderSize:
    raise newException(ValueError, "+3DOS file is shorter than its 128-byte header")
  for index, expected in Plus3DosSignature:
    if data[index] != byte(expected):
      raise newException(ValueError, "+3DOS signature is missing")
  if data[8] != Plus3DosSoftEof:
    raise newException(ValueError, "+3DOS signature is not followed by soft EOF")
  result.issue = data[9]
  result.version = data[10]
  result.fileLength = littleDword(data, 11)
  if uint64(result.fileLength) != uint64(data.len):
    raise newException(ValueError,
      "+3DOS declared file length does not match the source length")
  result.basicType = data[15]
  result.basicFileLength = littleWord(data, 16)
  result.basicParameter1 = littleWord(data, 18)
  result.basicParameter2 = littleWord(data, 20)
  for index in 23 .. 126:
    if data[index] != 0:
      raise newException(ValueError, "+3DOS reserved header bytes must be zero")
  var checksum = 0
  for index in 0 .. 126: checksum = (checksum + int(data[index])) and 0xff
  if checksum != int(data[127]):
    raise newException(ValueError, "+3DOS header checksum does not match")

proc isPlus3DosHeader*(data: openArray[byte]): bool =
  try:
    discard parsePlus3DosHeader(data)
    true
  except ValueError:
    false
