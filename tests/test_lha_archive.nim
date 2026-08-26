import std/[strutils, unittest]
import vexterlib

proc bytes(hex: string): seq[byte] =
  var cleaned = hex.replace(" ").replace("\n")
  for index in countup(0, cleaned.high, 2):
    result.add byte(parseHexInt(cleaned[index .. index + 1]))

proc crc16(data: openArray[byte]): uint16 =
  for value in data:
    result = result xor uint16(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xa001'u16 else: 0'u16)

proc levelZero(compressionMethod, name: string,
    raw, packed: seq[byte]): seq[byte] =
  let headerSize = 22 + name.len
  result = newSeq[byte](headerSize + 2)
  result[0] = byte(headerSize)
  for index, value in compressionMethod: result[2 + index] = byte(value)
  for index in 0 ..< 4:
    result[7 + index] = byte(uint32(packed.len) shr (index * 8))
    result[11 + index] = byte(uint32(raw.len) shr (index * 8))
  result[20] = 0
  result[21] = byte(name.len)
  for index, value in name: result[22 + index] = byte(value)
  let crc = crc16(raw)
  result[22 + name.len] = byte(crc)
  result[23 + name.len] = byte(crc shr 8)
  for index in 2 ..< result.len:
    result[1] = result[1] + result[index]
  result.add packed

proc levelOne(compressionMethod, name: string,
    raw, packed: seq[byte]): seq[byte] =
  let headerSize = 25 + name.len
  result = newSeq[byte](headerSize + 2)
  result[0] = byte(headerSize)
  for index, value in compressionMethod: result[2 + index] = byte(value)
  for index in 0 ..< 4:
    result[7 + index] = byte(uint32(packed.len) shr (index * 8))
    result[11 + index] = byte(uint32(raw.len) shr (index * 8))
  result[20] = 1
  result[21] = byte(name.len)
  for index, value in name: result[22 + index] = byte(value)
  let crc = crc16(raw)
  result[22 + name.len] = byte(crc)
  result[23 + name.len] = byte(crc shr 8)
  result[24 + name.len] = byte('A')
  # The final two bytes are the zero next-extended-header size.
  for index in 2 ..< result.len:
    result[1] = result[1] + result[index]
  result.add packed

suite "LHA archives":
  test "level-0 LH0 entries form a safe recursive hierarchy":
    var archive = levelZero("-lh0-", "images\\display.scr",
      newSeq[byte](ZxSpectrumScreenSize), newSeq[byte](ZxSpectrumScreenSize))
    archive.add 0
    let parsed = parseLhaArchive(archive)
    let inspection = inspectSource("collection.lha", archive)
    check parsed.entries.len == 1
    check parsed.entries[0].name == "images/display.scr"
    check inspection.selectedFormat.typeId == LhaArchiveTypeId
    check inspection.resources.leafResources[0].path ==
      "/archive/images/display.scr/screen"

  test "authentic Aminet LH5 member expands byte-identically":
    # anim/CareTaker.ma.snd from caretake.lha, sourced from Aminet. The packed
    # bytes, level-0 header, CRC, and independently extracted result are kept
    # together so this routine test does not depend on the research archive.
    var archive = bytes("""
      2bf52d6c68352d370000001a010000cdae4121000015616e696d5c4361726554
      616b65722e6d612e736e6488e4
      002c4b6f49f8cee0b75aed5fe12145a2364a01455918431dfd2f98e9121d7d
      9108f669ade543f1c23c3ae2a76f69e23add30af32660e00""")
    archive.add 0
    var expected = bytes("""
      0001000100024946462d53616d706c6500000000000000000000537461727472
      656b3a534e442f4361726554616b65722e496666000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000000000000000000000""")
    expected.setLen(282)
    let parsed = parseLhaArchive(archive)
    check parsed.entries.len == 1
    check parsed.entries[0].compressionMethod == "-lh5-"
    check parsed.entries[0].data == expected

  test "level-1 headers feed the same member decoders":
    var archive = levelOne("-lh0-", "level-one.txt",
      @[byte('o'), byte('k')], @[byte('o'), byte('k')])
    archive.add 0
    let parsed = parseLhaArchive(archive)
    check parsed.entries.len == 1
    check parsed.entries[0].name == "level-one.txt"
    check parsed.entries[0].data == @[byte('o'), byte('k')]

  test "session indexing skips LHA payloads until materialization":
    let raw = newSeq[byte](100_000)
    var archive = levelZero("-lh0-", "large.bin", raw, raw)
    archive.add 0
    let payloadStart = 24 + "large.bin".len
    var payloadRead = false
    let source = newByteSource(archive.len,
      proc(offset, length: int): seq[byte] =
        if offset < payloadStart + raw.len and offset + length > payloadStart:
          payloadRead = true
        result = archive[offset ..< offset + length])
    let session = openInspectionSession("large.lha",
      newSourceCollection(source))
    check session.selectedFormat.typeId == LhaArchiveTypeId
    check not payloadRead
    let child = session.expandResource(session.rootDescriptors[0].id).
      children[0]
    check not payloadRead
    discard session.loadResource(child.id)
    check payloadRead
    session.close()

  test "checksums, traversal, unsupported methods, and truncation fail":
    var valid = levelZero("-lh0-", "safe", @[1'u8], @[1'u8])
    valid.add 0
    var badHeader = valid
    badHeader[1] = badHeader[1] xor 1
    expect ValueError: discard parseLhaArchive(badHeader)
    expect ValueError:
      var unsafe = levelZero("-lh0-", "..\\escape", @[1'u8], @[1'u8])
      unsafe.add 0
      discard parseLhaArchive(unsafe)
    expect ValueError:
      var unsupported = levelZero("-lh1-", "file", @[1'u8], @[1'u8])
      unsupported.add 0
      check detectFormats("old.lzh", unsupported)[0].typeId == LhaArchiveTypeId
      expect ValueError:
        discard inspectSource("old.lzh", unsupported)
      discard parseLhaArchive(unsupported)
    expect ValueError: discard parseLhaArchive(valid[0 ..< valid.high - 1])
