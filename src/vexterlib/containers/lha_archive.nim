## Level-0 LHA/LZH archive parsing and LH0/LH5 expansion.

import std/[strutils, unicode]
import ../byte_sources

const
  LhaArchiveTypeId* = "archive.lha"
  LhaDirectoryTypeId* = "archive.lha-directory"
  LhaFileTypeId* = "archive.lha-file"
  LhaMaximumNameCharacters* = 255

type
  LhaEntry* = object
    name*: string
    segments*: seq[string]
    isDirectory*: bool
    compressionMethod*: string
    compressedSize*: int
    uncompressedSize*: int
    payloadOffset*: int
    expectedCrc*: uint16
    data*: seq[byte]

  LhaArchive* = object
    entries*: seq[LhaEntry]

  BitReader = object
    data: seq[byte]
    bitOffset: int

  HuffmanTree = object
    nodes: seq[int]

proc leWord(data: openArray[byte], offset: int): uint16 {.inline.} =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc crc16(data: openArray[byte]): uint16 =
  for value in data:
    result = result xor uint16(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xa001'u16 else: 0'u16)

proc readBits(reader: var BitReader, count: int): int =
  if count < 0 or reader.bitOffset + count > reader.data.len * 8:
    raise newException(ValueError, "truncated LHA LH5 bitstream")
  for bit in 0 ..< count:
    result = (result shl 1) or
      int((reader.data[reader.bitOffset shr 3] shr
        (7 - (reader.bitOffset and 7))) and 1)
    inc reader.bitOffset

proc setSingle(tree: var HuffmanTree, value: int) =
  tree.nodes = @[-value - 1]

proc buildTree(lengths: openArray[int], count, capacity: int): HuffmanTree =
  result.nodes = newSeq[int](capacity)
  var nextEntry = 0
  var allocated = 1
  var codeLength = 0
  while true:
    let newNodes = (allocated - nextEntry) * 2
    if allocated + newNodes > capacity:
      raise newException(ValueError, "invalid LHA LH5 Huffman tree")
    let endOffset = allocated
    while nextEntry < endOffset:
      result.nodes[nextEntry] = allocated
      allocated += 2
      inc nextEntry
    inc codeLength
    var remaining = false
    for code in 0 ..< count:
      if lengths[code] == codeLength:
        if nextEntry >= allocated:
          raise newException(ValueError, "oversubscribed LHA LH5 Huffman tree")
        result.nodes[nextEntry] = -code - 1
        inc nextEntry
      elif lengths[code] > codeLength:
        remaining = true
    if not remaining: break

proc read(tree: HuffmanTree, reader: var BitReader): int =
  if tree.nodes.len == 0:
    raise newException(ValueError, "missing LHA LH5 Huffman tree")
  var node = tree.nodes[0]
  while node >= 0:
    let branch = node + reader.readBits(1)
    if branch < 0 or branch >= tree.nodes.len:
      raise newException(ValueError, "invalid LHA LH5 Huffman code")
    node = tree.nodes[branch]
  -node - 1

proc readLength(reader: var BitReader): int =
  result = reader.readBits(3)
  if result == 7:
    while reader.readBits(1) != 0: inc result

proc readTempTable(reader: var BitReader): HuffmanTree =
  const maximum = 20
  let count = reader.readBits(5)
  if count == 0:
    result.setSingle(reader.readBits(5))
    return
  if count > maximum:
    raise newException(ValueError, "invalid LHA LH5 temporary table length")
  var lengths = newSeq[int](maximum)
  var index = 0
  while index < count:
    lengths[index] = reader.readLength()
    if index == 2:
      let skipped = reader.readBits(2)
      for unused in 0 ..< skipped:
        inc index
        if index >= count:
          raise newException(ValueError, "invalid LHA LH5 temporary table skip")
    inc index
  result = buildTree(lengths, count, maximum * 2)

