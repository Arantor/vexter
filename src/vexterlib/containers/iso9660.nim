## Read-only base ISO 9660 filesystems in cooked or raw Mode 1 CD images.

import std/[sets, strutils]
import ../byte_sources

const
  Iso9660TypeId* = "filesystem.iso9660"
  Iso9660DirectoryTypeId* = "filesystem.iso9660-directory"
  Iso9660FileTypeId* = "filesystem.iso9660-file"
  Iso9660LogicalBlockSize* = 2048
  Iso9660MaximumEntries* = 200_000
  Iso9660RecursiveInspectionLimit* = 64 * 1024 * 1024

type
  Iso9660Layout* = enum
    ilCooked2048
    ilRawMode1_2352

  Iso9660Entry* = object
    name*: string
    segments*: seq[string]
    isDirectory*: bool
    hidden*, associated*: bool
    extentBlock*, dataLength*: int
    recordingTime*: string
    fileVersion*: int
    systemUseBytes*: int
    posixMode*, posixUid*, posixGid*, posixSerial*: int
    symlinkTarget*: string
    isSymlink*, rockRidgeRelocated*: bool
    data*: seq[byte]

  Iso9660Image* = object
    layout*: Iso9660Layout
    volumeIdentifier*, systemIdentifier*: string
    volumeSetIdentifier*, publisherIdentifier*: string
    preparerIdentifier*, applicationIdentifier*: string
    creationTime*, modificationTime*: string
    logicalBlockSize*, volumeBlocks*: int
    primaryDescriptorCount*, supplementaryDescriptorCount*: int
    bootDescriptorCount*, partitionDescriptorCount*: int
    entries*: seq[Iso9660Entry]

  Iso9660Probe* = object
    layout*: Iso9660Layout
    volumeIdentifier*: string
    volumeBlocks*: int
    primaryDescriptorCount*, supplementaryDescriptorCount*: int

  Iso9660Index* = object
    layout*: Iso9660Layout
    volumeIdentifier*, systemIdentifier*: string
    volumeSetIdentifier*, publisherIdentifier*: string
    preparerIdentifier*, applicationIdentifier*: string
    creationTime*, modificationTime*: string
    logicalBlockSize*, volumeBlocks*: int
    primaryDescriptorCount*, supplementaryDescriptorCount*: int
    bootDescriptorCount*, partitionDescriptorCount*: int
    rootExtent*, rootLength*: int
    rockRidge*: bool
    suspSkip*: int

  SuspInfo = object
    name, symlinkTarget, extensionId: string
    linkPending: string
    nameSeen, symlinkSeen, relocated: bool
    mode, uid, gid, serial, childExtent: int

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc bothWord(data: openArray[byte], offset: int, field: string): int =
  result = data.leWord(offset)
  if result != data.beWord(offset + 2):
    raise newException(ValueError,
      "ISO 9660 both-byte values disagree for " & field)

proc bothDword(data: openArray[byte], offset: int, field: string): int =
  let little = data.leDword(offset)
  if little != data.beDword(offset + 4) or little > uint32(high(int)):
    raise newException(ValueError,
      "ISO 9660 both-byte values disagree or overflow for " & field)
  int(little)

proc paddedText(data: openArray[byte], offset, length: int): string =
  for index in offset ..< offset + length:
    let value = data[index]
    if value == 0: break
    if value >= 0x20 and value < 0x7f: result.add char(value)
    else: result.add "_" & toHex(int(value), 2)
  result = result.strip

proc descriptorTime(data: openArray[byte], offset: int): string =
  let raw = data.paddedText(offset, 16)
  if raw.len == 16 and raw != repeat('0', 16):
    result = raw[0..3] & "-" & raw[4..5] & "-" & raw[6..7] & " " &
      raw[8..9] & ":" & raw[10..11] & ":" & raw[12..13] & "." &
      raw[14..15]

proc recordingTime(data: openArray[byte], offset: int): string =
  let year = int(data[offset]) + 1900
  result = align($year, 4, '0') & "-" & align($data[offset + 1], 2, '0') &
    "-" & align($data[offset + 2], 2, '0') & " " &
    align($data[offset + 3], 2, '0') & ":" &
    align($data[offset + 4], 2, '0') & ":" &
    align($data[offset + 5], 2, '0')

