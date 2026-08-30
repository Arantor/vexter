import std/unittest
import vexterlib

proc put16(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)

proc put32(data: var seq[byte], offset: int, value: uint32) =
  for index in 0 .. 3: data[offset + index] = byte(value shr (index * 8))

proc put64(data: var seq[byte], offset: int, value: uint64) =
  for index in 0 .. 7: data[offset + index] = byte(value shr (index * 8))

proc putBe16(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8); data[offset + 1] = byte(value)

proc putBe32(data: var seq[byte], offset, value: int) =
  for index in 0 .. 3: data[offset + index] = byte(value shr ((3 - index) * 8))

proc putBoth16(data: var seq[byte], offset, value: int) =
  data.put16(offset, value); data.putBe16(offset + 2, value)

proc putBoth32(data: var seq[byte], offset, value: int) =
  data.put32(offset, uint32(value)); data.putBe32(offset + 4, value)

proc isoDirectoryRecord(extent, length: int, identifier: byte): seq[byte] =
  result = newSeq[byte](34)
  result[0] = 34
  result.putBoth32(2, extent)
  result.putBoth32(10, length)
  result[18] = 126; result[19] = 8; result[20] = 30
  result[25] = 2
  result.putBoth16(28, 1)
  result[32] = 1
  result[33] = identifier

proc type1Fixture(): seq[byte] =
  const filesystemOffset = 128
  const sectors = 24
  result = newSeq[byte](filesystemOffset + sectors * Iso9660LogicalBlockSize)
  result[0] = 0x7f
  for index, value in "ELF": result[index + 1] = byte(value)
  result[4] = 2; result[5] = 1; result[6] = 1
  result[8] = byte('A'); result[9] = byte('I'); result[10] = 1
  result.put16(18, 62)
  result.put64(40, 64)
  result.put16(52, 64)
  result.put16(58, 64)
  result.put16(60, 1)
  let primary = filesystemOffset + 16 * Iso9660LogicalBlockSize
  result[primary] = 1
  for index, value in "CD001": result[primary + 1 + index] = byte(value)
  result[primary + 6] = 1
  for index, value in "TYPE1": result[primary + 40 + index] = byte(value)
  result.putBoth32(primary + 80, sectors)
  result.putBoth16(primary + 120, 1)
  result.putBoth16(primary + 124, 1)
  result.putBoth16(primary + 128, Iso9660LogicalBlockSize)
  let root = isoDirectoryRecord(20, Iso9660LogicalBlockSize, 0)
  for index, value in root: result[primary + 156 + index] = value
  result[primary + 881] = 1
  let terminator = filesystemOffset + 17 * Iso9660LogicalBlockSize
  result[terminator] = 255
  for index, value in "CD001": result[terminator + 1 + index] = byte(value)
  result[terminator + 6] = 1
  let directory = filesystemOffset + 20 * Iso9660LogicalBlockSize
  for index, value in root: result[directory + index] = value
  let parent = isoDirectoryRecord(20, Iso9660LogicalBlockSize, 1)
  for index, value in parent: result[directory + root.len + index] = value

proc hybridType1Fixture(): seq[byte] =
  let appended = type1Fixture()
  result = appended[128 .. ^1]
  result[0] = 0x7f
  for index, value in "ELF": result[index + 1] = byte(value)
  result[4] = 2; result[5] = 1; result[6] = 1
  result.put16(18, 62)
  result.put64(40, 64)
  result.put16(52, 64)
  result.put16(58, 64)
  result.put16(60, 1)

