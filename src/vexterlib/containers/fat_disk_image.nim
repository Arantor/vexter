## Read-only FAT12/FAT16 filesystem parsing for unpartitioned raw disk images.

import std/[os, sets, strutils]

const
  FatDiskImageTypeId* = "filesystem.fat-disk-image"
  FatDirectoryTypeId* = "filesystem.fat-directory"
  FatFileTypeId* = "filesystem.fat-file"
  FatMaximumImageBytes* = 512 * 1024 * 1024

type
  FatKind* = enum
    fkFat12
    fkFat16

  FatEntryKind* = enum
    fekFile
    fekDirectory

  FatEntry* = ref object
    name*: string
    kind*: FatEntryKind
    attributes*: int
    firstCluster*: int
    size*: int
    data*: seq[byte]
    children*: seq[FatEntry]

  FatVolume* = object
    kind*: FatKind
    oemName*, label*: string
    bytesPerSector*, sectorsPerCluster*, reservedSectors*: int
    fatCount*, rootEntryCount*, totalSectors*, sectorsPerFat*: int
    mediaDescriptor*, clusterCount*: int
    entries*: seq[FatEntry]

proc word(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc dword(data: openArray[byte], offset: int): int {.inline.} =
  word(data, offset) or (word(data, offset + 2) shl 16)

proc isPowerOfTwo(value: int): bool =
  value > 0 and (value and (value - 1)) == 0

proc paddedText(data: openArray[byte], offset, length: int): string =
  var last = length
  while last > 0 and data[offset + last - 1] in [0'u8, 0x20'u8]: dec last
  for index in 0 ..< last:
    let value = data[offset + index]
    if value in 0x20'u8 .. 0x7e'u8: result.add char(value)
    else: result.add "_" & value.toHex(2)

proc entryName(data: openArray[byte], offset: int): string =
  var base = paddedText(data, offset, 8)
  if data[offset] == 0x05 and base.len > 0: base[0] = '_'
  let extension = paddedText(data, offset + 8, 3)
  result = if extension.len > 0: base & "." & extension else: base
  if result.len == 0 or '/' in result or '\\' in result:
    raise newException(ValueError, "invalid FAT directory name")

proc fatValue(volume: FatVolume, data: openArray[byte], cluster: int,
    fatOffset: int): int =
  case volume.kind
  of fkFat12:
    let offset = fatOffset + cluster + cluster div 2
    if offset > data.len - 2:
      raise newException(ValueError, "FAT12 cluster entry is out of range")
    let pair = word(data, offset)
    result = if (cluster and 1) == 0: pair and 0x0fff else: pair shr 4
  of fkFat16:
    let offset = fatOffset + cluster * 2
    if offset > data.len - 2:
      raise newException(ValueError, "FAT16 cluster entry is out of range")
    result = word(data, offset)

proc clusterChain(volume: FatVolume, data: openArray[byte], firstCluster,
    fatOffset, dataOffset: int): seq[int] =
  if firstCluster == 0: return
  var cluster = firstCluster
  var visited = initHashSet[int]()
  let endMarker = if volume.kind == fkFat12: 0x0ff8 else: 0xfff8
  let badMarker = if volume.kind == fkFat12: 0x0ff7 else: 0xfff7
  while cluster < endMarker:
    if cluster < 2 or cluster >= volume.clusterCount + 2:
      raise newException(ValueError, "FAT cluster pointer is out of range")
    if cluster in visited:
      raise newException(ValueError, "cyclic FAT cluster chain")
    visited.incl cluster
    let offset = dataOffset + (cluster - 2) *
      volume.sectorsPerCluster * volume.bytesPerSector
    if offset < dataOffset or offset > data.len -
        volume.sectorsPerCluster * volume.bytesPerSector:
      raise newException(ValueError, "FAT data cluster is out of range")
    result.add cluster
    cluster = fatValue(volume, data, cluster, fatOffset)
    if cluster == badMarker or cluster == 0 or cluster == 1:
      raise newException(ValueError, "invalid FAT cluster-chain terminator")
    if result.len > volume.clusterCount:
      raise newException(ValueError, "FAT cluster chain exceeds volume bounds")

proc chainData(volume: FatVolume, data: openArray[byte], firstCluster,
    fatOffset, dataOffset: int): seq[byte] =
  let clusterBytes = volume.sectorsPerCluster * volume.bytesPerSector
  for cluster in clusterChain(volume, data, firstCluster, fatOffset, dataOffset):
    let offset = dataOffset + (cluster - 2) * clusterBytes
    result.add data.toOpenArray(offset, offset + clusterBytes - 1)

proc parseDirectory(volume: FatVolume, image, directoryData: openArray[byte],
    fatOffset, dataOffset: int, visitedDirectories: var HashSet[int],
    depth: int): seq[FatEntry] =
  if depth > 64: raise newException(ValueError, "FAT directory nesting is too deep")
  var names = initHashSet[string]()
  for offset in countup(0, directoryData.len - 32, 32):
    let first = directoryData[offset]
    if first == 0: break
    if first == 0xe5: continue
    let attributes = int(directoryData[offset + 11])
    if attributes == 0x0f or (attributes and 0x08) != 0: continue
    if (attributes and 0xc0) != 0:
      raise newException(ValueError, "invalid FAT directory attributes")
    let name = entryName(directoryData, offset)
    if name in [".", ".."]: continue
    let folded = name.toLowerAscii
    if folded in names: raise newException(ValueError, "duplicate FAT directory name")
    names.incl folded
    let firstCluster = word(directoryData, offset + 26)
    let size = dword(directoryData, offset + 28)
    if size < 0 or size > image.len:
      raise newException(ValueError, "invalid FAT file size")
    if (attributes and 0x10) != 0:
      if firstCluster < 2 or firstCluster in visitedDirectories:
        raise newException(ValueError, "invalid or cyclic FAT directory cluster")
      visitedDirectories.incl firstCluster
      let contents = chainData(volume, image, firstCluster, fatOffset, dataOffset)
      result.add FatEntry(name: name, kind: fekDirectory,
        attributes: attributes, firstCluster: firstCluster,
        children: parseDirectory(volume, image, contents, fatOffset,
          dataOffset, visitedDirectories, depth + 1))
    else:
      if size > 0 and firstCluster < 2:
        raise newException(ValueError, "non-empty FAT file has no data cluster")
      var contents = chainData(volume, image, firstCluster, fatOffset, dataOffset)
      if contents.len < size:
        raise newException(ValueError, "FAT file cluster chain is truncated")
      contents.setLen(size)
      result.add FatEntry(name: name, kind: fekFile,
        attributes: attributes, firstCluster: firstCluster, size: size,
        data: move(contents))

proc parseFatDiskImage*(data: openArray[byte]): FatVolume =
  if data.len < 512 or data.len > FatMaximumImageBytes:
    raise newException(ValueError, "FAT disk image size is unsupported")
  result.bytesPerSector = word(data, 11)
  result.sectorsPerCluster = int(data[13])
  result.reservedSectors = word(data, 14)
  result.fatCount = int(data[16])
  result.rootEntryCount = word(data, 17)
  let shortSectors = word(data, 19)
  result.mediaDescriptor = int(data[21])
  result.sectorsPerFat = word(data, 22)
  result.totalSectors = if shortSectors != 0: shortSectors else: dword(data, 32)
  if not result.bytesPerSector.isPowerOfTwo or
      result.bytesPerSector notin 128 .. 4096 or
      not result.sectorsPerCluster.isPowerOfTwo or
      result.sectorsPerCluster > 128 or result.reservedSectors < 1 or
      result.fatCount notin 1 .. 4 or result.rootEntryCount == 0 or
      result.sectorsPerFat < 1 or result.totalSectors < 1 or
      result.mediaDescriptor < 0xf0:
    raise newException(ValueError, "invalid FAT BIOS parameter block")
  if result.totalSectors > high(int) div result.bytesPerSector or
      result.totalSectors * result.bytesPerSector != data.len:
    raise newException(ValueError, "FAT volume size disagrees with image length")
  let rootSectors = (result.rootEntryCount * 32 + result.bytesPerSector - 1) div
    result.bytesPerSector
  let firstDataSector = result.reservedSectors +
    result.fatCount * result.sectorsPerFat + rootSectors
  if firstDataSector >= result.totalSectors:
    raise newException(ValueError, "FAT filesystem regions exceed the volume")
  result.clusterCount = (result.totalSectors - firstDataSector) div
    result.sectorsPerCluster
  if result.clusterCount < 1 or result.clusterCount >= 65525:
    raise newException(ValueError, "FAT32 and invalid cluster counts are unsupported")
  result.kind = if result.clusterCount < 4085: fkFat12 else: fkFat16
  let fatOffset = result.reservedSectors * result.bytesPerSector
  let fatBytes = result.sectorsPerFat * result.bytesPerSector
  if fatOffset > data.len - fatBytes or data[fatOffset] != byte(result.mediaDescriptor) or
      data[fatOffset + 1] != 0xff or data[fatOffset + 2] != 0xff:
    raise newException(ValueError, "invalid FAT reserved cluster entries")
  for copy in 1 ..< result.fatCount:
    let other = fatOffset + copy * fatBytes
    if other > data.len - fatBytes or
        data.toOpenArray(fatOffset, fatOffset + fatBytes - 1) !=
          data.toOpenArray(other, other + fatBytes - 1):
      raise newException(ValueError, "FAT copies disagree")
  let rootOffset = (result.reservedSectors +
    result.fatCount * result.sectorsPerFat) * result.bytesPerSector
  let dataOffset = firstDataSector * result.bytesPerSector
  result.oemName = paddedText(data, 3, 8)
  if data.len >= 54 and data[38] in [0x28'u8, 0x29'u8]:
    result.label = paddedText(data, 43, 11)
  var visitedDirectories = initHashSet[int]()
  result.entries = parseDirectory(result, data,
    data.toOpenArray(rootOffset, rootOffset + rootSectors * result.bytesPerSector - 1),
    fatOffset, dataOffset, visitedDirectories, 0)

proc isFatDiskImage*(data: openArray[byte]): bool =
  try: discard parseFatDiskImage(data); true
  except ValueError: false

proc hasImgExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".img", ".ima", ".dsk"]

proc fatKindName*(kind: FatKind): string =
  if kind == fkFat12: "FAT12" else: "FAT16"
