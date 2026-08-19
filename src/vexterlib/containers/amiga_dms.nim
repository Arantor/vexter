## Parsing and disk reconstruction for DMS archives.
##
## HEAVY1/HEAVY2, RLE, CRC, and track-state behavior are informed by the
## user-supplied public-domain xDMS source identified in THIRD_PARTY.md. The
## implementation here is an independent Nim expression of that behavior.

import std/[os, strutils]

const
  AmigaDmsTypeId* = "amiga.dms"
  AmigaDmsTrackTypeId* = "amiga.dms-track"
  AmigaDmsHeaderSize* = 56
  AmigaDmsTrackHeaderSize* = 20
  DmsEncryptedFlag* = 2'u32
  DmsHighDensityFlag* = 16'u32

type
  AmigaDmsCompression* = enum
    adcNone = 0
    adcSimple = 1
    adcQuick = 2
    adcMedium = 3
    adcDeep = 4
    adcHeavy1 = 5
    adcHeavy2 = 6
    adcHeavy3 = 7
    adcHeavy4 = 8
    adcHeavy5 = 9

  AmigaDmsTrack* = object
    number*: int
    packedLength*: int
    runtimePackedLength*: int
    unpackedLength*: int
    flags*: int
    compression*: AmigaDmsCompression
    unpackedCrc*: uint16
    packedCrc*: uint16
    headerCrc*: uint16
    data*: seq[byte]

  AmigaDmsArchive* = object
    headerKind*: string
    infoFlags*: uint32
    date*: uint32
    lowTrack*: int
    highTrack*: int
    packedSize*: uint32
    unpackedSize*: uint32
    osVersion*: uint16
    osRevision*: uint16
    machineCpu*: uint16
    cpuCoprocessor*: uint16
    machineType*: uint16
    disketteType2*: uint16
    cpuMhzHundredths*: uint16
    creationTime*: uint32
    creatorVersion*: uint16
    neededVersion*: uint16
    disketteType*: uint16
    compression*: AmigaDmsCompression
    headerCrc*: uint16
    tracks*: seq[AmigaDmsTrack]

  DmsBitReader = object
    data: seq[byte]
    bitPosition: int

  DmsHuffmanNode = object
    child: array[2, int]
    symbol: int

  DmsHuffmanTree = object
    constantSymbol: int
    nodes: seq[DmsHuffmanNode]

  DmsHeavyState = object
    text: seq[byte]
    textLocation: int
    lastDistance: int
    characterTree: DmsHuffmanTree
    positionTree: DmsHuffmanTree