proc appendSuspArea(area: openArray[byte], start: int, info: var SuspInfo,
    continuation: var tuple[blockNumber, offset, length: int]) =
  var cursor = start
  while cursor + 4 <= area.len:
    let fieldLength = int(area[cursor + 2])
    if fieldLength == 0: break
    if fieldLength < 4 or cursor > area.len - fieldLength:
      raise newException(ValueError, "invalid SUSP field bounds")
    let signature = $char(area[cursor]) & $char(area[cursor + 1])
    if area[cursor + 3] != 1:
      cursor += fieldLength
      continue
    case signature
    of "ST":
      if fieldLength != 4: raise newException(ValueError, "invalid SUSP ST field")
      break
    of "CE":
      if fieldLength != 28: raise newException(ValueError, "invalid SUSP CE field")
      continuation = (area.bothDword(cursor + 4, "SUSP continuation block"),
        area.bothDword(cursor + 12, "SUSP continuation offset"),
        area.bothDword(cursor + 20, "SUSP continuation length"))
    of "ER":
      if fieldLength < 8: raise newException(ValueError, "invalid SUSP ER field")
      let identifierLength = int(area[cursor + 4])
      if cursor + 8 + identifierLength > cursor + fieldLength:
        raise newException(ValueError, "truncated SUSP extension identifier")
      for index in cursor + 8 ..< cursor + 8 + identifierLength:
        info.extensionId.add char(area[index])
    of "PX":
      if fieldLength >= 36:
        info.mode = area.bothDword(cursor + 4, "Rock Ridge mode")
        info.uid = area.bothDword(cursor + 20, "Rock Ridge uid")
        info.gid = area.bothDword(cursor + 28, "Rock Ridge gid")
        if fieldLength >= 44:
          info.serial = area.bothDword(cursor + 36, "Rock Ridge serial")
    of "NM":
      if fieldLength < 5: raise newException(ValueError, "invalid Rock Ridge NM field")
      let flags = int(area[cursor + 4])
      if (flags and 2) != 0: info.name = "."
      elif (flags and 4) != 0: info.name = ".."
      else:
        for index in cursor + 5 ..< cursor + fieldLength:
          let value = area[index]
          if value in [0'u8, byte('/'), byte('\\')]:
            raise newException(ValueError, "unsafe Rock Ridge alternate name")
          info.name.add char(value)
      info.nameSeen = true
    of "SL":
      if fieldLength < 5: raise newException(ValueError, "invalid Rock Ridge SL field")
      var component = cursor + 5
      while component < cursor + fieldLength:
        if component + 2 > cursor + fieldLength:
          raise newException(ValueError, "truncated Rock Ridge link component")
        let flags = int(area[component])
        let length = int(area[component + 1])
        if component + 2 + length > cursor + fieldLength:
          raise newException(ValueError, "truncated Rock Ridge link component")
        var value = ""
        if (flags and 8) != 0:
          value = ""
          if info.symlinkTarget.len == 0: info.symlinkTarget = "/"
        elif (flags and 4) != 0: value = ".."
        elif (flags and 2) != 0: value = "."
        else:
          for index in component + 2 ..< component + 2 + length:
            value.add char(area[index])
        info.linkPending.add value
        if (flags and 1) == 0:
          if info.symlinkTarget.len > 0 and
              not info.symlinkTarget.endsWith("/"):
            info.symlinkTarget.add "/"
          info.symlinkTarget.add info.linkPending
          info.linkPending.setLen(0)
        component += 2 + length
      info.symlinkSeen = true
    of "CL":
      if fieldLength != 12: raise newException(ValueError, "invalid Rock Ridge CL field")
      info.childExtent = area.bothDword(cursor + 4, "Rock Ridge child link")
    of "RE":
      if fieldLength != 4: raise newException(ValueError, "invalid Rock Ridge RE field")
      info.relocated = true
    else: discard
    cursor += fieldLength

proc parseSusp(initial: openArray[byte], start, volumeBlocks: int,
    readContinuation: proc(logicalOffset, length: int): seq[byte] {.closure.}): SuspInfo =
  var area = @initial
  var areaStart = start
  var seen = initHashSet[string]()
  for depth in 0 .. 16:
    var continuation = (blockNumber: 0, offset: 0, length: 0)
    appendSuspArea(area, areaStart, result, continuation)
    if continuation.length == 0: return
    if continuation.blockNumber < 0 or continuation.blockNumber >= volumeBlocks or
        continuation.offset < 0 or continuation.length < 0 or
        continuation.offset + continuation.length > Iso9660LogicalBlockSize:
      raise newException(ValueError, "SUSP continuation is outside one logical block")
    let identity = $continuation.blockNumber & ":" & $continuation.offset & ":" & $continuation.length
    if identity in seen: raise newException(ValueError, "cyclic SUSP continuation")
    seen.incl identity
    area = readContinuation(continuation.blockNumber * Iso9660LogicalBlockSize +
      continuation.offset, continuation.length)
    areaStart = 0
  raise newException(ValueError, "SUSP continuation chain exceeds safety limit")

proc rawSectorValid(data: openArray[byte], sector: int): bool =
  let offset = sector * 2352
  if offset < 0 or offset > data.len - 2352: return false
  if data[offset] != 0 or data[offset + 11] != 0 or data[offset + 15] != 1:
    return false
  for index in 1 .. 10:
    if data[offset + index] != 0xff: return false
  true

proc detectLayout(data: openArray[byte]): Iso9660Layout =
  if data.len >= 17 * Iso9660LogicalBlockSize and
      data[16 * Iso9660LogicalBlockSize + 1] == byte('C') and
      data[16 * Iso9660LogicalBlockSize + 2] == byte('D') and
      data[16 * Iso9660LogicalBlockSize + 3] == byte('0') and
      data[16 * Iso9660LogicalBlockSize + 4] == byte('0') and
      data[16 * Iso9660LogicalBlockSize + 5] == byte('1'):
    return ilCooked2048
  let rawOffset = 16 * 2352 + 16
  if data.len mod 2352 == 0 and data.len >= 17 * 2352 and
      rawSectorValid(data, 0) and rawSectorValid(data, 16) and
      data[rawOffset + 1] == byte('C') and data[rawOffset + 2] == byte('D') and
      data[rawOffset + 3] == byte('0') and data[rawOffset + 4] == byte('0') and
      data[rawOffset + 5] == byte('1'):
    return ilRawMode1_2352
  raise newException(ValueError,
    "ISO 9660 volume descriptor was not found in a cooked or raw Mode 1 image")

proc physicalSectors(data: openArray[byte], layout: Iso9660Layout): int =
  if layout == ilCooked2048: data.len div Iso9660LogicalBlockSize
  else: data.len div 2352

proc readLogical(data: openArray[byte], layout: Iso9660Layout,
    logicalOffset, length: int): seq[byte] =
  if logicalOffset < 0 or length < 0: raise newException(ValueError,
    "negative ISO 9660 data range")
  let sectorCount = physicalSectors(data, layout)
  if logicalOffset > sectorCount * Iso9660LogicalBlockSize - length:
    raise newException(ValueError, "ISO 9660 extent is outside the image")
  result = newSeq[byte](length)
  var sourceOffset = logicalOffset
  var targetOffset = 0
  while targetOffset < length:
    let sector = sourceOffset div Iso9660LogicalBlockSize
    let within = sourceOffset mod Iso9660LogicalBlockSize
    let amount = min(length - targetOffset,
      Iso9660LogicalBlockSize - within)
    let physical = if layout == ilCooked2048:
        sector * Iso9660LogicalBlockSize + within
      else:
        if not rawSectorValid(data, sector):
          raise newException(ValueError,
            "invalid raw Mode 1 sector framing at sector " & $sector)
        sector * 2352 + 16 + within
    for index in 0 ..< amount:
      result[targetOffset + index] = data[physical + index]
    sourceOffset += amount
    targetOffset += amount

proc descriptor(data: openArray[byte], layout: Iso9660Layout,
    sector: int): seq[byte] =
  readLogical(data, layout, sector * Iso9660LogicalBlockSize,
    Iso9660LogicalBlockSize)

proc validateRootRecord(record: openArray[byte], volumeBlocks: int): tuple[
    extent, length: int] =
  if record.len < 34:
    raise newException(ValueError, "invalid ISO 9660 root directory record")
  # Some mastered discs leave the root identifier length as zero. The root
  # extent and directory flag still identify the record unambiguously, and
  # DOS/CD implementations commonly accept this compatibility defect.
  let rootIdentifierValid = record[32] == 0 or
    (record[32] == 1 and record[33] == 0)
  if record[0] < 34 or not rootIdentifierValid or
      (record[25] and 2) == 0:
    raise newException(ValueError, "invalid ISO 9660 root directory record")
  result.extent = record.bothDword(2, "root extent")
  result.length = record.bothDword(10, "root length")
  discard record.bothWord(28, "root volume sequence")
  if result.length <= 0 or result.extent < 0 or
      result.extent >= volumeBlocks or
      result.length > (volumeBlocks - result.extent) * Iso9660LogicalBlockSize:
    raise newException(ValueError, "ISO 9660 root directory is outside the volume")

proc probeIso9660*(data: openArray[byte]): Iso9660Probe =
  result.layout = detectLayout(data)
  let sectors = physicalSectors(data, result.layout)
  var sawPrimary, sawTerminator: bool
  for sector in 16 ..< min(sectors, 16 + 256):
    let item = descriptor(data, result.layout, sector)
    if item.paddedText(1, 5) != "CD001" or item[6] != 1:
      raise newException(ValueError, "invalid ISO 9660 volume descriptor")
    case item[0]
    of 0: discard
    of 1:
      inc result.primaryDescriptorCount
      if not sawPrimary:
        sawPrimary = true
        result.volumeBlocks = item.bothDword(80, "volume space size")
        if item.bothWord(128, "logical block size") != Iso9660LogicalBlockSize:
          raise newException(ValueError,
            "only 2048-byte ISO 9660 logical blocks are supported")
        if result.volumeBlocks <= 16 or result.volumeBlocks > sectors:
          raise newException(ValueError,
            "ISO 9660 declared volume exceeds the image")
        result.volumeIdentifier = item.paddedText(40, 32)
        discard validateRootRecord(item.toOpenArray(156, 189),
          result.volumeBlocks)
    of 2: inc result.supplementaryDescriptorCount
    of 3: discard
    of 255:
      sawTerminator = true
      break
    else: discard
  if not sawPrimary or not sawTerminator:
    raise newException(ValueError,
      "ISO 9660 primary descriptor or terminator is missing")

proc decodedIdentifier(record: openArray[byte]): tuple[name: string,
    version: int] =
  let length = int(record[32])
  if length <= 0 or 33 + length > record.len:
    raise newException(ValueError, "invalid ISO 9660 file identifier")
  var raw = ""
  for index in 33 ..< 33 + length:
    let value = record[index]
    if value >= 0x20 and value < 0x7f and value notin [byte('/'), byte('\\')]:
      raw.add char(value)
    else:
      raw.add "_" & toHex(int(value), 2)
  let semicolon = raw.rfind(';')
  if semicolon >= 0 and semicolon < raw.high:
    try:
      result.version = parseInt(raw[semicolon + 1 .. ^1])
      raw.setLen(semicolon)
    except ValueError: discard
  if raw.endsWith('.'): raw.setLen(raw.len - 1)
  if raw.len == 0 or raw in [".", ".."]:
    raise newException(ValueError, "empty or ambiguous ISO 9660 file identifier")
  result.name = raw

proc walkDirectory(data: openArray[byte], layout: Iso9660Layout,
    volumeBlocks, extent, length: int, parent: seq[string], depth: int,
    visited, paths: var HashSet[string], entries: var seq[Iso9660Entry]) =
  if depth > 64: raise newException(ValueError,
    "ISO 9660 directory nesting exceeds safety limit")
  let identity = $extent & ":" & $length
  if identity in visited:
    raise newException(ValueError, "cyclic ISO 9660 directory extent")
  visited.incl identity
  let directory = readLogical(data, layout,
    extent * Iso9660LogicalBlockSize, length)
  var offset = 0
  while offset < directory.len:
    let withinBlock = offset mod Iso9660LogicalBlockSize
    let recordLength = int(directory[offset])
    if recordLength == 0:
      offset += Iso9660LogicalBlockSize - withinBlock
      continue
    if recordLength < 34 or recordLength >
        Iso9660LogicalBlockSize - withinBlock or
        offset > directory.len - recordLength:
      raise newException(ValueError, "invalid ISO 9660 directory record bounds")
    let record = directory[offset ..< offset + recordLength]
    let identifierLength = int(record[32])
    if 33 + identifierLength > recordLength:
      raise newException(ValueError, "truncated ISO 9660 file identifier")
    let special = identifierLength == 1 and record[33] in [0'u8, 1'u8]
    if special:
      # Some otherwise mountable images contain stale or mismatched redundant
      # endian fields in the self/parent records. Vexter never follows these
      # records, so only their framing and special identifier are relevant.
      offset += recordLength
      continue
    let entryExtent = record.bothDword(2, "entry extent")
    let entryLength = record.bothDword(10, "entry length")
    discard record.bothWord(28, "entry volume sequence")
    if entryExtent < 0 or entryExtent > volumeBlocks or entryLength < 0 or
        entryLength > (volumeBlocks - entryExtent) * Iso9660LogicalBlockSize:
      raise newException(ValueError, "ISO 9660 entry extent is outside the volume")
    let flags = int(record[25])
    if (flags and 0x80) != 0:
      raise newException(ValueError,
        "multi-extent ISO 9660 files are not supported")
    if not special:
      if entries.len >= Iso9660MaximumEntries:
        raise newException(ValueError, "ISO 9660 entry count exceeds safety limit")
      let identifier = decodedIdentifier(record)
      var segments = parent
      segments.add identifier.name
      let canonical = segments.join("/")
      if canonical in paths:
        raise newException(ValueError, "duplicate ISO 9660 path: " & canonical)
      paths.incl canonical
      let padding = if identifierLength mod 2 == 0: 1 else: 0
      let systemUseStart = 33 + identifierLength + padding
      let isDirectory = (flags and 2) != 0
      var entry = Iso9660Entry(name: canonical, segments: segments,
        isDirectory: isDirectory, hidden: (flags and 1) != 0,
        associated: (flags and 4) != 0, extentBlock: entryExtent,
        dataLength: entryLength, recordingTime: record.recordingTime(18),
        fileVersion: identifier.version,
        systemUseBytes: max(0, recordLength - systemUseStart))
      # File payloads can be large. Make the ownership transfer explicit;
      # copying the temporary here causes quadratic memory use on discs with
      # many files under Nim's checked memory manager.
      entries.add move(entry)
      if isDirectory:
        walkDirectory(data, layout, volumeBlocks, entryExtent, entryLength,
          segments, depth + 1, visited, paths, entries)
    offset += recordLength

proc parseIso9660*(data: openArray[byte]): Iso9660Image =
  let probe = probeIso9660(data)
  result.layout = probe.layout
  result.volumeIdentifier = probe.volumeIdentifier
  result.volumeBlocks = probe.volumeBlocks
  result.primaryDescriptorCount = probe.primaryDescriptorCount
  result.supplementaryDescriptorCount = probe.supplementaryDescriptorCount
  result.logicalBlockSize = Iso9660LogicalBlockSize
  let sectors = physicalSectors(data, result.layout)
  var primary: seq[byte]
  for sector in 16 ..< min(sectors, 16 + 256):
    let item = descriptor(data, result.layout, sector)
    case item[0]
    of 0: inc result.bootDescriptorCount
    of 1:
      if primary.len == 0: primary = item
    of 2: discard
    of 3: inc result.partitionDescriptorCount
    of 255: break
    else: discard
  result.systemIdentifier = primary.paddedText(8, 32)
  result.volumeSetIdentifier = primary.paddedText(190, 128)
  result.publisherIdentifier = primary.paddedText(318, 128)
  result.preparerIdentifier = primary.paddedText(446, 128)
  result.applicationIdentifier = primary.paddedText(574, 128)
  result.creationTime = primary.descriptorTime(813)
  result.modificationTime = primary.descriptorTime(830)
  let root = validateRootRecord(primary.toOpenArray(156, 189),
    result.volumeBlocks)
  # Growing a seq of objects which own file buffers can deep-copy every prior
  # buffer under Nim's checked memory management. Reserve a bounded table up
  # front so large discs remain linear in their payload size.
  result.entries = newSeqOfCap[Iso9660Entry](
    min(Iso9660MaximumEntries, min(result.volumeBlocks, 65_536)))
  var visited = initHashSet[string]()
  var paths = initHashSet[string]()
  walkDirectory(data, result.layout, result.volumeBlocks, root.extent,
    root.length, @[], 0, visited, paths, result.entries)

proc isIso9660*(data: openArray[byte]): bool =
  try:
    discard probeIso9660(data)
    true
  except ValueError:
    false

proc extractIso9660Entry*(data: openArray[byte], image: Iso9660Image,
    entry: Iso9660Entry): seq[byte] =
  ## Extracts a validated file extent on demand. Keeping parsed directory
  ## records lightweight avoids retaining a second complete copy of a disc.
  if entry.isDirectory:
    raise newException(ValueError, "cannot extract an ISO 9660 directory")
  readLogical(data, image.layout,
    entry.extentBlock * Iso9660LogicalBlockSize, entry.dataLength)

proc hasIso9660Extension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".iso")

