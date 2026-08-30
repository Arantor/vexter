import std/unittest
import vexterlib

proc putWord(data: var seq[byte], offset, value: int, big = false) =
  if big:
    data[offset] = byte(value shr 8); data[offset + 1] = byte(value)
  else:
    data[offset] = byte(value); data[offset + 1] = byte(value shr 8)

proc putDword(data: var seq[byte], offset, value: int, big = false) =
  if big:
    data[offset] = byte(value shr 24); data[offset + 1] = byte(value shr 16)
    data[offset + 2] = byte(value shr 8); data[offset + 3] = byte(value)
  else:
    data[offset] = byte(value); data[offset + 1] = byte(value shr 8)
    data[offset + 2] = byte(value shr 16); data[offset + 3] = byte(value shr 24)

proc putBothWord(data: var seq[byte], offset, value: int) =
  data.putWord(offset, value); data.putWord(offset + 2, value, true)

proc putBothDword(data: var seq[byte], offset, value: int) =
  data.putDword(offset, value); data.putDword(offset + 4, value, true)

proc directoryRecord(extent, length: int, identifier: seq[byte],
    directory = false, systemUse: seq[byte] = @[]): seq[byte] =
  let padding = if identifier.len mod 2 == 0: 1 else: 0
  result = newSeq[byte](33 + identifier.len + padding + systemUse.len)
  result[0] = byte(result.len)
  result.putBothDword(2, extent)
  result.putBothDword(10, length)
  result[18] = 126 # 2026
  result[19] = 8; result[20] = 24; result[21] = 21
  result[22] = 30; result[23] = 15
  if directory: result[25] = 2
  result.putBothWord(28, 1)
  result[32] = byte(identifier.len)
  for index, value in identifier: result[33 + index] = value
  for index, value in systemUse:
    result[33 + identifier.len + padding + index] = value

proc appendRecord(directory: var seq[byte], record: seq[byte]) =
  var offset = 0
  while offset < directory.len and directory[offset] != 0:
    offset += int(directory[offset])
  check offset + record.len <= directory.len
  for index, value in record: directory[offset + index] = value

proc putSector(image: var seq[byte], sector: int, content: seq[byte]) =
  for index, value in content:
    image[sector * Iso9660LogicalBlockSize + index] = value

