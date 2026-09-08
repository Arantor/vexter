import std/[os, sequtils, unittest]
import vexterlib/[detection, operations]
import vexterlib/[byte_sources, inspection_sessions]
import vexterlib/containers/inno_setup

proc put16(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value); data[offset + 1] = byte(value shr 8)

proc put32(data: var seq[byte], offset: int, value: uint32) =
  for index in 0 .. 3: data[offset + index] = byte(value shr (index * 8))

proc putText(data: var seq[byte], offset: int, value: string) =
  for index, character in value: data[offset + index] = byte(character)

proc legacyFixture(): seq[byte] =
  result = newSeq[byte](0x280)
  result.putText(0, "MZ")
  result.put32(0x30, 0x6f6e6e49'u32)
  result.put32(0x34, 0x80); result.put32(0x38, not 0x80'u32)
  result.putText(0x80, "rDlPtS07\x87eVx")
  result.put32(0x80 + 16, 0); result.put32(0x80 + 20, 0)
  result.put32(0x80 + 24, 0); result.put32(0x80 + 28, 0x100)
  result.put32(0x80 + 32, 0x200)
  result.putText(0x100, "Inno Setup Setup Data (4.1.6)")
  # Two empty version-4.0.9+ framed setup-header streams.
  result[0x100 + 64 + 8] = 0
  result[0x100 + 64 + 9 + 8] = 0
  result.putText(0x200, "payload")

proc modernFixture(): seq[byte] =
  result = newSeq[byte](0x800)
  result.putText(0, "MZ"); result.put32(0x3c, 0x80)
  result.putText(0x80, "PE\0\0"); result.put16(0x86, 1)
  result.put16(0x94, 0xe0); result.put16(0x98, 0x10b)
  result.put32(0x98 + 96 + 16, 0x1000)
  result.put32(0x98 + 96 + 20, 0x100)
  let section = 0x80 + 24 + 0xe0
  result.putText(section, ".rsrc"); result.put32(section + 8, 0x200)
  result.put32(section + 12, 0x1000); result.put32(section + 16, 0x200)
  result.put32(section + 20, 0x200)
  result.put16(0x20e, 1); result.put32(0x210, 10)
  result.put32(0x214, 0x80000020'u32)
  result.put16(0x22e, 1); result.put32(0x230, 11111)
  result.put32(0x234, 0x80000040'u32)
  result.put16(0x24e, 1); result.put32(0x250, 1033)
  result.put32(0x254, 0x60); result.put32(0x260, 0x1080)
  result.put32(0x264, 44)
  result.putText(0x280, "rDlPtS\xcd\xe6\xd7{\x0b*")
  result.put32(0x28c, 1); result.put32(0x294, 0)
  result.put32(0x298, 0); result.put32(0x29c, 0)
  result.put32(0x2a0, 0x400); result.put32(0x2a4, 0)
  result.putText(0x400, "Inno Setup Setup Data (6.3.0)")
  result[0x400 + 64 + 8] = 0
  result[0x400 + 64 + 9 + 8] = 0
  result.putText(0x600, "data")

suite "Inno Setup":
  test "supplied Unicode sample exposes named file and data tables":
    let sample = "innoextract-samples/setup_superfrog_2.0.0.7.exe"
    if fileExists(sample):
      let encoded = readFile(sample)
      let source = newByteSource(encoded.len,
        proc(offset, length: int): seq[byte] =
          result = newSeq[byte](length)
          for index in 0 ..< length:
            result[index] = byte(encoded[offset + index]))
      defer: source.close()
      let installer = indexInnoSetup(source)
      let manifest = parseInnoSetupManifest(
        decodeInnoSetupHeaders(source, installer), installer.setupVersion)
      check manifest.files.len == manifest.counts.files
      check manifest.dataEntries.len == manifest.counts.dataEntries
      check manifest.compression == iscLzma2
      check manifest.files.anyIt(it.destination.len > 0 and it.location >= 0)
      let file = manifest.files.filterIt(it.location >= 0)[0]
      let entry = manifest.dataEntries[file.location]
      var chunkOutput = 0'i64
      for candidate in manifest.dataEntries:
        if candidate.firstSlice == entry.firstSlice and
            candidate.chunkOffset == entry.chunkOffset:
          chunkOutput = max(chunkOutput,
            candidate.fileOffset + candidate.fileSize)
      let chunk = decodeInnoSetupChunk(source, installer.dataOffset, entry,
        int(chunkOutput))
      let payload = extractInnoSetupFile(chunk, file, entry)
      check payload.len == int(entry.fileSize)
      check payload.len >= 2 and payload[0] == byte('M') and
        payload[1] == byte('Z')

  test "legacy loader pointer is detected and exposed as bounded regions":
    let data = legacyFixture()
    let installer = parseInnoSetup(data)
    check installer.loaderVersion == "4.1.6"
    check installer.setupVersion == "Inno Setup Setup Data (4.1.6)"
    check installer.headerOffset == 0x100
    check installer.dataOffset == 0x200
    check installer.headerLength == 82
    check detectFormats("setup.exe", data)[0].typeId == InnoSetupTypeId
    let inspection = inspectSource("setup.exe", data)
    check inspection.resources.roots[0].path == "/installer"
    check inspection.resources.roots[0].children.len == 3
    check inspection.resources.roots[0].children[2].path ==
      "/installer/setup-data"

  test "modern loader is found through the PE resource tree":
    let installer = parseInnoSetup(modernFixture())
    check installer.loaderInPeResource
    check installer.loaderOffset == 0x280
    check installer.loaderVersion == "5.1.5"
    check installer.setupVersion == "Inno Setup Setup Data (6.3.0)"
    check installer.dataOffset == 0
    check installer.headerLength == 82

  test "monolithic data may begin before the setup headers":
    var data = legacyFixture()
    data.put32(0x80 + 32, 0xc0)
    let installer = parseInnoSetup(data)
    check installer.dataOffset == 0xc0
    check installer.headerOffset == 0x100

  test "coincidental strings and invalid loader pointers are rejected":
    var coincidence = newSeq[byte](512)
    coincidence.putText(100, "Inno Setup Setup Data (6.3.0)")
    check not isInnoSetup(coincidence)
    var broken = legacyFixture(); broken.put32(0x38, 0)
    check not isInnoSetup(broken)

  test "source-backed inspection does not materialize a large installer":
    let fixture = modernFixture()
    var largestRead = 0
    let logicalLength = 2 * 1024 * 1024 * 1024
    let source = newByteSource(logicalLength,
      proc(offset, length: int): seq[byte] =
        largestRead = max(largestRead, length)
        result = newSeq[byte](length)
        if offset < fixture.len:
          for index in 0 ..< min(length, fixture.len - offset):
            result[index] = fixture[offset + index])
    let session = openInspectionSession("huge-setup.exe",
      newSourceCollection(source))
    check session.selectedFormat.typeId == InnoSetupTypeId
    check largestRead <= 1024 * 1024
    check vrcExtractTree in session.rootDescriptors[0].capabilities
    check session.extractionPlan().entries.len == 0
    session.close()
