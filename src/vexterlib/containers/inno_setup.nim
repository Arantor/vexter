## Structural reader for installers produced by Inno Setup.
##
## The loader layout and signatures are derived from Daniel Scharrer's
## innoextract (zlib licence), supplied in the repository's innoextract/
## checkout. This is an independent Nim implementation with bounded reads.

import std/strutils
import ../byte_sources
import ../compression/lzma

const
  InnoSetupTypeId* = "windows.inno-setup"
  InnoSetupLoaderTypeId* = "windows.inno-setup-loader"
  InnoSetupHeaderTypeId* = "windows.inno-setup-headers"
  InnoSetupDataTypeId* = "windows.inno-setup-data"
  InnoSetupEmbeddedExeTypeId* = "windows.inno-setup-embedded-executable"

type InnoSetupInstaller* = object
  loaderOffset*: int
  loaderLength*: int
  headerOffset*: int
  headerLength*: int
  dataOffset*: int
  embeddedExeOffset*: int
  embeddedExeCompressedSize*: int
  embeddedExeUncompressedSize*: int
  loaderVersion*: string
  setupVersion*: string
  loaderInPeResource*: bool

type InnoSetupHeaderStreams* = object
  primary*, secondary*: seq[byte]

proc requireRange(data: openArray[byte], offset, length: int)
proc le32(data: openArray[byte], offset: int): uint32

type
  InnoSetupVersion* = object
    major*, minor*, patch*, revision*: int
    unicode*: bool
  InnoSetupHeaderCounts* = object
    appName*, baseFilename*, defaultDirectory*: string
    languages*, messages*, permissions*, types*, components*, tasks*: int
    directories*, files*, dataEntries*, icons*, iniEntries*, registryEntries*: int
    deleteEntries*, uninstallDeleteEntries*, runEntries*, uninstallRunEntries*: int
    entriesOffset*: int
  InnoSetupCompression* = enum
    iscStored = 0, iscZlib = 1, iscBzip2 = 2, iscLzma1 = 3, iscLzma2 = 4
  InnoSetupFileEntry* = object
    source*, destination*: string
    location*: int
    externalSize*: int64
    dontCopy*: bool
  InnoSetupDataEntry* = object
    firstSlice*, lastSlice*, chunkOffset*: int
    fileOffset*, fileSize*, chunkSize*: int64
    compressed*, encrypted*, callOptimized*: bool
    compression*: InnoSetupCompression
  InnoSetupManifest* = object
    version*: InnoSetupVersion
    counts*: InnoSetupHeaderCounts
    files*: seq[InnoSetupFileEntry]
    dataEntries*: seq[InnoSetupDataEntry]
    compression*: InnoSetupCompression
    slicesPerDisk*: int

type InnoReader = object
  data: seq[byte]
  position: int

proc take(reader: var InnoReader, length: int): seq[byte] =
  reader.data.requireRange(reader.position, length)
  result = reader.data[reader.position ..< reader.position + length]
  reader.position += length

proc u32(reader: var InnoReader): int =
  result = int(le32(reader.data, reader.position))
  reader.position += 4

proc skip(reader: var InnoReader, length: int) =
  reader.data.requireRange(reader.position, length)
  reader.position += length

proc u8(reader: var InnoReader): int =
  reader.data.requireRange(reader.position, 1)
  result = int(reader.data[reader.position]); inc reader.position

proc u16(reader: var InnoReader): int =
  reader.data.requireRange(reader.position, 2)
  result = int(reader.data[reader.position]) or
    (int(reader.data[reader.position + 1]) shl 8)
  reader.position += 2

proc u64(reader: var InnoReader): int64 =
  reader.data.requireRange(reader.position, 8)
  var value = 0'u64
  for index in 0 ..< 8:
    value = value or (uint64(reader.data[reader.position + index]) shl (index * 8))
  reader.position += 8
  if value > uint64(high(int64)):
    raise newException(ValueError, "oversized Inno Setup 64-bit field")
  int64(value)

proc binaryString(reader: var InnoReader): seq[byte] =
  let length = reader.u32()
  if length < 0 or length > 64 * 1024 * 1024:
    raise newException(ValueError, "invalid Inno Setup string length")
  reader.take(length)