proc isoFixture(): seq[byte] =
  const sectors = 32
  result = newSeq[byte](sectors * Iso9660LogicalBlockSize)
  var primary = newSeq[byte](Iso9660LogicalBlockSize)
  primary[0] = 1
  for index, value in "CD001": primary[1 + index] = byte(value)
  primary[6] = 1
  for index, value in "VEXTER": primary[8 + index] = byte(value)
  for index, value in "SYNTHETIC": primary[40 + index] = byte(value)
  primary.putBothDword(80, sectors)
  primary.putBothWord(120, 1); primary.putBothWord(124, 1)
  primary.putBothWord(128, Iso9660LogicalBlockSize)
  let root = directoryRecord(20, Iso9660LogicalBlockSize, @[0'u8], true)
  for index, value in root: primary[156 + index] = value
  for index, value in "VEXTER TESTS": primary[574 + index] = byte(value)
  primary[881] = 1
  result.putSector(16, primary)
  var terminator = newSeq[byte](Iso9660LogicalBlockSize)
  terminator[0] = 255
  for index, value in "CD001": terminator[1 + index] = byte(value)
  terminator[6] = 1
  result.putSector(17, terminator)

  var rootDirectory = newSeq[byte](Iso9660LogicalBlockSize)
  rootDirectory.appendRecord(directoryRecord(20, Iso9660LogicalBlockSize,
    @[0'u8], true))
  rootDirectory.appendRecord(directoryRecord(20, Iso9660LogicalBlockSize,
    @[1'u8], true))
  rootDirectory.appendRecord(directoryRecord(26, Iso9660LogicalBlockSize,
    @['D'.byte, 'O'.byte, 'C'.byte, 'S'.byte], true,
    @['S'.byte, 'P'.byte, 7'u8, 1, 0xbe, 0xef, 0]))
  rootDirectory.appendRecord(directoryRecord(22, ZxSpectrumScreenSize,
    @['I'.byte, 'M'.byte, 'A'.byte, 'G'.byte, 'E'.byte, '.'.byte,
      'S'.byte, 'C'.byte, 'R'.byte, ';'.byte, '1'.byte]))
  result.putSector(20, rootDirectory)

  var subdirectory = newSeq[byte](Iso9660LogicalBlockSize)
  subdirectory.appendRecord(directoryRecord(26, Iso9660LogicalBlockSize,
    @[0'u8], true))
  subdirectory.appendRecord(directoryRecord(20, Iso9660LogicalBlockSize,
    @[1'u8], true))
  subdirectory.appendRecord(directoryRecord(27, 5,
    @['N'.byte, 'O'.byte, 'T'.byte, 'E'.byte, '.'.byte, 'T'.byte,
      'X'.byte, 'T'.byte, ';'.byte, '1'.byte]))
  result.putSector(26, subdirectory)
  for index in 0 ..< ZxSpectrumScreenSize:
    result[22 * Iso9660LogicalBlockSize + index] = byte(index)
  for index, value in "hello":
    result[27 * Iso9660LogicalBlockSize + index] = byte(value)

proc suspField(signature: string, payload: seq[byte]): seq[byte] =
  result = @[byte(signature[0]), byte(signature[1]), byte(4 + payload.len), 1'u8]
  result.add payload

proc rockRidgeFixture(): seq[byte] =
  result = isoFixture()
  var rootDirectory = newSeq[byte](Iso9660LogicalBlockSize)
  var rootSusp = suspField("SP", @[0xbe'u8, 0xef'u8, 0'u8])
  rootSusp.add suspField("ER", @[10'u8, 0'u8, 0'u8, 1'u8, 'I'.byte,
    'E'.byte, 'E'.byte, 'E'.byte, '_'.byte, 'P'.byte, '1'.byte,
    '2'.byte, '8'.byte, '2'.byte])
  rootDirectory.appendRecord(directoryRecord(20, Iso9660LogicalBlockSize,
    @[0'u8], true, rootSusp))
  rootDirectory.appendRecord(directoryRecord(20, Iso9660LogicalBlockSize,
    @[1'u8], true))
  var nm = suspField("NM", @[0'u8, 'r'.byte, 'e'.byte, 'a'.byte,
    'd'.byte, 'm'.byte, 'e'.byte, '.'.byte, 't'.byte, 'x'.byte, 't'.byte])
  var pxPayload = newSeq[byte](40)
  pxPayload.putBothDword(0, 0o100644)
  pxPayload.putBothDword(8, 1)
  pxPayload.putBothDword(16, 1000)
  pxPayload.putBothDword(24, 1001)
  pxPayload.putBothDword(32, 7)
  nm.add suspField("PX", pxPayload)
  nm.add suspField("ST", @[])
  rootDirectory.appendRecord(directoryRecord(27, 5,
    @['R'.byte, 'E'.byte, 'A'.byte, 'D'.byte, 'M'.byte, 'E'.byte,
      '.'.byte, 'T'.byte, 'X'.byte, 'T'.byte, ';'.byte, '1'.byte],
    systemUse = nm))
  var link = suspField("NM", @[0'u8, 'l'.byte, 'i'.byte, 'n'.byte, 'k'.byte])
  link.add suspField("SL", @[0'u8, 0'u8, 10'u8, 'r'.byte, 'e'.byte,
    'a'.byte, 'd'.byte, 'm'.byte, 'e'.byte, '.'.byte, 't'.byte,
    'x'.byte, 't'.byte])
  rootDirectory.appendRecord(directoryRecord(0, 0,
    @['L'.byte, 'I'.byte, 'N'.byte, 'K'.byte, ';'.byte, '1'.byte],
    systemUse = link))
  result.putSector(20, rootDirectory)

proc rawMode1(cooked: seq[byte]): seq[byte] =
  let sectors = cooked.len div Iso9660LogicalBlockSize
  result = newSeq[byte](sectors * 2352)
  for sector in 0 ..< sectors:
    let target = sector * 2352
    for index in 1 .. 10: result[target + index] = 0xff
    result[target + 15] = 1
    for index in 0 ..< Iso9660LogicalBlockSize:
      result[target + 16 + index] =
        cooked[sector * Iso9660LogicalBlockSize + index]

suite "ISO 9660 filesystems":
  test "SUSP activates Rock Ridge names, POSIX metadata, and symbolic links":
    let source = memoryByteSource(rockRidgeFixture())
    let index = indexIso9660(source)
    check index.rockRidge
    check index.suspSkip == 0
    let entries = listIso9660Directory(source, index, index.rootExtent,
      index.rootLength, @[])
    check entries.len == 2
    check entries[0].name == "readme.txt"
    check entries[0].posixMode == 0o100644
    check entries[0].posixUid == 1000
    check entries[0].posixGid == 1001
    check entries[0].posixSerial == 7
    check entries[1].name == "link"
    check entries[1].isSymlink
    check entries[1].symlinkTarget == "readme.txt"
    source.close()

  test "cooked images expose hierarchy and recursively decoded files":
    let data = isoFixture()
    let parsed = parseIso9660(data)
    check parsed.layout == ilCooked2048
    check parsed.volumeIdentifier == "SYNTHETIC"
    check parsed.entries.len == 3
    check parsed.entries[0].name == "DOCS"
    check parsed.entries[0].systemUseBytes == 7
    check parsed.entries[1].name == "DOCS/NOTE.TXT"
    check extractIso9660Entry(data, parsed, parsed.entries[1]) ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]
    check parsed.entries[2].name == "IMAGE.SCR"
    check parsed.entries[2].fileVersion == 1

    let candidates = detectFormats("disc.bin", data)
    check candidates[0].typeId == Iso9660TypeId
    check candidates[0].confidence == vdcCertain
    let inspection = inspectSource("disc.bin", data)
    check inspection.resources.roots[0].path == "/disc"
    check inspection.resources.findRasterResource(
      "/disc/IMAGE.SCR/screen") != nil
    let leaves = inspection.resources.leafResources
    check leaves[0].path == "/disc/DOCS/NOTE.TXT"
    check leaves[0].rawDataAvailable
    check leaves[0].data.len == 0
    check leaves[0].resourceBytes ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]
    let exported = exportResource(inspection.resources, VextExportRequest(
      resourcePath: leaves[0].path, outputFormat: "bin",
      suggestedName: "note"))
    check exported.artifacts.artifacts[0].data ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]

  test "raw Mode 1/2352 images use the same filesystem pathway":
    let raw = rawMode1(isoFixture())
    let parsed = parseIso9660(raw)
    check parsed.layout == ilRawMode1_2352
    check extractIso9660Entry(raw, parsed, parsed.entries[1]) ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]
    let inspection = inspectSource("track.dat", raw)
    check inspection.selectedFormat.typeId == Iso9660TypeId
    check inspection.resources.findRasterResource(
      "/disc/IMAGE.SCR/screen") != nil
    let note = inspection.resources.leafResources[0]
    check note.data.len == 0
    check note.resourceBytes ==
      @['h'.byte, 'e'.byte, 'l'.byte, 'l'.byte, 'o'.byte]

  test "session directory providers visit only expanded ISO extents":
    let data = isoFixture()
    let subdirectoryStart = 26 * Iso9660LogicalBlockSize
    let subdirectoryEnd = subdirectoryStart + Iso9660LogicalBlockSize
    var subdirectoryRead = false
    let source = newByteSource(data.len,
      proc(offset, length: int): seq[byte] =
        if offset < subdirectoryEnd and offset + length > subdirectoryStart:
          subdirectoryRead = true
        result = data[offset ..< offset + length])
    let session = openInspectionSession("disc.iso",
      newSourceCollection(source))
    check session.selectedFormat.typeId == Iso9660TypeId
    check vrcExtractTree in session.rootDescriptors[0].capabilities
    check not subdirectoryRead
    let rootChildren = session.expandResource(
      session.rootDescriptors[0].id).children
    check rootChildren.len == 2
    check not subdirectoryRead
    let docs = session.resourceAtPath("/disc/DOCS")
    let docsChildren = session.expandResource(docs.id).children
    check subdirectoryRead
    check docsChildren.len == 1
    check docsChildren[0].path == "/disc/DOCS/NOTE.TXT"
    let plan = session.extractionPlan()
    var foundNote = false
    for entry in plan.entries:
      if entry.relativePath == "DOCS/NOTE.TXT": foundNote = true
    check foundNote
    session.close()

  test "descriptor, both-byte, extent, and raw-sector damage is rejected":
    var missingTerminator = isoFixture()
    missingTerminator[17 * Iso9660LogicalBlockSize] = 0
    expect ValueError: discard parseIso9660(missingTerminator)

    var endianMismatch = isoFixture()
    endianMismatch[16 * Iso9660LogicalBlockSize + 87] = 31
    expect ValueError: discard parseIso9660(endianMismatch)

    var badExtent = isoFixture()
    # Damage the first ordinary child record; self/parent navigation aliases
    # are deliberately recovery-tolerant because they are never followed.
    badExtent[20 * Iso9660LogicalBlockSize + 68 + 2] = 40
    expect ValueError: discard parseIso9660(badExtent)

    var raw = rawMode1(isoFixture())
    raw[20 * 2352 + 1] = 0
    expect ValueError: discard parseIso9660(raw)

  test "zero-length root identifiers used by compatible masters are accepted":
    var data = isoFixture()
    data[16 * Iso9660LogicalBlockSize + 156 + 32] = 0
    check parseIso9660(data).entries.len == 3

  test "stale redundant fields in ignored parent records are tolerated":
    var data = isoFixture()
    let parentRecord = 20 * Iso9660LogicalBlockSize + 34
    data[parentRecord + 6] = 0xff
    data[parentRecord + 14] = 0xff
    check parseIso9660(data).entries.len == 3
    let source = memoryByteSource(data)
    let index = indexIso9660(source)
    check listIso9660Directory(source, index, index.rootExtent,
      index.rootLength, @[]).len == 2
    source.close()

  test "lazy contained resources decode once while retaining raw bytes":
    var screen = newSeq[byte](ZxSpectrumScreenSize)
    for index in 0 ..< screen.len: screen[index] = byte(index)
    let source = VextPayloadSource(data: screen)
    let node = VextResourceNode(path: "/disc/IMAGE.SCR",
      typeId: Iso9660FileTypeId, kind: vrnkOpaque,
      lazyPayload: VextPayloadRef(source: source,
        spans: @[VextPayloadSpan(offset: 0, length: screen.len)],
        length: screen.len), rawDataAvailable: true)
    check decodeResourceOnDemand(node) == vddDecoded
    check node.kind == vrnkGroup
    check node.typeId == ZxSpectrumScreenTypeId
    check node.children.len == 1
    check node.children[0].path == "/disc/IMAGE.SCR/screen"
    check node.resourceBytes == screen
    check decodeResourceOnDemand(node) == vddNotApplicable