proc iso9660LayoutName*(layout: Iso9660Layout): string =
  case layout
  of ilCooked2048: "cooked 2048-byte sectors"
  of ilRawMode1_2352: "raw Mode 1/2352 sectors"

proc rawSectorValid(source: VextByteSource, sector: int): bool =
  let offset = sector * 2352
  if offset < 0 or offset > source.length - 2352: return false
  let header = source.readAt(offset, 16)
  if header[0] != 0 or header[11] != 0 or header[15] != 1: return false
  for index in 1 .. 10:
    if header[index] != 0xff: return false
  true

proc detectLayout(source: VextByteSource): Iso9660Layout =
  if source.length >= 17 * Iso9660LogicalBlockSize:
    let signature = source.readAt(16 * Iso9660LogicalBlockSize + 1, 5)
    if signature == @[byte('C'), byte('D'), byte('0'), byte('0'), byte('1')]:
      return ilCooked2048
  if source.length mod 2352 == 0 and source.length >= 17 * 2352 and
      source.rawSectorValid(0) and source.rawSectorValid(16):
    let signature = source.readAt(16 * 2352 + 17, 5)
    if signature == @[byte('C'), byte('D'), byte('0'), byte('0'), byte('1')]:
      return ilRawMode1_2352
  raise newException(ValueError,
    "ISO 9660 volume descriptor was not found in a cooked or raw Mode 1 image")