proc utf16String(reader: var InnoReader): string =
  let encoded = reader.binaryString()
  if (encoded.len and 1) != 0:
    raise newException(ValueError, "odd-length Inno Setup Unicode string")
  var index = 0
  while index < encoded.len:
    let value = int(encoded[index]) or (int(encoded[index + 1]) shl 8)
    index += 2
    if value < 0x80:
      result.add char(value)
    elif value < 0x800:
      result.add char(0xc0 or (value shr 6))
      result.add char(0x80 or (value and 0x3f))
    elif value in 0xd800 .. 0xdbff:
      if index + 1 >= encoded.len:
        raise newException(ValueError, "truncated Inno Setup Unicode surrogate")
      let low = int(encoded[index]) or (int(encoded[index + 1]) shl 8)
      if low notin 0xdc00 .. 0xdfff:
        raise newException(ValueError, "invalid Inno Setup Unicode surrogate")
      index += 2
      let rune = 0x10000 + ((value - 0xd800) shl 10) + low - 0xdc00
      result.add char(0xf0 or (rune shr 18))
      result.add char(0x80 or ((rune shr 12) and 0x3f))
      result.add char(0x80 or ((rune shr 6) and 0x3f))
      result.add char(0x80 or (rune and 0x3f))
    elif value in 0xdc00 .. 0xdfff:
      raise newException(ValueError, "unpaired Inno Setup Unicode surrogate")
    else:
      result.add char(0xe0 or (value shr 12))
      result.add char(0x80 or ((value shr 6) and 0x3f))
      result.add char(0x80 or (value and 0x3f))

proc parseInnoSetupVersion*(marker: string): InnoSetupVersion =
  let opening = marker.find('(')
  if opening < 0:
    raise newException(ValueError, "invalid Inno Setup version marker")
  var values: seq[int]
  var current = 0
  var digits = false
  for index in opening + 1 ..< marker.len:
    let value = marker[index]
    if value in {'0' .. '9'}:
      current = current * 10 + ord(value) - ord('0')
      digits = true
    elif value == '.' and digits:
      values.add current; current = 0; digits = false
    else:
      if digits: values.add current
      break
  if values.len < 3:
    raise newException(ValueError, "invalid Inno Setup version number")
  result.major = values[0]; result.minor = values[1]; result.patch = values[2]
  if values.len > 3: result.revision = values[3]
  result.unicode = marker.contains("(u)") or marker.contains("(U)") or
    result.major >= 6

proc atLeast(version: InnoSetupVersion, major, minor, patch: int): bool =
  (version.major, version.minor, version.patch) >= (major, minor, patch)

