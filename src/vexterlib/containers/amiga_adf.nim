## Read-only parsing for classic AmigaDOS OFS/FFS floppy images.

import std/[algorithm, os, strutils]

const
  AmigaAdfTypeId* = "amiga.adf"
  AmigaAdfFileTypeId* = "amiga.adf-file"
  AmigaAdfDirectoryTypeId* = "amiga.adf-directory"
  AmigaAdfLinkTypeId* = "amiga.adf-link"
  AmigaAdfBlockSize* = 512
  AmigaAdfDdSize* = 901120
  AmigaAdfHdSize* = 1802240
  AdfHashEntries = 72

type
  AmigaAdfEntryKind* = enum
    aaekFile
    aaekDirectory
    aaekLink

  AmigaAdfEntry* = ref object
    name*: string
    sector*: int
    kind*: AmigaAdfEntryKind
    size*: int
    comment*: string
    data*: seq[byte]
    children*: seq[AmigaAdfEntry]

  AmigaAdfVolume* = object
    name*: string
    filesystem*: string
    flags*: int
    rootBlock*: int
    entries*: seq[AmigaAdfEntry]

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc signedDword(data: openArray[byte], offset: int): int32 {.inline.} =
  cast[int32](beDword(data, offset))

proc blockOffset(sector, blockCount: int): int =
  if sector <= 1 or sector >= blockCount:
    raise newException(ValueError, "ADF block pointer is out of range")
  sector * AmigaAdfBlockSize

proc validBlockChecksum(data: openArray[byte], offset: int): bool =
  var sum = 0'u32
  for position in countup(offset, offset + AmigaAdfBlockSize - 4, 4):
    sum += beDword(data, position)
  sum == 0

proc amigaString(data: openArray[byte], lengthOffset, maximum: int): string =
  let length = int(data[lengthOffset])
  if length > maximum or lengthOffset + length >= data.len:
    raise newException(ValueError, "invalid ADF string length")
  for index in 0 ..< length:
    let value = data[lengthOffset + 1 + index]
    if value < 0x80:
      result.add char(value)
    else:
      # AmigaDOS filenames use the native eight-bit character set. Preserve
      # its Latin-1 code points as valid UTF-8 for paths and JSON output.
      result.add char(0xc0 or (value shr 6))
      result.add char(0x80 or (value and 0x3f))

proc readFileData(data: openArray[byte], headerOffset, blockCount: int,
    fastFileSystem: bool): seq[byte] =
  let fileSize = int(beDword(data, headerOffset + 324))
  if fileSize < 0 or fileSize > data.len:
    raise newException(ValueError, "invalid ADF file size")
  var remaining = fileSize
  var pointerBlockOffset = headerOffset
  var visited: seq[bool] = newSeq[bool](blockCount)
  while remaining > 0:
    if not validBlockChecksum(data, pointerBlockOffset):
      raise newException(ValueError, "invalid ADF file-header checksum")
    let highSequence = int(beDword(data, pointerBlockOffset + 8))
    if highSequence < 0 or highSequence > AdfHashEntries:
      raise newException(ValueError, "invalid ADF data-block count")
    for index in 0 ..< highSequence:
      let sector = int(beDword(data, pointerBlockOffset + 308 - index * 4))
      let offset = blockOffset(sector, blockCount)
      if visited[sector]:
        raise newException(ValueError, "cyclic ADF file data pointers")
      visited[sector] = true
      if fastFileSystem:
        let amount = min(remaining, AmigaAdfBlockSize)
        result.add data.toOpenArray(offset, offset + amount - 1)
        remaining -= amount
      else:
        if beDword(data, offset) != 8 or not validBlockChecksum(data, offset):
          raise newException(ValueError, "invalid OFS data block")
        let amount = int(beDword(data, offset + 12))
        if amount < 0 or amount > 488 or amount > remaining:
          raise newException(ValueError, "invalid OFS data-block size")
        if amount > 0:
          result.add data.toOpenArray(offset + 24, offset + 23 + amount)
        remaining -= amount
    if remaining == 0:
      break
    let extension = int(beDword(data, pointerBlockOffset + 504))
    if extension == 0:
      raise newException(ValueError, "truncated ADF file block chain")
    pointerBlockOffset = blockOffset(extension, blockCount)
    if visited[extension]:
      raise newException(ValueError, "cyclic ADF file extension chain")
    visited[extension] = true
    if beDword(data, pointerBlockOffset) != 16 or
        signedDword(data, pointerBlockOffset + 508) != -3:
      raise newException(ValueError, "invalid ADF file extension block")

