## Type 2 AppImage indexing and SquashFS 4 filesystem extraction.

import std/[dynlib, sets, strutils]
import ../byte_sources
import ./iso9660

const
  AppImageTypeId* = "executable.appimage-type2"
  AppImageType1TypeId* = "executable.appimage-type1"
  AppImageDirectoryTypeId* = "filesystem.squashfs-directory"
  AppImageFileTypeId* = "filesystem.squashfs-file"
  AppImageSymlinkTypeId* = "filesystem.squashfs-symlink"
  AppImageMaximumEntries* = 200_000
  SquashMetadataSize = 8192

type
  AppImageEntryKind* = enum
    aiekDirectory, aiekFile, aiekSymlink, aiekOther

  AppImageEntry* = object
    name*: string
    segments*: seq[string]
    kind*: AppImageEntryKind
    permissions*: int
    uidIndex*, gidIndex*, uid*, gid*: int
    mtime*: uint32
    inodeNumber*: int
    size*: int
    symlinkTarget*: string
    blocksStart*: uint64
    fragmentIndex*: uint32
    fragmentOffset*: uint32
    blockSizes*: seq[uint32]

  AppImageArchive* = object
    elfClass*, elfEndian*, elfMachine*: int
    filesystemOffset*: int
    blockSize*, compressor*, flags*, inodeCount*, fragmentCount*, idCount*: int
    bytesUsed*: int
    inodeTable*, directoryTable*, fragmentTable*, idTable*: uint64
    rootInode*: uint64
    entries*: seq[AppImageEntry]

  AppImageType1* = object
    elfClass*, elfEndian*, elfMachine*: int
    filesystemOffset*: int
    iso*: Iso9660Index

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
  const ZstdLibrary = "libzstd.dll"
else:
  const ZlibLibrary = "libz.so.1"
  const ZstdLibrary = "libzstd.so.1"

type ZStream = object
  nextIn: ptr byte
  availIn: cuint
  totalIn: culong
  nextOut: ptr byte
  availOut: cuint
  totalOut: culong
  msg, state: pointer
  zalloc, zfree: pointer
  opaque: pointer
  dataType: cint
  adler, reserved: culong

proc zlibVersion(): cstring {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateInit(stream: ptr ZStream, version: cstring, size: cint): cint
    {.cdecl, importc: "inflateInit_", dynlib: ZlibLibrary.}
proc inflate(stream: ptr ZStream, flush: cint): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateEnd(stream: ptr ZStream): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}
type
  ZstdDecompressProc = proc(dst: pointer, dstCapacity: csize_t, src: pointer,
    compressedSize: csize_t): csize_t {.cdecl.}
  ZstdIsErrorProc = proc(code: csize_t): cuint {.cdecl.}

proc decompressZstd(destination: pointer, destinationSize: int,
    sourceData: pointer, sourceSize: int): csize_t =
  ## Keep optional SquashFS compression support from becoming a process-wide
  ## runtime dependency. In particular, Windows must be able to start Vexter
  ## without libzstd.dll when no Zstandard-compressed AppImage is inspected.
  let library = loadLib(ZstdLibrary)
  if library == nil:
    raise newException(ValueError,
      "Zstandard-compressed SquashFS requires " & ZstdLibrary)
  try:
    let zstdDecompress = cast[ZstdDecompressProc](library.symAddr("ZSTD_decompress"))
    let zstdIsError = cast[ZstdIsErrorProc](library.symAddr("ZSTD_isError"))
    if zstdDecompress == nil or zstdIsError == nil:
      raise newException(ValueError,
        ZstdLibrary & " does not provide the required Zstandard API")
    result = zstdDecompress(destination, csize_t(destinationSize), sourceData,
      csize_t(sourceSize))
    if zstdIsError(result) != 0:
      raise newException(ValueError, "invalid SquashFS Zstandard block")
  finally:
    unloadLib(library)

