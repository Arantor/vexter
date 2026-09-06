import std/unittest
import vexterlib

proc crc16(data: openArray[byte]): uint16 =
  for value in data:
    result = result xor uint16(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xa001'u16 else: 0'u16)

proc storedMember(name: string, payload: seq[byte]): seq[byte] =
  let headerSize = 22 + name.len
  result = newSeq[byte](headerSize + 2)
  result[0] = byte(headerSize)
  for index, value in "-lh0-": result[2 + index] = byte(value)
  for index in 0 ..< 4:
    result[7 + index] = byte(uint32(payload.len) shr (index * 8))
    result[11 + index] = byte(uint32(payload.len) shr (index * 8))
  result[20] = 0
  result[21] = byte(name.len)
  for index, value in name: result[22 + index] = byte(value)
  let crc = crc16(payload)
  result[22 + name.len] = byte(crc)
  result[23 + name.len] = byte(crc shr 8)
  for index in 2 ..< result.len: result[1] += result[index]
  result.add payload

suite "Amiga LHA paths":
  test "byte 0xff separators form a recursive hierarchy":
    let separator = $char(0xff)
    var archive = storedMember("View3.2.info", @[byte('i')])
    archive.add storedMember("View3.2" & separator & "ReadMe", @[byte('r')])
    archive.add 0

    let parsed = parseLhaArchive(archive)
    check parsed.entries[0].name == "View3.2.info"
    check parsed.entries[1].name == "View3.2/ReadMe"
    check parsed.entries[1].segments == @["View3.2", "ReadMe"]

    let indexed = indexLhaArchive(memoryByteSource(archive))
    check indexed.entries[0].name == "View3.2.info"
    check indexed.entries[1].name == "View3.2/ReadMe"
    check indexed.entries[1].segments == @["View3.2", "ReadMe"]