proc parseDirectory(data: openArray[byte], directoryOffset, blockCount: int,
    fastFileSystem: bool, visitedDirectories: var seq[bool]): seq[AmigaAdfEntry] =
  for bucket in 0 ..< AdfHashEntries:
    var sector = int(beDword(data, directoryOffset + 24 + bucket * 4))
    var chainSeen = newSeq[bool](blockCount)
    while sector != 0:
      let offset = blockOffset(sector, blockCount)
      if chainSeen[sector]:
        raise newException(ValueError, "cyclic ADF directory hash chain")
      chainSeen[sector] = true
      if beDword(data, offset) != 2 or not validBlockChecksum(data, offset):
        raise newException(ValueError, "invalid ADF directory entry block")
      let secondaryType = signedDword(data, offset + 508)
      let name = amigaString(data, offset + 432, 30)
      if name.len == 0 or '/' in name or ':' in name:
        raise newException(ValueError, "invalid ADF entry name")
      let comment = amigaString(data, offset + 328, 79)
      case secondaryType
      of -3:
        result.add AmigaAdfEntry(
          name: name, sector: sector, kind: aaekFile,
          size: int(beDword(data, offset + 324)), comment: comment,
          data: readFileData(data, offset, blockCount, fastFileSystem))
      of 2:
        if visitedDirectories[sector]:
          if offset != directoryOffset:
            raise newException(ValueError, "cyclic ADF directory tree at block " &
              $sector & " (" & name & ")")
          # Some authentic OFS game disks include their own directory header
          # in the first hash slot. It is a self-entry, not a child to recurse
          # into. Its next-hash field belongs to this directory's entry in its
          # parent, so it must not be followed from the child hash table.
          break
        else:
          visitedDirectories[sector] = true
          result.add AmigaAdfEntry(
            name: name, sector: sector, kind: aaekDirectory, comment: comment,
            children: parseDirectory(data, offset, blockCount, fastFileSystem,
              visitedDirectories))
      of -4, 3, 4:
        result.add AmigaAdfEntry(
          name: name, sector: sector, kind: aaekLink, comment: comment)
      else:
        raise newException(ValueError, "unsupported ADF directory entry type")
      sector = int(beDword(data, offset + 496))
  result.sort(proc (left, right: AmigaAdfEntry): int =
    cmp(left.name.toLowerAscii, right.name.toLowerAscii))

proc parseAmigaAdf*(data: openArray[byte]): AmigaAdfVolume =
  if data.len notin [AmigaAdfDdSize, AmigaAdfHdSize] or
      data.len mod AmigaAdfBlockSize != 0:
    raise newException(ValueError, "unsupported ADF floppy image size")
  if data[0] != byte('D') or data[1] != byte('O') or data[2] != byte('S') or
      data[3] > 5:
    raise newException(ValueError, "invalid AmigaDOS ADF boot signature")
  result.flags = int(data[3])
  result.filesystem = if (result.flags and 1) != 0: "FFS" else: "OFS"
  let blockCount = data.len div AmigaAdfBlockSize
  result.rootBlock = blockCount div 2
  let rootOffset = result.rootBlock * AmigaAdfBlockSize
  if beDword(data, rootOffset) != 2 or beDword(data, rootOffset + 12) != 72 or
      signedDword(data, rootOffset + 508) != 1 or
      not validBlockChecksum(data, rootOffset):
    raise newException(ValueError, "invalid ADF root block")
  result.name = amigaString(data, rootOffset + 432, 30)
  var visitedDirectories = newSeq[bool](blockCount)
  visitedDirectories[result.rootBlock] = true
  result.entries = parseDirectory(data, rootOffset, blockCount,
    (result.flags and 1) != 0, visitedDirectories)

proc isAmigaAdf*(data: openArray[byte]): bool =
  try:
    discard parseAmigaAdf(data)
    true
  except ValueError:
    false

proc hasAmigaAdfExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".adf"