proc readCodeTable(reader: var BitReader,
    temporary: HuffmanTree): HuffmanTree =
  const maximum = 510
  let count = reader.readBits(9)
  if count == 0:
    result.setSingle(reader.readBits(9))
    return
  if count > maximum:
    raise newException(ValueError, "invalid LHA LH5 code table length")
  var lengths = newSeq[int](maximum)
  var index = 0
  while index < count:
    let code = temporary.read(reader)
    if code <= 2:
      let skipped = case code
        of 0: 1
        of 1: reader.readBits(4) + 3
        else: reader.readBits(9) + 20
      if index + skipped > count:
        raise newException(ValueError, "invalid LHA LH5 code table skip")
      index += skipped
    else:
      lengths[index] = code - 2
      inc index
  result = buildTree(lengths, count, maximum * 2)

proc readOffsetTable(reader: var BitReader): HuffmanTree =
  # jslha uses fourteen history bits for its LH5 decoder. Authentic Aminet
  # controls confirm this accepts ordinary LH5 streams; the extra slot is not
  # emitted by those streams.
  const historyBits = 14
  let count = reader.readBits(4)
  if count == 0:
    result.setSingle(reader.readBits(4))
    return
  if count > historyBits:
    raise newException(ValueError, "invalid LHA LH5 offset table length")
  var lengths = newSeq[int](historyBits)
  for index in 0 ..< count:
    lengths[index] = reader.readLength()
  result = buildTree(lengths, count, 40)

proc decodeLh5(source: openArray[byte], expectedSize: int): seq[byte] =
  var reader = BitReader(data: @source)
  result = newSeqOfCap[byte](expectedSize)
  var history = newSeq[byte](1 shl 14)
  var historyPosition = 0
  while result.len < expectedSize:
    let blockCount = reader.readBits(16)
    if blockCount == 0:
      raise newException(ValueError, "invalid empty LHA LH5 block")
    let temporary = reader.readTempTable()
    let codes = reader.readCodeTable(temporary)
    let offsets = reader.readOffsetTable()
    for item in 0 ..< blockCount:
      if result.len >= expectedSize:
        raise newException(ValueError, "LHA LH5 block exceeds declared size")
      let code = codes.read(reader)
      if code < 256:
        result.add byte(code)
        history[historyPosition] = byte(code)
        historyPosition = (historyPosition + 1) and (history.high)
      else:
        let count = code - 253
        let bits = offsets.read(reader)
        let offset = if bits == 0: 0
          elif bits == 1: 1
          else: reader.readBits(bits - 1) + (1 shl (bits - 1))
        var sourcePosition = (historyPosition + history.len - offset - 1) and
          history.high
        if result.len + count > expectedSize:
          raise newException(ValueError, "LHA LH5 match exceeds declared size")
        for copied in 0 ..< count:
          let value = history[sourcePosition]
          sourcePosition = (sourcePosition + 1) and history.high
          result.add value
          history[historyPosition] = value
          historyPosition = (historyPosition + 1) and history.high

proc validatedSegments(name: string, directory: bool): seq[string] =
  var canonical = name.replace('\\', '/')
  if canonical.len == 0 or canonical[0] == '/':
    raise newException(ValueError, "invalid absolute or empty LHA entry name")
  if directory and canonical.endsWith('/'):
    canonical.setLen(canonical.len - 1)
  for segment in canonical.split('/'):
    if segment.len == 0 or segment in [".", ".."]:
      raise newException(ValueError, "cyclic or ambiguous LHA entry path: " & name)
    result.add segment