proc physicalSectors(source: VextByteSource, layout: Iso9660Layout): int =
  if layout == ilCooked2048: source.length div Iso9660LogicalBlockSize
  else: source.length div 2352

proc readLogical*(source: VextByteSource, layout: Iso9660Layout,
    logicalOffset, length: int): seq[byte] =
  if logicalOffset < 0 or length < 0:
    raise newException(ValueError, "negative ISO 9660 data range")
  let sectorCount = source.physicalSectors(layout)
  if logicalOffset > sectorCount * Iso9660LogicalBlockSize - length:
    raise newException(ValueError, "ISO 9660 extent is outside the image")
  result = newSeq[byte](length)
  var sourceOffset = logicalOffset
  var targetOffset = 0
  while targetOffset < length:
    let sector = sourceOffset div Iso9660LogicalBlockSize
    let within = sourceOffset mod Iso9660LogicalBlockSize
    let amount = min(length - targetOffset,
      Iso9660LogicalBlockSize - within)
    let physical = if layout == ilCooked2048:
        sector * Iso9660LogicalBlockSize + within
      else:
        if not source.rawSectorValid(sector):
          raise newException(ValueError,
            "invalid raw Mode 1 sector framing at sector " & $sector)
        sector * 2352 + 16 + within
    let part = source.readAt(physical, amount)
    for index in 0 ..< amount: result[targetOffset + index] = part[index]
    sourceOffset += amount
    targetOffset += amount