proc type2Fixture(): seq[byte] =
  const filesystemOffset = 128
  const inodeTable = 101
  const directoryTable = 171
  const bytesUsed = 213
  result = newSeq[byte](filesystemOffset + bytesUsed)
  result[0] = 0x7f
  for index, value in "ELF": result[index + 1] = byte(value)
  result[4] = 2; result[5] = 1; result[6] = 1
  result[8] = byte('A'); result[9] = byte('I'); result[10] = 2
  result.put16(18, 62)
  result.put64(40, 64)
  result.put16(52, 64)
  result.put16(58, 64)
  result.put16(60, 1)

  let base = filesystemOffset
  result.put32(base, 0x73717368'u32)
  result.put32(base + 4, 2)
  result.put32(base + 12, 4096)
  result.put32(base + 16, 0)
  result.put16(base + 20, 1)
  result.put16(base + 22, 12)
  result.put16(base + 24, 0)
  result.put16(base + 26, 1)
  result.put16(base + 28, 4)
  result.put16(base + 30, 0)
  result.put64(base + 32, 0)
  result.put64(base + 40, bytesUsed)
  result.put64(base + 48, 205)
  result.put64(base + 56, high(uint64))
  result.put64(base + 64, inodeTable)
  result.put64(base + 72, directoryTable)
  result.put64(base + 80, high(uint64))
  result.put64(base + 88, high(uint64))
  for index, value in "hello": result[base + 96 + index] = byte(value)

  let inode = base + inodeTable
  result.put16(inode, 0x8000 or 68)
  let root = inode + 2
  result.put16(root, 1); result.put16(root + 2, 0o755)
  result.put32(root + 12, 1)
  result.put32(root + 16, 0)
  result.put32(root + 20, 2)
  result.put16(root + 24, 29)
  result.put16(root + 26, 0)
  let file = root + 32
  result.put16(file, 2); result.put16(file + 2, 0o755)
  result.put32(file + 12, 2)
  result.put32(file + 16, 96)
  result.put32(file + 20, high(uint32))
  result.put32(file + 24, 0)
  result.put32(file + 28, 5)
  result.put32(file + 32, 0x01000005'u32)

  let directory = base + directoryTable
  result.put16(directory, 0x8000 or 26)
  let listing = directory + 2
  result.put32(listing, 0)
  result.put32(listing + 4, 0)
  result.put32(listing + 8, 1)
  result.put16(listing + 12, 32)
  result.put16(listing + 14, 1)
  result.put16(listing + 16, 2)
  result.put16(listing + 18, 5)
  for index, value in "AppRun": result[listing + 20 + index] = byte(value)
  result.put16(base + 199, 0x8000 or 4)
  result.put32(base + 201, 1000)
  result.put64(base + 205, 199)

suite "AppImage Type 2":
  test "ELF boundary, SquashFS tree, and stored file extraction":
    let source = memoryByteSource(type2Fixture())
    let archive = indexAppImage(source)
    check archive.filesystemOffset == 128
    check archive.compressor == 1
    check archive.entries.len == 1
    check archive.entries[0].name == "AppRun"
    check archive.entries[0].permissions == 0o755
    check archive.entries[0].uid == 1000
    check archive.entries[0].gid == 1000
    check extractAppImageEntry(source, archive, archive.entries[0]) ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]
    source.close()

    let candidates = detectFormats("fixture.AppImage", type2Fixture())
    check candidates[0].typeId == AppImageTypeId
    let session = openInspectionSession("fixture.AppImage",
      newSourceCollection(memoryByteSource(type2Fixture())))
    check session.selectedFormat.typeId == AppImageTypeId
    check vrcExtractTree in session.rootDescriptors[0].capabilities
    let children = session.expandResource(session.rootDescriptors[0].id).children
    check children.len == 1
    check children[0].path == "/appimage/AppRun"
    check session.materializePayload(children[0].id) ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]
    check session.extractionPlan().entries.len == 1
    session.close()

  test "marker and exact ELF-to-SquashFS boundary are required":
    var badMarker = type2Fixture()
    badMarker[10] = 1
    let markerSource = memoryByteSource(badMarker)
    expect ValueError: discard indexAppImage(markerSource)
    markerSource.close()

    var shifted = type2Fixture()
    shifted.put64(40, 63)
    let shiftedSource = memoryByteSource(shifted)
    expect ValueError: discard indexAppImage(shiftedSource)
    shiftedSource.close()

suite "AppImage Type 1":
  test "markerless ELF in the ISO system area is recognized as Type 1":
    let data = hybridType1Fixture()
    let source = memoryByteSource(data)
    let indexed = indexAppImageType1(source)
    check indexed.filesystemOffset == 0
    check indexed.iso.volumeIdentifier == "TYPE1"
    source.close()
    check detectFormats("legacy.AppImage", data)[0].typeId ==
      AppImageType1TypeId
    let session = openInspectionSession("legacy.AppImage",
      newSourceCollection(memoryByteSource(data)))
    check session.selectedFormat.typeId == AppImageType1TypeId
    check session.rootDescriptors[0].path == "/appimage"
    session.close()

  test "ELF wrapper remains the selected format around its ISO filesystem":
    let data = type1Fixture()
    let source = memoryByteSource(data)
    let indexed = indexAppImageType1(source)
    check indexed.filesystemOffset == 128
    check indexed.iso.volumeIdentifier == "TYPE1"
    source.close()
    let candidates = detectFormats("fixture.AppImage", data)
    check candidates[0].typeId == AppImageType1TypeId
    let session = openInspectionSession("fixture.AppImage",
      newSourceCollection(memoryByteSource(data)))
    check session.selectedFormat.typeId == AppImageType1TypeId
    check session.rootDescriptors[0].path == "/appimage"
    var filesystemType = ""
    for item in session.rootDescriptors[0].metadata:
      if item.key == "filesystem.type": filesystemType = item.value.stringValue
    check filesystemType == Iso9660TypeId
    session.close()

  test "AI01 alone is not enough without a valid appended ISO filesystem":
    var data = type1Fixture()
    data[128 + 16 * Iso9660LogicalBlockSize + 1] = 0
    let source = memoryByteSource(data)
    expect ValueError: discard indexAppImageType1(source)
    source.close()