proc beWord(data: openArray[byte], offset: int): uint16 {.inline.} =
  (uint16(data[offset]) shl 8) or uint16(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc compression(value: uint16, context: string): AmigaDmsCompression =
  if value > 9:
    raise newException(ValueError, "invalid DMS " & context & " compression mode")
  AmigaDmsCompression(value)

proc dmsCrc(data: openArray[byte]): uint16 =
  ## CRC-16/ARC as used by xDMS, initialized to zero.
  var crc = 0'u16
  for value in data:
    crc = crc xor uint16(value)
    for bit in 0 ..< 8:
      crc = if (crc and 1) != 0: (crc shr 1) xor 0xa001'u16 else: crc shr 1
  crc

proc dmsChecksum(data: openArray[byte]): uint16 =
  var sum = 0'u32
  for value in data: sum += uint32(value)
  uint16(sum and 0xffff)

proc readBits(reader: var DmsBitReader, count: int): int =
  if count < 0 or count > 24:
    raise newException(ValueError, "invalid DMS bit count")
  for unused in 0 ..< count:
    result = result shl 1
    let byteIndex = reader.bitPosition shr 3
    if byteIndex < reader.data.len:
      result = result or
        int((reader.data[byteIndex] shr (7 - (reader.bitPosition and 7))) and 1)
    inc reader.bitPosition

proc buildHuffman(lengths: openArray[byte]): DmsHuffmanTree =
  var maximum = 0
  for length in lengths:
    maximum = max(maximum, int(length))
  if maximum == 0:
    raise newException(ValueError, "empty DMS Huffman tree")
  var counts = newSeq[int](maximum + 1)
  for length in lengths:
    if length > 0: inc counts[int(length)]
  var nextCode = newSeq[int](maximum + 1)
  var code = 0
  for length in 1 .. maximum:
    code = (code + counts[length - 1]) shl 1
    nextCode[length] = code
  if code + counts[maximum] != (1 shl maximum):
    raise newException(ValueError, "invalid DMS Huffman tree")
  result.constantSymbol = -1
  result.nodes = @[DmsHuffmanNode(child: [-1, -1], symbol: -1)]
  for symbol, rawLength in lengths:
    let length = int(rawLength)
    if length == 0: continue
    let symbolCode = nextCode[length]
    inc nextCode[length]
    var node = 0
    for shift in countdown(length - 1, 0):
      let branch = (symbolCode shr shift) and 1
      if result.nodes[node].child[branch] < 0:
        result.nodes[node].child[branch] = result.nodes.len
        result.nodes.add DmsHuffmanNode(child: [-1, -1], symbol: -1)
      node = result.nodes[node].child[branch]
    if result.nodes[node].symbol >= 0:
      raise newException(ValueError, "duplicate DMS Huffman code")
    result.nodes[node].symbol = symbol

proc constantTree(symbol, symbolCount: int): DmsHuffmanTree =
  if symbol < 0 or symbol >= symbolCount:
    raise newException(ValueError, "invalid DMS constant Huffman symbol")
  DmsHuffmanTree(constantSymbol: symbol)

proc decodeSymbol(tree: DmsHuffmanTree, reader: var DmsBitReader): int =
  if tree.constantSymbol >= 0:
    return tree.constantSymbol
  var node = 0
  for depth in 1 .. 32:
    let branch = reader.readBits(1)
    node = tree.nodes[node].child[branch]
    if node < 0 or node >= tree.nodes.len:
      raise newException(ValueError, "invalid DMS Huffman code")
    if tree.nodes[node].symbol >= 0:
      return tree.nodes[node].symbol
  raise newException(ValueError, "overlong DMS Huffman code")

proc readCharacterTree(reader: var DmsBitReader): DmsHuffmanTree =
  const CharacterCount = 510
  let count = reader.readBits(9)
  if count == 0:
    return constantTree(reader.readBits(9), CharacterCount)
  if count > CharacterCount:
    raise newException(ValueError, "invalid DMS character-tree size")
  var lengths = newSeq[byte](CharacterCount)
  for index in 0 ..< count:
    lengths[index] = byte(reader.readBits(5))
  buildHuffman(lengths)

proc readPositionTree(reader: var DmsBitReader, symbolCount: int): DmsHuffmanTree =
  let count = reader.readBits(5)
  if count == 0:
    return constantTree(reader.readBits(5), symbolCount)
  if count > symbolCount:
    raise newException(ValueError, "invalid DMS position-tree size")
  var lengths = newSeq[byte](symbolCount)
  for index in 0 ..< count:
    lengths[index] = byte(reader.readBits(4))
  buildHuffman(lengths)

proc resetHeavy(state: var DmsHeavyState) =
  state.text = newSeq[byte](0x3fc8)
  state.textLocation = 0
  state.lastDistance = 0
  state.characterTree = DmsHuffmanTree(constantSymbol: -1)
  state.positionTree = DmsHuffmanTree(constantSymbol: -1)

proc unpackHeavy(data: seq[byte], expandedLength, flags: int,
    heavy2: bool, state: var DmsHeavyState): seq[byte] =
  let
    positionSymbols = if heavy2: 15 else: 14
    dictionaryMask = if heavy2: 0x1fff else: 0x0fff
  var reader = DmsBitReader(data: data)
  if (flags and 2) != 0:
    state.characterTree = readCharacterTree(reader)
    state.positionTree = readPositionTree(reader, positionSymbols)
  if state.characterTree.constantSymbol < 0 and state.characterTree.nodes.len == 0:
    raise newException(ValueError, "DMS HEAVY track has no character tree")
  if state.positionTree.constantSymbol < 0 and state.positionTree.nodes.len == 0:
    raise newException(ValueError, "DMS HEAVY track has no position tree")
  while result.len < expandedLength:
    let symbol = decodeSymbol(state.characterTree, reader)
    if symbol < 256:
      let value = byte(symbol)
      result.add value
      state.text[state.textLocation and dictionaryMask] = value
      state.textLocation = (state.textLocation + 1) and 0xffff
    else:
      var amount = symbol - 253
      let position = decodeSymbol(state.positionTree, reader)
      if position != positionSymbols - 1:
        if position == 0:
          state.lastDistance = 0
        else:
          let extraBits = position - 1
          state.lastDistance = (1 shl extraBits) or reader.readBits(extraBits)
      var source = (state.textLocation - state.lastDistance - 1) and 0xffff
      if amount > expandedLength - result.len:
        raise newException(ValueError, "DMS HEAVY match exceeds track length")
      while amount > 0:
        let value = state.text[source and dictionaryMask]
        result.add value
        state.text[state.textLocation and dictionaryMask] = value
        source = (source + 1) and 0xffff
        state.textLocation = (state.textLocation + 1) and 0xffff
        dec amount

proc unpackRle(data: openArray[byte], expandedLength: int): seq[byte] =
  var input = 0
  while result.len < expandedLength:
    if input >= data.len:
      raise newException(ValueError, "truncated DMS RLE stream")
    let value = data[input]
    inc input
    if value != 0x90:
      result.add value
      continue
    if input >= data.len:
      raise newException(ValueError, "truncated DMS RLE command")
    var amount = int(data[input])
    inc input
    if amount == 0:
      result.add 0x90'u8
      continue
    if input >= data.len:
      raise newException(ValueError, "truncated DMS RLE value")
    let repeated = data[input]
    inc input
    if amount == 0xff:
      if input + 2 > data.len:
        raise newException(ValueError, "truncated extended DMS RLE command")
      amount = (int(data[input]) shl 8) or int(data[input + 1])
      input += 2
    if amount > expandedLength - result.len:
      raise newException(ValueError, "DMS RLE run exceeds track length")
    for unused in 0 ..< amount: result.add repeated

proc parseAmigaDms*(data: openArray[byte]): AmigaDmsArchive =
  if data.len < AmigaDmsHeaderSize:
    raise newException(ValueError, "truncated DMS information header")
  if data[0] != byte('D') or data[1] != byte('M') or data[2] != byte('S') or
      data[3] != byte('!'):
    raise newException(ValueError, "invalid DMS identifier")
  # The structure sheet labels this longword as a header and lists ` PRO` and
  # `FILE`, but authentic DMS disk archives also store zero here.  Treat the
  # documented text values as descriptive metadata, not a second signature.
  if beDword(data, 4) == 0:
    result.headerKind = ""
  else:
    for index in 4 .. 7:
      if data[index] < 0x20 or data[index] > 0x7e:
        raise newException(ValueError, "invalid DMS header kind")
      result.headerKind.add char(data[index])
    if result.headerKind notin [" PRO", "FILE"]:
      raise newException(ValueError, "unsupported DMS header kind")
  result.infoFlags = beDword(data, 8)
  result.date = beDword(data, 12)
  result.lowTrack = int(beWord(data, 16))
  result.highTrack = int(beWord(data, 18))
  if result.lowTrack > result.highTrack:
    raise newException(ValueError, "invalid DMS track range")
  result.packedSize = beDword(data, 20)
  result.unpackedSize = beDword(data, 24)
  result.osVersion = beWord(data, 28)
  result.osRevision = beWord(data, 30)
  result.machineCpu = beWord(data, 32)
  result.cpuCoprocessor = beWord(data, 34)
  result.machineType = beWord(data, 36)
  result.disketteType2 = beWord(data, 38)
  result.cpuMhzHundredths = beWord(data, 40)
  result.creationTime = beDword(data, 42)
  result.creatorVersion = beWord(data, 46)
  result.neededVersion = beWord(data, 48)
  result.disketteType = beWord(data, 50)
  result.compression = compression(beWord(data, 52), "header")
  result.headerCrc = beWord(data, 54)
  if dmsCrc(data.toOpenArray(4, 53)) != result.headerCrc:
    raise newException(ValueError, "invalid DMS information-header CRC")

  var offset = AmigaDmsHeaderSize
  while offset < data.len:
    if data.len - offset < AmigaDmsTrackHeaderSize:
      raise newException(ValueError, "truncated DMS track header")
    if data[offset] != byte('T') or data[offset + 1] != byte('R'):
      raise newException(ValueError, "invalid DMS track identifier")
    let packedLength = int(beWord(data, offset + 6))
    if packedLength > data.len - offset - AmigaDmsTrackHeaderSize:
      raise newException(ValueError, "truncated DMS track payload")
    var payload: seq[byte]
    if packedLength > 0:
      payload.add data.toOpenArray(offset + AmigaDmsTrackHeaderSize,
        offset + AmigaDmsTrackHeaderSize + packedLength - 1)
    let track = AmigaDmsTrack(
      number: int(beWord(data, offset + 2)),
      packedLength: packedLength,
      runtimePackedLength: int(beWord(data, offset + 8)),
      unpackedLength: int(beWord(data, offset + 10)),
      flags: int(data[offset + 12]),
      compression: compression(uint16(data[offset + 13]), "track"),
      unpackedCrc: beWord(data, offset + 14),
      packedCrc: beWord(data, offset + 16),
      headerCrc: beWord(data, offset + 18),
      data: payload)
    if dmsCrc(data.toOpenArray(offset, offset + 17)) != track.headerCrc:
      raise newException(ValueError, "invalid DMS track-header CRC")
    if dmsCrc(track.data) != track.packedCrc:
      raise newException(ValueError, "invalid DMS packed-track CRC")
    if track.number < result.lowTrack or track.number > result.highTrack:
      raise newException(ValueError, "DMS track number is outside the declared range")
    result.tracks.add track
    offset += AmigaDmsTrackHeaderSize + packedLength
  if result.tracks.len == 0:
    raise newException(ValueError, "DMS archive contains no tracks")

proc unpackAmigaDms*(archive: AmigaDmsArchive): seq[byte] =
  if (archive.infoFlags and DmsEncryptedFlag) != 0:
    raise newException(ValueError, "encrypted DMS archives are unsupported")
  var expectedTrack = archive.lowTrack
  var heavyState: DmsHeavyState
  heavyState.resetHeavy()
  for track in archive.tracks:
    if track.number != expectedTrack:
      raise newException(ValueError, "DMS disk tracks are missing or out of order")
    var unpacked: seq[byte]
    case track.compression
    of adcNone:
      if track.packedLength != track.unpackedLength:
        raise newException(ValueError, "invalid uncompressed DMS track lengths")
      unpacked = track.data
    of adcSimple:
      unpacked = unpackRle(track.data, track.unpackedLength)
    of adcHeavy1, adcHeavy2:
      let intermediate = unpackHeavy(track.data, track.runtimePackedLength,
        track.flags, track.compression == adcHeavy2, heavyState)
      unpacked = if (track.flags and 4) != 0:
        unpackRle(intermediate, track.unpackedLength) else: intermediate
    else:
      raise newException(ValueError, "DMS compression mode " &
        $ord(track.compression) & " is not yet implemented")
    if unpacked.len != track.unpackedLength:
      raise newException(ValueError, "DMS track has an invalid unpacked length")
    if dmsChecksum(unpacked) != track.unpackedCrc:
      raise newException(ValueError, "invalid DMS unpacked-track checksum")
    result.add unpacked
    if (track.flags and 1) == 0:
      heavyState.resetHeavy()
    inc expectedTrack
  if expectedTrack != archive.highTrack + 1:
    raise newException(ValueError, "DMS archive does not contain its declared track range")
  if archive.unpackedSize != 0 and uint32(result.len) != archive.unpackedSize:
    raise newException(ValueError, "DMS unpacked size does not match its track data")

proc unpackAmigaDms*(data: openArray[byte]): seq[byte] =
  unpackAmigaDms(parseAmigaDms(data))

proc canUnpackAmigaDms*(archive: AmigaDmsArchive): bool =
  if (archive.infoFlags and DmsEncryptedFlag) != 0:
    return false
  for track in archive.tracks:
    if track.compression notin {adcNone, adcSimple, adcHeavy1, adcHeavy2}:
      return false
  true

proc isAmigaDms*(data: openArray[byte]): bool =
  try:
    discard parseAmigaDms(data)
    true
  except ValueError:
    false

proc hasAmigaDmsExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".dms", ".fms"]
