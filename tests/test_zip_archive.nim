import std/[strutils, unittest]
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc addDword(data: var seq[byte], value: uint32) =
  data.add byte(value)
  data.add byte(value shr 8)
  data.add byte(value shr 16)
  data.add byte(value shr 24)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

type FixtureEntry = object
  name: string
  data: seq[byte]
  compression: int
  compressed: seq[byte]

proc zipFixture(entries: openArray[FixtureEntry]): seq[byte] =
  var central: seq[byte]
  for entry in entries:
    let localOffset = result.len
    let packed = if entry.compression == 0: entry.data else: entry.compressed
    result.addDword(0x04034b50'u32)
    result.addWord(20)
    result.addWord(0x800)
    result.addWord(entry.compression)
    result.addWord(0); result.addWord(0)
    result.addDword(crc32(entry.data))
    result.addDword(uint32(packed.len))
    result.addDword(uint32(entry.data.len))
    result.addWord(entry.name.len); result.addWord(0)
    for value in entry.name: result.add byte(value)
    result.add packed

    central.addDword(0x02014b50'u32)
    central.addWord(20); central.addWord(20)
    central.addWord(0x800); central.addWord(entry.compression)
    central.addWord(0); central.addWord(0)
    central.addDword(crc32(entry.data))
    central.addDword(uint32(packed.len))
    central.addDword(uint32(entry.data.len))
    central.addWord(entry.name.len); central.addWord(0); central.addWord(0)
    central.addWord(0); central.addWord(0); central.addDword(0)
    central.addDword(uint32(localOffset))
    for value in entry.name: central.add byte(value)
  let centralOffset = result.len
  result.add central
  result.addDword(0x06054b50'u32)
  result.addWord(0); result.addWord(0)
  result.addWord(entries.len); result.addWord(entries.len)
  result.addDword(uint32(central.len)); result.addDword(uint32(centralOffset))
  result.addWord(0)

suite "ZIP archives":
  test "stored entries form a hierarchy and recognized files open recursively":
    let archive = zipFixture([
      FixtureEntry(name: "docs/readme.txt", data: @[byte('h'), byte('i')]),
      FixtureEntry(name: "images/display.scr",
        data: newSeq[byte](ZxSpectrumScreenSize))])
    let parsed = parseZipArchive(archive)
    let candidates = detectFormats("collection.ZIP", archive)
    let inspection = inspectSource("collection.ZIP", archive)
    let leaves = inspection.resources.leafResources
    check parsed.entries.len == 2
    check candidates[0].typeId == ZipArchiveTypeId
    check candidates[0].confidence == vdcCertain
    check leaves.len == 2
    check leaves[0].path == "/archive/docs/readme.txt"
    check leaves[0].data.len == 0
    check leaves[0].resourceBytes == @[byte('h'), byte('i')]
    check leaves[1].path == "/archive/images/display.scr"
    check leaves[1].kind == vrnkOpaque
    check decodeResourceOnDemand(leaves[1]) == vddDecoded
    check leaves[1].children[0].path ==
      "/archive/images/display.scr/screen"
    check leaves[1].children[0].kind == vrnkRaster

  test "DEFLATE entries are expanded and checked":
    # Raw DEFLATE for "hello" (generated locally with zlib).
    let archive = zipFixture([FixtureEntry(name: "hello.txt",
      data: @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')],
      compression: 8, compressed: @[0xcb'u8, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00])])
    let parsed = parseZipArchive(archive)
    check extractZipEntry(archive, parsed.entries[0]) ==
      @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]

  test "a contained decoder failure does not invalidate its ZIP carrier":
    var brokenPcx = newSeq[byte](128)
    brokenPcx[0] = 0x0a
    brokenPcx[1] = 5
    brokenPcx[2] = 1
    brokenPcx[3] = 8
    brokenPcx[65] = 1
    brokenPcx[66] = 2
    brokenPcx[68] = 1
    let archive = zipFixture([
      FixtureEntry(name: "broken.pcx", data: brokenPcx),
      FixtureEntry(name: "readme.txt", data: @[byte('o'), byte('k')])])
    let inspection = inspectSource("mixed.zip", archive)
    check inspection.selectedFormat.typeId == ZipArchiveTypeId
    check inspection.warnings.len == 0
    let failed = inspection.resources.leafResources[0]
    check failed.path == "/archive/broken.pcx"
    check failed.kind == vrnkOpaque
    check decodeResourceOnDemand(failed) == vddFailed
    check failed.failureFormat == PcxTypeId
    check "truncated PCX image data" in failed.failureMessage
    check failed.rawDataAvailable
    check inspection.resources.leafResources[1].path == "/archive/readme.txt"

  test "member checksum damage is isolated until materialization":
    var archive = zipFixture([
      FixtureEntry(name: "bad.bin", data: @[1'u8, 2, 3])])
    archive[30 + "bad.bin".len] = 9
    let parsed = parseZipArchive(archive)
    check parsed.entries.len == 1
    let inspection = inspectSource("damaged.zip", archive)
    let member = inspection.resources.leafResources[0]
    check member.failureMessage.len == 0
    check decodeResourceOnDemand(member) == vddFailed
    check "CRC-32" in member.failureMessage

  test "unsafe, duplicate, and overlong paths are rejected":
    expect ValueError:
      discard parseZipArchive(zipFixture([
        FixtureEntry(name: "../escape", data: @[1'u8])]))
    expect ValueError:
      discard parseZipArchive(zipFixture([
        FixtureEntry(name: "same", data: @[1'u8]),
        FixtureEntry(name: "same", data: @[2'u8])]))
    expect ValueError:
      discard parseZipArchive(zipFixture([
        FixtureEntry(name: repeat('x', 256), data: @[1'u8])]))

  test "random-access sessions index and enumerate without reading payloads":
    let archive = zipFixture([FixtureEntry(name: "large.bin",
      data: newSeq[byte](100_000))])
    let payloadStart = 30 + "large.bin".len
    var payloadRead = false
    let source = newByteSource(archive.len,
      proc(offset, length: int): seq[byte] =
        if offset < payloadStart + 100_000 and offset + length > payloadStart:
          payloadRead = true
        result = archive[offset ..< offset + length])
    let session = openInspectionSession("large.zip",
      newSourceCollection(source))
    check session.selectedFormat.typeId == ZipArchiveTypeId
    check not payloadRead
    let roots = session.rootDescriptors
    check roots.len == 1
    let children = session.expandResource(roots[0].id).children
    check children.len == 1
    check children[0].path == "/archive/large.bin"
    check not payloadRead
    discard session.loadResource(children[0].id)
    check payloadRead
    session.close()

  test "a caller can override the working limit for one materialization":
    let archive = zipFixture([FixtureEntry(name: "large.bin",
      data: newSeq[byte](100_000))])
    var limits = defaultWorkLimits()
    limits.maximumWorkingBytes = 50_000
    let session = openInspectionSession("large.zip",
      newSourceCollection(memoryByteSource(archive)), limits = limits)
    let member = session.expandResource(session.rootDescriptors[0].id).children[0]
    var message = ""
    try:
      discard session.loadResource(member.id)
    except VextWorkLimitError as error:
      message = error.msg
    check "100000 bytes" in message
    check "50000 bytes" in message
    let loaded = session.loadResource(member.id,
      maximumWorkingBytes = member.estimatedBytes)
    check loaded.data.len == 100_000
    session.close()

  test "export names are host-independent":
    check normalizedZipExportName("report:2026?.txt") == "report_2026_.txt"
    check normalizedZipExportName("CON") == "_CON"
    check normalizedZipExportName("trailing. ") == "trailing"