proc parseInnoSetupHeaderCounts*(primary: sink seq[byte],
    version: InnoSetupVersion): InnoSetupHeaderCounts =
  ## Parses the common main-header prefix used by the supplied 5.5/5.6 Unicode
  ## corpus and leaves the reader positioned at the first language entry.
  if not version.unicode or version.major != 5 or version.minor notin [5, 6]:
    raise newException(ValueError, "unsupported Inno Setup header-table version")
  var reader = InnoReader(data: move(primary))
  var stringIndex = 0
  template text(): string =
    block:
      inc stringIndex
      try: reader.utf16String()
      except ValueError as error:
        raise newException(ValueError, "Inno Setup main-header string " &
          $stringIndex & ": " & error.msg)
  result.appName = text()
  discard text() # app_versioned_name
  discard text() # app_id
  discard text() # app_copyright
  discard text(); discard text() # publisher + URL
  discard text() # support phone
  discard text(); discard text(); discard text() # support/update/version
  result.defaultDirectory = text()
  discard text() # default group
  result.baseFilename = text()
  discard text() # uninstall files directory
  discard text(); discard text(); discard text() # uninstall name/icon, app mutex
  discard text(); discard text(); discard text() # default user/org/serial
  discard text(); discard text(); discard text(); discard text() # readme/contact/comments/modify
  discard text() # create uninstall registry key
  discard text() # uninstallable expression
  discard text() # close applications filter
  if version.atLeast(5, 5, 6): discard text() # setup mutex
  if version.atLeast(5, 6, 1):
    discard text(); discard text() # changes environment/associations
  discard reader.binaryString() # ANSI license text
  discard reader.binaryString() # ANSI info before
  discard reader.binaryString() # ANSI info after
  discard reader.binaryString() # compiled code bytecode
  result.languages = reader.u32(); result.messages = reader.u32()
  result.permissions = reader.u32(); result.types = reader.u32()
  result.components = reader.u32(); result.tasks = reader.u32()
  result.directories = reader.u32(); result.files = reader.u32()
  result.dataEntries = reader.u32(); result.icons = reader.u32()
  result.iniEntries = reader.u32(); result.registryEntries = reader.u32()
  result.deleteEntries = reader.u32()
  result.uninstallDeleteEntries = reader.u32()
  result.runEntries = reader.u32(); result.uninstallRunEntries = reader.u32()
  for value in [result.languages, result.messages, result.permissions,
      result.types, result.components, result.tasks, result.directories,
      result.files, result.dataEntries, result.icons, result.iniEntries,
      result.registryEntries, result.deleteEntries,
      result.uninstallDeleteEntries, result.runEntries,
      result.uninstallRunEntries]:
    if value < 0 or value > 1_000_000:
      raise newException(ValueError, "implausible Inno Setup entry count")
  result.entriesOffset = reader.position

proc skipString(reader: var InnoReader) = discard reader.binaryString()

proc skipWinVersionRange(reader: var InnoReader) = reader.skip(20)

proc skipMainHeaderTail(reader: var InnoReader, version: InnoSetupVersion,
    compression: var InnoSetupCompression, slicesPerDisk: var int) =
  reader.skipWinVersionRange()
  reader.skip(if version.atLeast(5, 5, 7): 8 else: 12) # wizard colours
  if version.atLeast(5, 5, 7): reader.skip(1) # image alpha format
  reader.skip(20 + 8) # SHA-1 password verifier and salt
  discard reader.u64() # extra disk space
  slicesPerDisk = reader.u32()
  reader.skip(1) # uninstall log mode
  reader.skip(1) # directory-exists warning
  reader.skip(1) # required privileges
  reader.skip(2) # language dialog and detection
  let storedCompression = reader.u8()
  if storedCompression notin 0 .. 4:
    raise newException(ValueError, "unknown Inno Setup compression method")
  compression = InnoSetupCompression(storedCompression)
  reader.skip(2) # allowed architectures and 64-bit-mode architectures
  reader.skip(2) # disable directory and program-group pages
  discard reader.u64() # uninstall display size
  # Six packed bytes cover the 5.5/5.6 header option sets. Neither set has
  # the special three-byte padding case.
  reader.skip(6)

proc skipLanguage(reader: var InnoReader, version: InnoSetupVersion) =
  for unused in 0 ..< 10: reader.skipString()
  reader.skip(4 + 4 * 4 + 1)

proc skipMessage(reader: var InnoReader) =
  reader.skipString(); reader.skipString(); reader.skip(4)

proc skipType(reader: var InnoReader) =
  for unused in 0 ..< 4: reader.skipString()
  reader.skipWinVersionRange(); reader.skip(1 + 1 + 8)

proc skipComponent(reader: var InnoReader) =
  for unused in 0 ..< 5: reader.skipString()
  reader.skip(8 + 4 + 1); reader.skipWinVersionRange()
  reader.skip(1 + 8)

proc skipTask(reader: var InnoReader) =
  for unused in 0 ..< 6: reader.skipString()
  reader.skip(4 + 1); reader.skipWinVersionRange(); reader.skip(1)

proc skipCondition(reader: var InnoReader) =
  for unused in 0 ..< 6: reader.skipString()

proc parseDirectory(reader: var InnoReader): string =
  result = reader.utf16String()
  reader.skipCondition()
  reader.skip(4); reader.skipWinVersionRange(); reader.skip(2 + 1)

