import std/unittest
import vexterlib

proc addBe(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc crc16(data: openArray[byte]): uint16 =
  for value in data:
    result = result xor uint16(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xa001'u16 else: 0'u16)

proc lhaMember(name: string, payload: seq[byte]): seq[byte] =
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
  for index in 2 ..< result.len: result[1] = result[1] + result[index]
  result.add payload

proc executable(): seq[byte] =
  result.addBe(1011) # HUNK_HEADER
  result.addBe(0)    # resident names terminator
  result.addBe(1); result.addBe(0); result.addBe(0)
  result.addBe(1)    # one-longword allocation table entry
  result.addBe(1001); result.addBe(1)
  result.add @[1'u8, 2, 3, 4]
  result.addBe(1010) # HUNK_END

suite "Amiga Hunk executables and LHA self-extractors":
  test "minimal load file exposes its code hunk":
    let source = executable()
    let parsed = parseAmigaHunkExecutable(source)
    let inspection = inspectSource("program", source)
    check parsed.executableLength == source.len
    check parsed.hunks.len == 1
    check parsed.hunks[0].data == @[1'u8, 2, 3, 4]
    check inspection.selectedFormat.typeId == AmigaHunkExecutableTypeId
    check inspection.resources.leafResources[0].path == "/executable/hunks/0"

  test "appended usage and main archives select the SFX handler":
    var source = executable()
    source.add lhaMember("usage.txt", @[byte('u')])
    source.add @[0'u8, 0]
    source.add lhaMember("payload.bin", @[byte('p')])
    source.add 0
    let parsed = parseAmigaLhaSfx(source)
    let candidates = detectFormats("archive.run", source)
    let inspection = inspectSource("archive.run", source)
    check parsed.usageArchive.entries[0].data == @[byte('u')]
    check parsed.archive.entries[0].data == @[byte('p')]
    check candidates[0].typeId == AmigaLhaSfxTypeId
    check candidates[1].typeId == AmigaHunkExecutableTypeId
    check inspection.resources.leafResources[^1].path == "/archive/payload.bin"