proc validateLhaStructure(data: openArray[byte]): int =
  ## Validates level-0 record framing without requiring a supported member
  ## codec. This lets frontends identify an LHA archive before decoding it.
  if data.len < 2:
    raise newException(ValueError, "LHA archive is too short")
  var offset = 0
  while offset < data.len and data[offset] != 0:
    let headerSize = int(data[offset])
    if headerSize < 22 or offset + headerSize + 2 > data.len:
      raise newException(ValueError, "invalid LHA level-0 header length")
    let level = int(data[offset + 20])
    if level notin [0, 1]:
      raise newException(ValueError, "unsupported LHA header level")
    var checksum = 0
    for index in offset + 2 .. offset + headerSize + 1:
      checksum = (checksum + int(data[index])) and 0xff
    if checksum != int(data[offset + 1]):
      raise newException(ValueError, "LHA header checksum does not match")
    if data[offset + 2] != byte('-') or data[offset + 6] != byte('-'):
      raise newException(ValueError, "invalid LHA compression method identifier")
    for index in offset + 2 .. offset + 6:
      if data[index] < 0x20 or data[index] > 0x7e:
        raise newException(ValueError, "invalid LHA compression method identifier")
    let nameLength = int(data[offset + 21])
    if (level == 0 and nameLength == 0) or
        24 + nameLength > headerSize + 2:
      raise newException(ValueError, "invalid LHA level-0 filename length")
    for index in 0 ..< nameLength:
      if data[offset + 22 + index] == 0:
        raise newException(ValueError, "NUL in LHA entry name")
    let declaredSize = uint64(leDword(data, offset + 7))
    var payloadOffset = offset + headerSize + 2
    var packedSize = declaredSize
    if level == 1:
      var extensionSize = int(leWord(data, offset + headerSize))
      while extensionSize != 0:
        if extensionSize < 3 or extensionSize > data.len - payloadOffset or
            uint64(extensionSize) > packedSize:
          raise newException(ValueError, "invalid LHA level-1 extended header")
        packedSize -= uint64(extensionSize)
        let nextSize = int(leWord(data,
          payloadOffset + extensionSize - 2))
        payloadOffset += extensionSize
        extensionSize = nextSize
    if packedSize > uint64(data.len - payloadOffset):
      raise newException(ValueError, "truncated LHA member data")
    offset = payloadOffset + int(packedSize)
    inc result
  if offset >= data.len or data[offset] != 0:
    raise newException(ValueError, "LHA end marker was not found")
  for index in offset + 1 ..< data.len:
    if data[index] != 0:
      raise newException(ValueError, "trailing data after LHA end marker")
  if result == 0:
    raise newException(ValueError, "LHA archive contains no entries")

proc isLhaArchiveStructure*(data: openArray[byte]): bool =
  try:
    discard validateLhaStructure(data)
    true
  except ValueError:
    false