proc parseFile(reader: var InnoReader): InnoSetupFileEntry =
  result.source = reader.utf16String()
  result.destination = reader.utf16String()
  reader.skipString() # install font name
  reader.skipString() # strong assembly name
  reader.skipCondition()
  reader.skipWinVersionRange()
  result.location = reader.u32()
  if uint64(result.location) == uint64(high(uint32)): result.location = -1
  discard reader.u32() # attributes
  result.externalSize = reader.u64()
  reader.skip(2) # permission
  # 32 file flags are stored as four bytes for these versions. DontCopy is
  # bit 19 in the canonical flag order.
  let flags = reader.u32()
  result.dontCopy = (flags and (1 shl 19)) != 0
  reader.skip(1) # file type

proc parseData(reader: var InnoReader, compression: InnoSetupCompression,
    version: InnoSetupVersion): InnoSetupDataEntry =
  result.firstSlice = reader.u32(); result.lastSlice = reader.u32()
  result.chunkOffset = reader.u32()
  result.fileOffset = reader.u64(); result.fileSize = reader.u64()
  result.chunkSize = reader.u64()
  reader.skip(20) # SHA-1
  reader.skip(8 + 8) # FILETIME and file version
  let flags = reader.u16()
  result.callOptimized = (flags and (1 shl 4)) != 0
  result.encrypted = (flags and (1 shl 6)) != 0
  result.compressed = (flags and (1 shl 7)) != 0
  result.compression = if result.compressed: compression else: iscStored

proc parseInnoSetupManifest*(headers: sink InnoSetupHeaderStreams,
    marker: string): InnoSetupManifest =
  result.version = parseInnoSetupVersion(marker)
  result.counts = parseInnoSetupHeaderCounts(headers.primary, result.version)
  var primary = InnoReader(data: move(headers.primary),
    position: result.counts.entriesOffset)
  primary.skipMainHeaderTail(result.version, result.compression,
    result.slicesPerDisk)
  for unused in 0 ..< result.counts.languages: primary.skipLanguage(result.version)
  for unused in 0 ..< result.counts.messages: primary.skipMessage()
  for unused in 0 ..< result.counts.permissions: primary.skipString()
  for unused in 0 ..< result.counts.types: primary.skipType()
  for unused in 0 ..< result.counts.components: primary.skipComponent()
  for unused in 0 ..< result.counts.tasks: primary.skipTask()
  for unused in 0 ..< result.counts.directories: discard primary.parseDirectory()
  for unused in 0 ..< result.counts.files: result.files.add primary.parseFile()
  var secondary = InnoReader(data: move(headers.secondary))
  for unused in 0 ..< result.counts.dataEntries:
    result.dataEntries.add secondary.parseData(result.compression, result.version)
  for file in result.files:
    if file.location >= result.dataEntries.len:
      raise newException(ValueError, "Inno Setup file references an invalid data entry")

proc decodeExecutableFilter(data: var seq[byte]) =
  ## Reverses the 5.3.9+ x86 CALL/JMP transform used by the supplied corpus.
  var offset = 0
  while offset < data.len:
    let opcode = data[offset]
    inc offset
    if opcode notin [0xe8'u8, 0xe9'u8] or
        0x10000 - ((offset - 1) mod 0x10000) < 5:
      continue
    if offset > data.len - 4: break
    if data[offset + 3] in [0'u8, 0xff'u8]:
      var relative = uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
        (uint32(data[offset + 2]) shl 16)
      relative = (relative - uint32((offset + 4) and 0xffffff)) and 0xffffff
      data[offset] = byte(relative)
      data[offset + 1] = byte(relative shr 8)
      data[offset + 2] = byte(relative shr 16)
      if (relative and 0x800000) != 0: data[offset + 3] = not data[offset + 3]
    offset += 4