proc sourceDescriptor(source: VextByteSource, layout: Iso9660Layout,
    sector: int): seq[byte] =
  source.readLogical(layout, sector * Iso9660LogicalBlockSize,
    Iso9660LogicalBlockSize)

proc indexIso9660*(source: VextByteSource): Iso9660Index =
  ## Validates volume descriptors and the root record without walking any
  ## descendant directory.
  result.layout = source.detectLayout()
  result.logicalBlockSize = Iso9660LogicalBlockSize
  let sectors = source.physicalSectors(result.layout)
  var primary: seq[byte]
  var sawTerminator = false
  for sector in 16 ..< min(sectors, 16 + 256):
    let item = source.sourceDescriptor(result.layout, sector)
    if item.paddedText(1, 5) != "CD001" or item[6] != 1:
      raise newException(ValueError, "invalid ISO 9660 volume descriptor")
    case item[0]
    of 0: inc result.bootDescriptorCount
    of 1:
      inc result.primaryDescriptorCount
      if primary.len == 0:
        primary = item
        result.volumeBlocks = item.bothDword(80, "volume space size")
        if item.bothWord(128, "logical block size") != Iso9660LogicalBlockSize:
          raise newException(ValueError,
            "only 2048-byte ISO 9660 logical blocks are supported")
        if result.volumeBlocks <= 16 or result.volumeBlocks > sectors:
          raise newException(ValueError,
            "ISO 9660 declared volume exceeds the image")
    of 2: inc result.supplementaryDescriptorCount
    of 3: inc result.partitionDescriptorCount
    of 255:
      sawTerminator = true
      break
    else: discard
  if primary.len == 0 or not sawTerminator:
    raise newException(ValueError,
      "ISO 9660 primary descriptor or terminator is missing")
  result.volumeIdentifier = primary.paddedText(40, 32)
  result.systemIdentifier = primary.paddedText(8, 32)
  result.volumeSetIdentifier = primary.paddedText(190, 128)
  result.publisherIdentifier = primary.paddedText(318, 128)
  result.preparerIdentifier = primary.paddedText(446, 128)
  result.applicationIdentifier = primary.paddedText(574, 128)
  result.creationTime = primary.descriptorTime(813)
  result.modificationTime = primary.descriptorTime(830)
  let root = validateRootRecord(primary.toOpenArray(156, 189),
    result.volumeBlocks)
  result.rootExtent = root.extent
  result.rootLength = root.length
  # SUSP is announced by SP in the first (self) record of the root directory.
  # Its final byte applies as a skip before every subsequent System Use area.
  let rootBytes = source.readLogical(result.layout,
    result.rootExtent * Iso9660LogicalBlockSize, min(result.rootLength,
    Iso9660LogicalBlockSize))
  if rootBytes.len >= 41:
    let recordLength = int(rootBytes[0])
    let identifierLength = int(rootBytes[32])
    let systemUseStart = 33 + identifierLength +
      (if identifierLength mod 2 == 0: 1 else: 0)
    if recordLength <= rootBytes.len and systemUseStart + 7 <= recordLength and
        rootBytes[systemUseStart] == byte('S') and
        rootBytes[systemUseStart + 1] == byte('P') and
        rootBytes[systemUseStart + 2] == 7 and
        rootBytes[systemUseStart + 3] == 1 and
        rootBytes[systemUseStart + 4] == 0xbe and
        rootBytes[systemUseStart + 5] == 0xef:
      result.suspSkip = int(rootBytes[systemUseStart + 6])
      let suspLayout = result.layout
      let rootSusp = parseSusp(rootBytes.toOpenArray(0, recordLength - 1),
        systemUseStart, result.volumeBlocks,
        proc(logicalOffset, length: int): seq[byte] =
          source.readLogical(suspLayout, logicalOffset, length))
      result.rockRidge = rootSusp.extensionId in ["RRIP_1991A", "IEEE_P1282"]