proc le16(data: openArray[byte], offset: int): uint16 {.inline.} =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc le64(data: openArray[byte], offset: int): uint64 {.inline.} =
  uint64(data.le32(offset)) or (uint64(data.le32(offset + 4)) shl 32)

proc be16(data: openArray[byte], offset: int): uint16 {.inline.} =
  (uint16(data[offset]) shl 8) or uint16(data[offset + 1])

proc be32(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc be64(data: openArray[byte], offset: int): uint64 {.inline.} =
  (uint64(data.be32(offset)) shl 32) or uint64(data.be32(offset + 4))

proc checkedInt(value: uint64, field: string): int =
  if value > uint64(high(int)):
    raise newException(ValueError, field & " exceeds host limits")
  int(value)

proc decompress(compressor: int, input: seq[byte], maximum: int): seq[byte] =
  if maximum < 0: raise newException(ValueError, "negative decompression limit")
  result = newSeq[byte](maximum)
  case compressor
  of 1:
    var stream = ZStream(availIn: cuint(input.len), availOut: cuint(result.len))
    if input.len > 0: stream.nextIn = unsafeAddr input[0]
    if result.len > 0: stream.nextOut = addr result[0]
    if inflateInit(addr stream, zlibVersion(), cint(sizeof(ZStream))) != 0:
      raise newException(ValueError, "could not initialize SquashFS zlib inflater")
    let status = inflate(addr stream, 4)
    discard inflateEnd(addr stream)
    if status != 1 or stream.totalOut > culong(maximum):
      raise newException(ValueError, "invalid or oversized SquashFS zlib block")
    result.setLen(int(stream.totalOut))
  of 6:
    var destination, sourceData: pointer
    if result.len > 0: destination = addr result[0]
    if input.len > 0: sourceData = unsafeAddr input[0]
    let size = decompressZstd(destination, result.len, sourceData, input.len)
    if size > csize_t(maximum):
      raise newException(ValueError, "invalid or oversized SquashFS Zstandard block")
    result.setLen(int(size))
  else:
    raise newException(ValueError, "unsupported SquashFS compressor: " & $compressor)

proc elfValue(header: openArray[byte], offset, size, endian: int): uint64 =
  if offset < 0 or offset + size > header.len:
    raise newException(ValueError, "truncated ELF header")
  if endian == 1:
    case size
    of 2: uint64(header.le16(offset))
    of 4: uint64(header.le32(offset))
    of 8: header.le64(offset)
    else: raise newException(ValueError, "invalid ELF integer size")
  elif endian == 2:
    case size
    of 2: uint64(header.be16(offset))
    of 4: uint64(header.be32(offset))
    of 8: header.be64(offset)
    else: raise newException(ValueError, "invalid ELF integer size")
  else: raise newException(ValueError, "invalid ELF byte order")

proc appImageFilesystemOffset(source: VextByteSource, expectedType: int,
    elfClass, elfEndian, elfMachine: var int): int =
  if source.length < 96: raise newException(ValueError, "AppImage is too short")
  let header = source.readAt(0, min(source.length, 64))
  if header[0 .. 3] != @[0x7f'u8, byte('E'), byte('L'), byte('F')]:
    raise newException(ValueError, "AppImage does not contain an ELF executable")
  if expectedType >= 0 and (header[8] != byte('A') or
      header[9] != byte('I') or header[10] != byte(expectedType)):
    raise newException(ValueError,
      "AppImage Type " & $expectedType & " marker is missing")
  elfClass = int(header[4])
  elfEndian = int(header[5])
  if elfClass notin [1, 2] or elfEndian notin [1, 2] or
      header[6] != 1:
    raise newException(ValueError, "unsupported ELF identification")
  elfMachine = int(header.elfValue(18, 2, elfEndian))
  let sectionOffset = if elfClass == 1: header.elfValue(32, 4, elfEndian)
    else: header.elfValue(40, 8, elfEndian)
  let sizeOffset = if elfClass == 1: 46 else: 58
  let countOffset = if elfClass == 1: 48 else: 60
  let headerSize = int(header.elfValue(if elfClass == 1: 40 else: 52,
    2, elfEndian))
  let sectionSize = header.elfValue(sizeOffset, 2, elfEndian)
  let sectionCount = header.elfValue(countOffset, 2, elfEndian)
  if headerSize < (if elfClass == 1: 52 else: 64) or
      sectionOffset == 0 or sectionSize == 0 or sectionCount == 0 or
      sectionCount > 65_535 or sectionOffset > uint64(source.length) or
      sectionSize > (uint64(source.length) - sectionOffset) div sectionCount:
    raise newException(ValueError, "invalid or sectionless ELF AppImage")
  result = checkedInt(sectionOffset + sectionSize * sectionCount,
    "ELF section table end")
  if result > source.length - 96:
    raise newException(ValueError, "ELF section table leaves no filesystem")

proc indexAppImageType1*(source: VextByteSource): AppImageType1 =
  let boundary = appImageFilesystemOffset(source, -1,
    result.elfClass, result.elfEndian, result.elfMachine)
  let header = source.readAt(0, 11)
  result.filesystemOffset = if header[8] == byte('A') and
      header[9] == byte('I') and header[10] == 1: boundary else: 0
  let isoSource = sliceByteSource(source, result.filesystemOffset,
    source.length - result.filesystemOffset, source.label & " (AppImage ISO)")
  result.iso = indexIso9660(isoSource)

proc readArchive(source: VextByteSource, archive: AppImageArchive,
    relativeOffset, length: int): seq[byte] =
  if relativeOffset < 0 or length < 0 or
      relativeOffset > archive.bytesUsed - length:
    raise newException(ValueError, "SquashFS read is outside filesystem bounds")
  source.readAt(archive.filesystemOffset + relativeOffset, length)

proc readCompressedBlock(source: VextByteSource, archive: AppImageArchive,
    relativeOffset, storedSize, maximum: int, uncompressed: bool): seq[byte] =
  if storedSize < 0 or storedSize > maximum:
    raise newException(ValueError, "invalid SquashFS block size")
  let stored = source.readArchive(archive, relativeOffset, storedSize)
  if uncompressed: return stored
  decompress(archive.compressor, stored, maximum)

proc metadataBlock(source: VextByteSource, archive: AppImageArchive,
    relativeOffset: int): tuple[data: seq[byte], next: int] =
  let header = source.readArchive(archive, relativeOffset, 2).le16(0)
  let storedSize = int(header and 0x7fff)
  if storedSize <= 0 or storedSize > SquashMetadataSize:
    raise newException(ValueError, "invalid SquashFS metadata block size")
  result.data = source.readCompressedBlock(archive, relativeOffset + 2,
    storedSize, SquashMetadataSize, (header and 0x8000) != 0)
  result.next = relativeOffset + 2 + storedSize

proc metadataBytes(source: VextByteSource, archive: AppImageArchive,
    tableStart, blockOffset: uint64, within, length: int): seq[byte] =
  if within < 0 or within >= SquashMetadataSize or length < 0:
    raise newException(ValueError, "invalid SquashFS metadata reference")
  var location = checkedInt(tableStart + blockOffset, "metadata block")
  var skip = within
  var remaining = length
  while remaining > 0:
    let metadata = source.metadataBlock(archive, location)
    if skip > metadata.data.len:
      raise newException(ValueError, "metadata offset exceeds decoded block")
    let amount = min(remaining, metadata.data.len - skip)
    if amount == 0:
      raise newException(ValueError, "metadata record cannot advance")
    result.add metadata.data[skip ..< skip + amount]
    remaining -= amount
    location = metadata.next
    skip = 0

proc parseInode(source: VextByteSource, archive: AppImageArchive,
    reference: uint64): AppImageEntry =
  let blockReference = reference shr 16
  let within = int(reference and 0xffff)
  var common = source.metadataBytes(archive, archive.inodeTable,
    blockReference, within, 32)
  let inodeType = int(common.le16(0))
  result.permissions = int(common.le16(2))
  result.uidIndex = int(common.le16(4))
  result.gidIndex = int(common.le16(6))
  result.mtime = common.le32(8)
  result.inodeNumber = int(common.le32(12))
  if result.inodeNumber <= 0 or result.inodeNumber > archive.inodeCount:
    raise newException(ValueError, "invalid SquashFS inode number")
  case inodeType
  of 1:
    result.kind = aiekDirectory
    result.blocksStart = uint64(common.le32(16))
    result.size = max(0, int(common.le16(24)) - 3)
    result.fragmentOffset = uint32(common.le16(26))
  of 8:
    common = source.metadataBytes(archive, archive.inodeTable,
      blockReference, within, 40)
    result.kind = aiekDirectory
    result.size = max(0, int(common.le32(20)) - 3)
    result.blocksStart = uint64(common.le32(24))
    result.fragmentOffset = uint32(common.le16(34))
  of 2:
    result.kind = aiekFile
    result.blocksStart = uint64(common.le32(16))
    result.fragmentIndex = common.le32(20)
    result.fragmentOffset = common.le32(24)
    result.size = int(common.le32(28))
    let count = if result.fragmentIndex == high(uint32):
        (result.size + archive.blockSize - 1) div archive.blockSize
      else: result.size div archive.blockSize
    if count > 0:
      let all = source.metadataBytes(archive, archive.inodeTable, blockReference,
        within, 32 + count * 4)
      for index in 0 ..< count: result.blockSizes.add all.le32(32 + index * 4)
  of 9:
    common = source.metadataBytes(archive, archive.inodeTable,
      blockReference, within, 56)
    result.kind = aiekFile
    result.blocksStart = common.le64(16)
    let size64 = common.le64(24)
    result.size = checkedInt(size64, "SquashFS file size")
    result.fragmentIndex = common.le32(44)
    result.fragmentOffset = common.le32(48)
    let count = if result.fragmentIndex == high(uint32):
        (result.size + archive.blockSize - 1) div archive.blockSize
      else: result.size div archive.blockSize
    if count > 0:
      let all = source.metadataBytes(archive, archive.inodeTable, blockReference,
        within, 56 + count * 4)
      for index in 0 ..< count: result.blockSizes.add all.le32(56 + index * 4)
  of 3, 10:
    result.kind = aiekSymlink
    let targetLength = int(common.le32(20))
    if targetLength < 0 or targetLength > 65_535:
      raise newException(ValueError, "invalid SquashFS symbolic link length")
    let all = source.metadataBytes(archive, archive.inodeTable, blockReference,
      within, 24 + targetLength)
    for index in 24 ..< all.len: result.symlinkTarget.add char(all[index])
    result.size = targetLength
  else:
    result.kind = aiekOther

proc validateName(name: string) =
  if name.len == 0 or name in [".", ".."] or '/' in name or
      '\0' in name:
    raise newException(ValueError, "unsafe SquashFS entry name: " & name.escape)

proc walkDirectory(source: VextByteSource, archive: var AppImageArchive,
    inode: AppImageEntry, parent: seq[string], depth: int,
    visited: var HashSet[int]) =
  if depth > 128: raise newException(ValueError, "SquashFS nesting exceeds safety limit")
  if inode.inodeNumber in visited:
    raise newException(ValueError, "cyclic SquashFS directory inode")
  visited.incl inode.inodeNumber
  if inode.size == 0: return
  let listing = source.metadataBytes(archive, archive.directoryTable,
    inode.blocksStart, int(inode.fragmentOffset), inode.size)
  var offset = 0
  while offset < listing.len:
    if offset > listing.len - 12:
      raise newException(ValueError, "truncated SquashFS directory header")
    let count = int(listing.le32(offset)) + 1
    let inodeBlock = uint64(listing.le32(offset + 4))
    if count <= 0 or count > 256:
      raise newException(ValueError, "invalid SquashFS directory entry count")
    offset += 12
    for unused in 0 ..< count:
      if offset > listing.len - 8:
        raise newException(ValueError, "truncated SquashFS directory entry")
      let inodeOffset = int(listing.le16(offset))
      let nameLength = int(listing.le16(offset + 6)) + 1
      offset += 8
      if nameLength <= 0 or nameLength > 256 or offset > listing.len - nameLength:
        raise newException(ValueError, "invalid SquashFS directory name length")
      var name = newString(nameLength)
      for index in 0 ..< nameLength: name[index] = char(listing[offset + index])
      validateName(name)
      offset += nameLength
      var child = source.parseInode(archive, (inodeBlock shl 16) or uint64(inodeOffset))
      child.segments = parent & @[name]
      child.name = child.segments.join("/")
      if archive.entries.len >= AppImageMaximumEntries:
        raise newException(ValueError, "SquashFS entry count exceeds safety limit")
      archive.entries.add child
      if child.kind == aiekDirectory:
        source.walkDirectory(archive, child, child.segments, depth + 1, visited)

proc indexAppImage*(source: VextByteSource): AppImageArchive =
  result.filesystemOffset = appImageFilesystemOffset(source, 2,
    result.elfClass, result.elfEndian, result.elfMachine)
  let super = source.readAt(result.filesystemOffset, 96)
  if super.le32(0) != 0x73717368'u32:
    raise newException(ValueError, "SquashFS does not begin at ELF section-table end")
  result.inodeCount = int(super.le32(4))
  result.blockSize = int(super.le32(12))
  result.fragmentCount = int(super.le32(16))
  result.compressor = int(super.le16(20))
  let blockLog = int(super.le16(22))
  result.flags = int(super.le16(24))
  result.idCount = int(super.le16(26))
  let major = int(super.le16(28)); let minor = int(super.le16(30))
  result.rootInode = super.le64(32)
  result.bytesUsed = checkedInt(super.le64(40), "SquashFS used size")
  result.idTable = super.le64(48)
  result.inodeTable = super.le64(64)
  result.directoryTable = super.le64(72)
  result.fragmentTable = super.le64(80)
  if result.inodeCount <= 0 or result.blockSize < 4096 or
      result.blockSize > 1_048_576 or (result.blockSize and
      (result.blockSize - 1)) != 0 or (1 shl blockLog) != result.blockSize or
      major != 4 or minor != 0 or result.compressor notin [1, 6] or
      result.bytesUsed < 96 or result.bytesUsed > source.length - result.filesystemOffset or
      result.inodeTable >= uint64(result.bytesUsed) or
      result.directoryTable >= uint64(result.bytesUsed):
    raise newException(ValueError, "invalid or unsupported SquashFS 4 superblock")
  var root = source.parseInode(result, result.rootInode)
  if root.kind != aiekDirectory:
    raise newException(ValueError, "SquashFS root inode is not a directory")
  var visited = initHashSet[int]()
  source.walkDirectory(result, root, @[], 0, visited)

  let archiveIdCount = result.idCount
  let archiveIdTable = result.idTable
  let indexedArchive = result
  proc resolveId(index: int): int =
    if index < 0 or index >= archiveIdCount or archiveIdTable == high(uint64):
      raise newException(ValueError, "invalid SquashFS UID/GID table index")
    let tableBlock = index div 2048
    let locations = source.readArchive(indexedArchive,
      checkedInt(archiveIdTable, "ID table") + tableBlock * 8, 8)
    let location = checkedInt(locations.le64(0), "ID metadata location")
    let metadata = source.metadataBlock(indexedArchive, location)
    let offset = (index mod 2048) * 4
    if offset > metadata.data.len - 4:
      raise newException(ValueError, "UID/GID entry exceeds metadata block")
    checkedInt(uint64(metadata.data.le32(offset)), "UID/GID")

  for entry in result.entries.mitems:
    entry.uid = resolveId(entry.uidIndex)
    entry.gid = resolveId(entry.gidIndex)
  var appRun = false
  for entry in result.entries:
    if entry.segments.len == 1 and entry.segments[0] == "AppRun" and
        entry.kind in [aiekFile, aiekSymlink]:
      appRun = true
  if not appRun:
    var roots: seq[string]
    for entry in result.entries:
      if entry.segments.len == 1 and roots.len < 8: roots.add entry.name
    raise newException(ValueError, "AppImage root has no AppRun file (found: " &
      roots.join(", ") & ")")

proc parseAppImage*(data: openArray[byte]): AppImageArchive =
  ## Compatibility adapter for the eager operations API. Inspection sessions
  ## use `indexAppImage` directly and retain random-access ownership instead.
  let source = memoryByteSource(@data)
  try: result = indexAppImage(source)
  finally: source.close()

proc parseAppImageType1*(data: openArray[byte]): AppImageType1 =
  let source = memoryByteSource(@data)
  try: result = indexAppImageType1(source)
  finally: source.close()

proc isAppImage*(data: openArray[byte]): bool =
  try:
    discard parseAppImage(data)
    true
  except ValueError, LibraryError:
    false

proc fragment(source: VextByteSource, archive: AppImageArchive,
    index: uint32): tuple[start: uint64, size: uint32] =
  if index >= uint32(archive.fragmentCount) or
      archive.fragmentTable == high(uint64):
    raise newException(ValueError, "invalid SquashFS fragment index")
  let tableBlock = int(index) div 512
  let locationBytes = source.readArchive(archive,
    checkedInt(archive.fragmentTable, "fragment table") + tableBlock * 8, 8)
  let location = checkedInt(locationBytes.le64(0), "fragment metadata location")
  let metadata = source.metadataBlock(archive, location)
  let offset = (int(index) mod 512) * 16
  if offset > metadata.data.len - 16:
    raise newException(ValueError, "fragment entry exceeds metadata block")
  result.start = metadata.data.le64(offset)
  result.size = metadata.data.le32(offset + 8)

proc extractAppImageEntry*(source: VextByteSource, archive: AppImageArchive,
    entry: AppImageEntry, maximumSize = high(int)): seq[byte] =
  if entry.kind != aiekFile:
    raise newException(ValueError, "only regular AppImage files have payloads")
  if entry.size > maximumSize:
    raise newException(ValueError, "AppImage member exceeds materialization limit")
  var location = checkedInt(entry.blocksStart, "file data start")
  for encoded in entry.blockSizes:
    let storedSize = int(encoded and 0x00ff_ffff'u32)
    let expected = min(archive.blockSize, entry.size - result.len)
    if storedSize == 0:
      result.add newSeq[byte](expected)
    else:
      let decoded = source.readCompressedBlock(archive, location, storedSize,
        archive.blockSize, (encoded and 0x0100_0000'u32) != 0)
      if decoded.len > expected:
        raise newException(ValueError, "SquashFS file block exceeds expected size")
      result.add decoded
      if decoded.len < expected: result.add newSeq[byte](expected - decoded.len)
      location += storedSize
  if entry.fragmentIndex != high(uint32) and result.len < entry.size:
    let item = source.fragment(archive, entry.fragmentIndex)
    let storedSize = int(item.size and 0x00ff_ffff'u32)
    let decoded = source.readCompressedBlock(archive, checkedInt(item.start,
      "fragment data start"), storedSize, archive.blockSize,
      (item.size and 0x0100_0000'u32) != 0)
    let tail = entry.size - result.len
    if int(entry.fragmentOffset) > decoded.len - tail:
      raise newException(ValueError, "SquashFS fragment slice is out of bounds")
    result.add decoded[int(entry.fragmentOffset) ..< int(entry.fragmentOffset) + tail]
  if result.len != entry.size:
    raise newException(ValueError, "SquashFS file length does not match inode")

proc hasAppImageExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".appimage")