proc parseLhaArchive*(data: openArray[byte]): LhaArchive =
  if data.len < 2:
    raise newException(ValueError, "LHA archive is too short")
  var offset = 0
  var names: seq[string]
  while offset < data.len and data[offset] != 0:
    let headerSize = int(data[offset])
    if headerSize < 22 or offset + headerSize + 2 > data.len:
      raise newException(ValueError, "invalid LHA level-0 header length")
    let level = int(data[offset + 20])
    if level notin [0, 1]:
      raise newException(ValueError, "unsupported LHA header level")
    var checksum = 0
    for index in offset + 2 .. offset + headerSize + 1:
      checksum = (checksum + int(data[index])) and 0xff
    if checksum != int(data[offset + 1]):
      raise newException(ValueError, "LHA header checksum does not match")
    var compressionMethod: string
    for index in offset + 2 .. offset + 6:
      compressionMethod.add char(data[index])
    if compressionMethod notin ["-lh0-", "-lh5-", "-lhd-"]:
      raise newException(ValueError,
        "unsupported LHA compression method: " & compressionMethod)
    let declaredSize64 = uint64(leDword(data, offset + 7))
    let uncompressedSize64 = uint64(leDword(data, offset + 11))
    if declaredSize64 > uint64(high(int)) or
        uncompressedSize64 > uint64(high(int)):
      raise newException(ValueError, "LHA member is too large")
    var compressedSize = int(declaredSize64)
    let uncompressedSize = int(uncompressedSize64)
    let nameLength = int(data[offset + 21])
    if (level == 0 and nameLength == 0) or
        24 + nameLength > headerSize + 2:
      raise newException(ValueError, "invalid LHA level-0 filename length")
    var name: string
    for index in 0 ..< nameLength:
      let value = data[offset + 22 + index]
      if value == 0: raise newException(ValueError, "NUL in LHA entry name")
      name.add char(value)
    if runeLen(name) > LhaMaximumNameCharacters:
      raise newException(ValueError, "LHA entry name exceeds 255 characters")
    var payloadOffset = offset + headerSize + 2
    if level == 1:
      var extensionSize = int(leWord(data, offset + headerSize))
      var directoryPrefix = ""
      while extensionSize != 0:
        if extensionSize < 3 or extensionSize > data.len - payloadOffset or
            extensionSize > compressedSize:
          raise newException(ValueError, "invalid LHA level-1 extended header")
        let extensionType = data[payloadOffset]
        let fieldLength = extensionSize - 3
        if extensionType in [1'u8, 2'u8]:
          var field = ""
          for index in 0 ..< fieldLength:
            let value = data[payloadOffset + 1 + index]
            if value == 0: field.add '/'
            else: field.add char(value)
          if extensionType == 1: name = field
          else: directoryPrefix = field
        let nextSize = int(leWord(data,
          payloadOffset + extensionSize - 2))
        compressedSize -= extensionSize
        payloadOffset += extensionSize
        extensionSize = nextSize
      if directoryPrefix.len > 0:
        name = directoryPrefix & name
    if name.len == 0:
      raise newException(ValueError, "empty LHA entry name")
    let directory = compressionMethod == "-lhd-" or
      name.endsWith("/") or name.endsWith("\\")
    let segments = validatedSegments(name, directory)
    let canonical = segments.join("/")
    if canonical in names:
      raise newException(ValueError, "duplicate LHA entry path: " & canonical)
    names.add canonical
    let expectedCrc = leWord(data, offset + 22 + nameLength)
    if compressedSize > data.len - payloadOffset:
      raise newException(ValueError, "truncated LHA member data")
    var payload: seq[byte]
    if directory:
      if compressedSize != 0 or uncompressedSize != 0:
        raise newException(ValueError, "LHA directory entry contains file data")
    else:
      var packed: seq[byte]
      if compressedSize > 0:
        packed.add data.toOpenArray(payloadOffset,
          payloadOffset + compressedSize - 1)
      if compressionMethod == "-lh0-":
        payload = @packed
        if payload.len != uncompressedSize:
          raise newException(ValueError, "invalid stored LHA entry size")
      else:
        payload = decodeLh5(packed, uncompressedSize)
      if crc16(payload) != expectedCrc:
        raise newException(ValueError, "LHA entry CRC-16 does not match: " & canonical)
    result.entries.add LhaEntry(name: canonical, segments: segments,
      isDirectory: directory, compressionMethod: compressionMethod,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize, data: payload)
    offset = payloadOffset + compressedSize
  if offset >= data.len or data[offset] != 0:
    raise newException(ValueError, "LHA end marker was not found")
  for index in offset + 1 ..< data.len:
    if data[index] != 0:
      raise newException(ValueError, "trailing data after LHA end marker")
  if result.entries.len == 0:
    raise newException(ValueError, "LHA archive contains no entries")

proc isLhaArchive*(data: openArray[byte]): bool =
  try:
    discard parseLhaArchive(data)
    true
  except ValueError:
    false

proc hasLhaExtension*(filename: string): bool =
  let lower = filename.toLowerAscii
  lower.endsWith(".lha") or lower.endsWith(".lzh")