proc listIso9660Directory*(source: VextByteSource, index: Iso9660Index,
    extent, length: int, parent: seq[string]): seq[Iso9660Entry] =
  ## Reads and validates exactly one indexed directory extent.
  let directory = source.readLogical(index.layout,
    extent * Iso9660LogicalBlockSize, length)
  var offset = 0
  var paths = initHashSet[string]()
  while offset < directory.len:
    let withinBlock = offset mod Iso9660LogicalBlockSize
    let recordLength = int(directory[offset])
    if recordLength == 0:
      offset += Iso9660LogicalBlockSize - withinBlock
      continue
    if recordLength < 34 or recordLength >
        Iso9660LogicalBlockSize - withinBlock or
        offset > directory.len - recordLength:
      raise newException(ValueError, "invalid ISO 9660 directory record bounds")
    let record = directory[offset ..< offset + recordLength]
    let identifierLength = int(record[32])
    if 33 + identifierLength > recordLength:
      raise newException(ValueError, "truncated ISO 9660 file identifier")
    let special = identifierLength == 1 and record[33] in [0'u8, 1'u8]
    if special:
      # These navigation aliases are not exposed or followed. Accept broken
      # redundant endian values seen in otherwise valid, mountable media.
      offset += recordLength
      continue
    let entryExtent = record.bothDword(2, "entry extent")
    let entryLength = record.bothDword(10, "entry length")
    discard record.bothWord(28, "entry volume sequence")
    if entryExtent < 0 or entryExtent > index.volumeBlocks or entryLength < 0 or
        entryLength > (index.volumeBlocks - entryExtent) * Iso9660LogicalBlockSize:
      raise newException(ValueError, "ISO 9660 entry extent is outside the volume")
    let flags = int(record[25])
    if (flags and 0x80) != 0:
      raise newException(ValueError,
        "multi-extent ISO 9660 files are not supported")
    if not special:
      let identifier = decodedIdentifier(record)
      let padding = if identifierLength mod 2 == 0: 1 else: 0
      let systemUseStart = 33 + identifierLength + padding
      var susp: SuspInfo
      if index.rockRidge and systemUseStart + index.suspSkip < recordLength:
        susp = parseSusp(record, systemUseStart + index.suspSkip,
          index.volumeBlocks, proc(logicalOffset, length: int): seq[byte] =
            source.readLogical(index.layout, logicalOffset, length))
      if susp.relocated:
        offset += recordLength
        continue
      let presentedName = if susp.nameSeen and susp.name.len > 0:
          susp.name else: identifier.name
      var segments = parent
      segments.add presentedName
      let canonical = segments.join("/")
      if canonical in paths:
        raise newException(ValueError, "duplicate ISO 9660 path: " & canonical)
      paths.incl canonical
      let presentedExtent = if susp.childExtent > 0: susp.childExtent else: entryExtent
      result.add Iso9660Entry(name: canonical, segments: segments,
        isDirectory: (flags and 2) != 0 or susp.childExtent > 0,
        hidden: (flags and 1) != 0,
        associated: (flags and 4) != 0, extentBlock: presentedExtent,
        dataLength: entryLength, recordingTime: record.recordingTime(18),
        fileVersion: identifier.version,
        systemUseBytes: max(0, recordLength - systemUseStart),
        posixMode: susp.mode, posixUid: susp.uid, posixGid: susp.gid,
        posixSerial: susp.serial, symlinkTarget: susp.symlinkTarget,
        isSymlink: susp.symlinkSeen)
    offset += recordLength

proc extractIso9660Entry*(source: VextByteSource, index: Iso9660Index,
    entry: Iso9660Entry, maximumSize = high(int)): seq[byte] =
  if entry.isDirectory:
    raise newException(ValueError, "cannot extract an ISO 9660 directory")
  if entry.dataLength > maximumSize:
    raise newException(ValueError,
      "ISO 9660 member exceeds the permitted materialization size")
  source.readLogical(index.layout,
    entry.extentBlock * Iso9660LogicalBlockSize, entry.dataLength)