proc decodeInnoSetupChunk*(source: VextByteSource, sourceOffset: int,
    entry: InnoSetupDataEntry, maximumOutput: int): seq[byte] =
  if entry.encrypted:
    raise newException(ValueError, "encrypted Inno Setup chunks are not supported")
  if entry.chunkSize < 0 or entry.chunkSize > int64(high(int)):
    raise newException(ValueError, "oversized Inno Setup chunk")
  let encoded = source.readAt(sourceOffset + entry.chunkOffset,
    4 + int(entry.chunkSize))
  if encoded.len < 4 or encoded[0] != byte('z') or encoded[1] != byte('l') or
      encoded[2] != byte('b') or encoded[3] != 0x1a:
    raise newException(ValueError, "invalid Inno Setup data-chunk signature")
  case entry.compression
  of iscStored:
    result = encoded[4 .. ^1]
    if result.len > maximumOutput:
      raise newException(ValueError, "Inno Setup chunk exceeds its output limit")
  of iscLzma1:
    if encoded.len < 10:
      raise newException(ValueError, "truncated Inno Setup LZMA1 chunk")
    let property = int(encoded[4])
    if property >= 9 * 5 * 5:
      raise newException(ValueError, "invalid Inno Setup LZMA1 properties")
    let properties = RawLzmaProperties(lc: property mod 9,
      lp: (property div 9) mod 5, pb: property div (9 * 5),
      dictionarySize: int(le32(encoded, 5)))
    result = decodeRawLzma1(encoded[9 .. ^1], properties, maximumOutput)
  of iscLzma2:
    if encoded.len < 6 or encoded[4] > 40:
      raise newException(ValueError, "invalid Inno Setup LZMA2 properties")
    let property = int(encoded[4])
    let dictionarySize = if property == 40: int(high(int32))
      else: (2 or (property and 1)) shl (property div 2 + 11)
    result = decodeRawLzma2(encoded.toOpenArray(5, encoded.high),
      dictionarySize, maximumOutput)
  of iscZlib, iscBzip2:
    raise newException(ValueError, "this Inno Setup chunk compression is not yet supported")

proc extractInnoSetupFile*(chunk: openArray[byte], file: InnoSetupFileEntry,
    entry: InnoSetupDataEntry): seq[byte] =
  if entry.fileOffset < 0 or entry.fileSize < 0 or
      entry.fileOffset > int64(chunk.len) - entry.fileSize:
    raise newException(ValueError, "Inno Setup file lies outside its decoded chunk")
  result = newSeq[byte](int(entry.fileSize))
  for index in 0 ..< result.len:
    result[index] = chunk[int(entry.fileOffset) + index]
  if entry.callOptimized: result.decodeExecutableFilter()

const loaderMagics = [
  "rDlPtS02\x87eVx", "rDlPtS04\x87eVx", "rDlPtS05\x87eVx",
  "rDlPtS06\x87eVx", "rDlPtS07\x87eVx",
  "rDlPtS\xcd\xe6\xd7{\x0b*", "nS5W7dT\x83\xaa\x1b\x0fj"]

proc requireRange(data: openArray[byte], offset, length: int) =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "Inno Setup structure is outside the executable")

proc le16(data: openArray[byte], offset: int): int =
  data.requireRange(offset, 2)
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): uint32 =
  data.requireRange(offset, 4)
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc crc32(data: openArray[byte]): uint32 =
  result = high(uint32)
  for value in data:
    result = result xor uint32(value)
    for unused in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = not result

proc matches(data: openArray[byte], offset: int, value: string): bool =
  if offset < 0 or value.len > data.len - offset: return false
  for index, character in value:
    if data[offset + index] != byte(character): return false
  true

proc rvaToOffset(data: openArray[byte], peOffset, sectionCount,
    optionalSize: int, rva: uint32): int =
  let sections = peOffset + 24 + optionalSize
  data.requireRange(sections, sectionCount * 40)
  for index in 0 ..< sectionCount:
    let item = sections + index * 40
    let virtualSize = le32(data, item + 8)
    let virtualAddress = le32(data, item + 12)
    let rawSize = le32(data, item + 16)
    let rawOffset = le32(data, item + 20)
    let extent = max(virtualSize, rawSize)
    if rva >= virtualAddress and uint64(rva - virtualAddress) < uint64(extent):
      let delta = rva - virtualAddress
      if delta >= rawSize: break
      let candidate = uint64(rawOffset) + uint64(delta)
      if candidate > uint64(data.len): break
      return int(candidate)
  raise newException(ValueError, "Inno Setup PE resource address is not file-backed")