proc indexLhaArchive*(source: VextByteSource): LhaArchive =
  ## Scans sequential LHA headers and retains member offsets without reading or
  ## decompressing their payloads.
  if source.isNil or source.length < 2:
    raise newException(ValueError, "LHA archive is too short")
  var offset = 0
  var names: seq[string]
  while offset < source.length:
    let first = source.readAt(offset, 1)[0]
    if first == 0: break
    let headerSize = int(first)
    if headerSize < 22 or offset + headerSize + 2 > source.length:
      raise newException(ValueError, "invalid LHA level-0 header length")
    let header = source.readAt(offset, headerSize + 2)
    let level = int(header[20])
    if level notin [0, 1]:
      raise newException(ValueError, "unsupported LHA header level")
    var checksum = 0
    for index in 2 .. headerSize + 1:
      checksum = (checksum + int(header[index])) and 0xff
    if checksum != int(header[1]):
      raise newException(ValueError, "LHA header checksum does not match")
    var compressionMethod: string
    for index in 2 .. 6: compressionMethod.add char(header[index])
    if compressionMethod notin ["-lh0-", "-lh5-", "-lhd-"]:
      raise newException(ValueError,
        "unsupported LHA compression method: " & compressionMethod)
    let declaredSize64 = uint64(leDword(header, 7))
    let uncompressedSize64 = uint64(leDword(header, 11))
    if declaredSize64 > uint64(high(int)) or
        uncompressedSize64 > uint64(high(int)):
      raise newException(ValueError, "LHA member is too large")
    var compressedSize = int(declaredSize64)
    let uncompressedSize = int(uncompressedSize64)
    let nameLength = int(header[21])
    if (level == 0 and nameLength == 0) or 24 + nameLength > header.len:
      raise newException(ValueError, "invalid LHA level-0 filename length")
    var name: string
    for index in 0 ..< nameLength:
      let value = header[22 + index]
      if value == 0: raise newException(ValueError, "NUL in LHA entry name")
      name.add char(value)
    var payloadOffset = offset + headerSize + 2
    if level == 1:
      var extensionSize = int(leWord(header, headerSize))
      var directoryPrefix = ""
      while extensionSize != 0:
        if extensionSize < 3 or extensionSize > source.length - payloadOffset or
            extensionSize > compressedSize:
          raise newException(ValueError, "invalid LHA level-1 extended header")
        let extension = source.readAt(payloadOffset, extensionSize)
        let extensionType = extension[0]
        let fieldLength = extensionSize - 3
        if extensionType in [1'u8, 2'u8]:
          var field = ""
          for index in 0 ..< fieldLength:
            let value = extension[1 + index]
            if value == 0: field.add '/' else: field.add char(value)
          if extensionType == 1: name = field else: directoryPrefix = field
        extensionSize = int(leWord(extension, extension.len - 2))
        compressedSize -= extension.len
        payloadOffset += extension.len
      if directoryPrefix.len > 0: name = directoryPrefix & name
    if name.len == 0:
      raise newException(ValueError, "empty LHA entry name")
    if runeLen(name) > LhaMaximumNameCharacters:
      raise newException(ValueError, "LHA entry name exceeds 255 characters")
    let directory = compressionMethod == "-lhd-" or
      name.endsWith("/") or name.endsWith("\\")
    let segments = validatedSegments(name, directory)
    let canonical = segments.join("/")
    if canonical in names:
      raise newException(ValueError, "duplicate LHA entry path: " & canonical)
    names.add canonical
    if compressedSize > source.length - payloadOffset:
      raise newException(ValueError, "truncated LHA member data")
    if directory and (compressedSize != 0 or uncompressedSize != 0):
      raise newException(ValueError, "LHA directory entry contains file data")
    result.entries.add LhaEntry(name: canonical, segments: segments,
      isDirectory: directory, compressionMethod: compressionMethod,
      compressedSize: compressedSize, uncompressedSize: uncompressedSize,
      payloadOffset: payloadOffset,
      expectedCrc: leWord(header, 22 + nameLength))
    offset = payloadOffset + compressedSize
  if offset >= source.length or source.readAt(offset, 1)[0] != 0:
    raise newException(ValueError, "LHA end marker was not found")
  inc offset
  while offset < source.length:
    let amount = min(64 * 1024, source.length - offset)
    for value in source.readAt(offset, amount):
      if value != 0:
        raise newException(ValueError, "trailing data after LHA end marker")
    offset += amount
  if result.entries.len == 0:
    raise newException(ValueError, "LHA archive contains no entries")

proc extractLhaEntry*(source: VextByteSource, entry: LhaEntry,
    maximumSize = high(int)): seq[byte] =
  if entry.isDirectory:
    raise newException(ValueError, "cannot extract an LHA directory")
  if entry.uncompressedSize > maximumSize:
    raise newException(ValueError,
      "LHA member exceeds the permitted materialization size: " & entry.name)
  let packed = source.readAt(entry.payloadOffset, entry.compressedSize)
  if entry.compressionMethod == "-lh0-":
    result = packed
    if result.len != entry.uncompressedSize:
      raise newException(ValueError, "invalid stored LHA entry size")
  elif entry.compressionMethod == "-lh5-":
    result = decodeLh5(packed, entry.uncompressedSize)
  else:
    raise newException(ValueError,
      "unsupported LHA compression method: " & entry.compressionMethod)
  if crc16(result) != entry.expectedCrc:
    raise newException(ValueError,
      "LHA entry CRC-16 does not match: " & entry.name)