proc resourceChild(data: openArray[byte], root, directory: int,
    wantedId: int): int =
  data.requireRange(directory, 16)
  let named = le16(data, directory + 12)
  let ids = le16(data, directory + 14)
  if named > 4096 or ids > 4096:
    raise newException(ValueError, "invalid PE resource directory count")
  data.requireRange(directory + 16, (named + ids) * 8)
  for index in named ..< named + ids:
    let entry = directory + 16 + index * 8
    let identifier = le32(data, entry)
    if (identifier and 0x80000000'u32) == 0 and int(identifier) == wantedId:
      let target = le32(data, entry + 4)
      if (target and 0x80000000'u32) == 0:
        raise newException(ValueError, "PE resource level unexpectedly contains data")
      let relative = int(target and 0x7fffffff'u32)
      if relative > data.len - root:
        raise newException(ValueError, "invalid PE resource directory offset")
      return root + relative
  raise newException(ValueError, "Inno Setup PE resource was not found")

proc firstResourceData(data: openArray[byte], root, directory: int): int =
  data.requireRange(directory, 24)
  let count = le16(data, directory + 12) + le16(data, directory + 14)
  if count < 1 or count > 4096:
    raise newException(ValueError, "invalid PE language resource directory")
  let target = le32(data, directory + 20)
  if (target and 0x80000000'u32) != 0:
    raise newException(ValueError, "PE language resource does not contain data")
  let relative = int(target)
  if relative > data.len - root:
    raise newException(ValueError, "invalid PE resource data offset")
  root + relative

proc findModernLoader(data: openArray[byte]): int =
  if data.len < 0x40 or data[0] != byte('M') or data[1] != byte('Z'):
    raise newException(ValueError, "not a PE executable")
  let peOffset = int(le32(data, 0x3c))
  data.requireRange(peOffset, 24)
  if not data.matches(peOffset, "PE\0\0"):
    raise newException(ValueError, "not a PE executable")
  let sectionCount = le16(data, peOffset + 6)
  let optionalSize = le16(data, peOffset + 20)
  data.requireRange(peOffset + 24, optionalSize)
  let optionalMagic = le16(data, peOffset + 24)
  let directories = case optionalMagic
    of 0x10b: peOffset + 24 + 96
    of 0x20b: peOffset + 24 + 112
    else: raise newException(ValueError, "unsupported PE optional header")
  if directories + 24 > peOffset + 24 + optionalSize:
    raise newException(ValueError, "PE optional header has no resource directory")
  let resourceRva = le32(data, directories + 16)
  let resourceSize = le32(data, directories + 20)
  if resourceRva == 0 or resourceSize < 16:
    raise newException(ValueError, "PE executable has no resources")
  let root = rvaToOffset(data, peOffset, sectionCount, optionalSize, resourceRva)
  let typeDirectory = resourceChild(data, root, root, 10) # RT_RCDATA
  let nameDirectory = resourceChild(data, root, typeDirectory, 11111)
  let dataEntry = firstResourceData(data, root, nameDirectory)
  data.requireRange(dataEntry, 16)
  let payloadRva = le32(data, dataEntry)
  let payloadSize = int(le32(data, dataEntry + 4))
  result = rvaToOffset(data, peOffset, sectionCount, optionalSize, payloadRva)
  data.requireRange(result, payloadSize)

proc loaderMagicIndex(data: openArray[byte], offset: int): int =
  for index, magic in loaderMagics:
    if data.matches(offset, magic): return index
  -1

proc setupVersionAt(data: openArray[byte], offset: int): string =
  data.requireRange(offset, 12)
  var length = min(64, data.len - offset)
  for index in 0 ..< length:
    if data[offset + index] == 0:
      length = index
      break
  for index in 0 ..< length:
    let value = data[offset + index]
    if value < 0x20 or value > 0x7e:
      raise newException(ValueError, "invalid Inno Setup data version")
    result.add char(value)
  if not (result.startsWith("Inno Setup Setup Data (") or
      result.startsWith("My Inno Setup Extensions Setup Data (") or
      result.startsWith("i1.2.10--")):
    raise newException(ValueError, "Inno Setup data version marker was not found")

proc setupHeaderLength(data: openArray[byte], offset: int,
    version: string, modernBlocks: bool): int =
  ## Version 4.0.9 and later store two independently framed header streams
  ## after the fixed 64-byte version marker. Each stream starts with a CRC32,
  ## a stored length, and a compression byte. The stored length includes the
  ## per-4096-byte checksummed subblocks consumed by innoextract's block reader.
  if not modernBlocks or not version.startsWith("Inno Setup Setup Data ("):
    return data.len - offset
  var cursor = offset + 64
  data.requireRange(offset, 64)
  for unused in 0 ..< 2:
    data.requireRange(cursor, 9)
    let storedLength = uint64(le32(data, cursor + 4))
    if storedLength > uint64(data.len - cursor - 9):
      raise newException(ValueError, "truncated Inno Setup header block")
    cursor += 9 + int(storedLength)
  cursor - offset

proc parseInnoSetup*(data: openArray[byte]): InnoSetupInstaller =
  if data.len < 64:
    raise newException(ValueError, "Inno Setup executable is too short")
  var loader = -1
  if le32(data, 0x30) == 0x6f6e6e49'u32:
    let pointer = le32(data, 0x34)
    if pointer != not le32(data, 0x38):
      raise newException(ValueError, "invalid Inno Setup loader pointer checksum")
    if uint64(pointer) > uint64(data.high):
      raise newException(ValueError, "invalid Inno Setup loader pointer")
    loader = int(pointer)
  else:
    loader = findModernLoader(data)
    result.loaderInPeResource = true
  let magicIndex = loaderMagicIndex(data, loader)
  if magicIndex < 0:
    raise newException(ValueError, "unknown Inno Setup loader signature")
  result.loaderOffset = loader
  result.loaderVersion = ["1.2.10", "4.0.0", "4.0.3", "4.0.10",
    "4.1.6", "5.1.5", "5.1.5-alternate"][magicIndex]
  var cursor = loader + 12
  if magicIndex >= 5: cursor += 4 # loader revision
  cursor += 4 # reserved/unknown field covered by the loader checksum
  result.embeddedExeOffset = int(le32(data, cursor)); cursor += 4
  if magicIndex < 4:
    result.embeddedExeCompressedSize = int(le32(data, cursor)); cursor += 4
  result.embeddedExeUncompressedSize = int(le32(data, cursor)); cursor += 4
  cursor += 4 # embedded executable checksum
  if magicIndex == 0: cursor += 4 # message offset
  result.headerOffset = int(le32(data, cursor)); cursor += 4
  result.dataOffset = int(le32(data, cursor)); cursor += 4
  if magicIndex >= 3: cursor += 4 # loader-header CRC32
  result.loaderLength = cursor - loader
  data.requireRange(loader, result.loaderLength)
  if result.headerOffset < 0 or result.headerOffset >= data.len:
    raise newException(ValueError, "invalid Inno Setup header offset")
  if result.dataOffset < 0 or result.dataOffset > data.len:
    raise newException(ValueError, "invalid Inno Setup data offset")
  if result.embeddedExeOffset < 0 or result.embeddedExeOffset > data.len:
    raise newException(ValueError, "invalid embedded setup executable offset")
  result.setupVersion = setupVersionAt(data, result.headerOffset)
  result.headerLength = setupHeaderLength(data, result.headerOffset,
    result.setupVersion, magicIndex >= 3)

proc isInnoSetup*(data: openArray[byte]): bool =
  try:
    discard parseInnoSetup(data)
    true
  except ValueError:
    false

proc indexInnoSetup*(source: VextByteSource): InnoSetupInstaller =
  ## Indexes modern installers through bounded random-access reads.
  if source.isNil or source.length < 64:
    raise newException(ValueError, "Inno Setup executable is too short")
  let bootstrap = source.readAt(0, min(source.length, 1024 * 1024))
  let loader = findModernLoader(bootstrap)
  let magicIndex = loaderMagicIndex(bootstrap, loader)
  if magicIndex < 5:
    raise newException(ValueError,
      "source-backed Inno inspection requires a 5.1.5 or later PE loader")
  result.loaderOffset = loader
  result.loaderInPeResource = true
  result.loaderVersion = if magicIndex == 5: "5.1.5" else: "5.1.5-alternate"
  var cursor = loader + 20
  result.embeddedExeOffset = int(le32(bootstrap, cursor)); cursor += 4
  result.embeddedExeUncompressedSize = int(le32(bootstrap, cursor)); cursor += 4
  cursor += 4
  result.headerOffset = int(le32(bootstrap, cursor)); cursor += 4
  result.dataOffset = int(le32(bootstrap, cursor)); cursor += 8
  result.loaderLength = cursor - loader
  if result.headerOffset < 0 or result.headerOffset > source.length - 64 or
      result.dataOffset < 0 or result.dataOffset > source.length:
    raise newException(ValueError, "invalid Inno Setup source offsets")
  let marker = source.readAt(result.headerOffset, 64)
  result.setupVersion = setupVersionAt(marker, 0)
  var blockCursor = result.headerOffset + 64
  for unused in 0 ..< 2:
    let header = source.readAt(blockCursor, 9)
    let storedLength = uint64(le32(header, 4))
    if storedLength > uint64(source.length - blockCursor - 9):
      raise newException(ValueError, "truncated Inno Setup header block")
    blockCursor += 9 + int(storedLength)
  result.headerLength = blockCursor - result.headerOffset

proc decodeHeaderBlock(data: openArray[byte], cursor: var int,
    maximumOutput: int): seq[byte] =
  data.requireRange(cursor, 9)
  let expectedHeaderCrc = le32(data, cursor)
  let storedLength = int(le32(data, cursor + 4))
  let compressed = data[cursor + 8] != 0
  if crc32(data.toOpenArray(cursor + 4, cursor + 8)) != expectedHeaderCrc:
    raise newException(ValueError, "Inno Setup header-block framing CRC32 mismatch")
  cursor += 9
  data.requireRange(cursor, storedLength)
  let finish = cursor + storedLength
  var encoded: seq[byte]
  while cursor < finish:
    data.requireRange(cursor, 4)
    let expectedChunkCrc = le32(data, cursor)
    cursor += 4
    let amount = min(4096, finish - cursor)
    if amount == 0 or crc32(data.toOpenArray(cursor, cursor + amount - 1)) !=
        expectedChunkCrc:
      raise newException(ValueError, "Inno Setup header subblock CRC32 mismatch")
    encoded.add data.toOpenArray(cursor, cursor + amount - 1)
    cursor += amount
  if not compressed:
    if encoded.len > maximumOutput:
      raise newException(ValueError, "Inno Setup header exceeds its output limit")
    return move(encoded)
  if encoded.len < 6:
    raise newException(ValueError, "truncated Inno Setup LZMA header stream")
  let property = int(encoded[0])
  if property >= 9 * 5 * 5:
    raise newException(ValueError, "invalid Inno Setup LZMA1 properties")
  let properties = RawLzmaProperties(lc: property mod 9,
    lp: (property div 9) mod 5, pb: property div (9 * 5),
    dictionarySize: int(le32(encoded, 1)))
  decodeRawLzma1(encoded[5 .. ^1], properties, maximumOutput)

proc decodeInnoSetupHeaders*(source: VextByteSource,
    installer: InnoSetupInstaller,
    maximumOutput = 64 * 1024 * 1024): InnoSetupHeaderStreams =
  ## Materializes only the compact encoded header region and validates both
  ## framing layers before LZMA expansion.
  if maximumOutput <= 0:
    raise newException(ValueError, "invalid Inno Setup header output limit")
  let data = source.readAt(installer.headerOffset, installer.headerLength)
  var cursor = 64
  result.primary = decodeHeaderBlock(data, cursor, maximumOutput)
  result.secondary = decodeHeaderBlock(data, cursor, maximumOutput)
  if cursor != data.len:
    raise newException(ValueError, "trailing bytes after Inno Setup headers")

proc hasInnoSetupExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".exe")
