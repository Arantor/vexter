## XPK container parsing and SHRI arithmetic/LZ decompression.
##
## Ported from Ancient Format Decompressor's XPKMaster and SHRIDecompressor,
## Copyright (c) 2017 Teemu Suutari, under the BSD 2-Clause License.

const
  XpkTypeId* = "archive.xpk"
  XpkMagic* = "XPKF"
  XpkShriMethod* = "SHRI"
  XpkMaxUnpackedSize = 512 * 1024 * 1024

type
  XpkChunk* = object
    kind*: int
    packed*: seq[byte]
    unpackedSize*: int

  XpkArchive* = object
    compression*: string
    unpackedSize*: int
    rawPrefix*: seq[byte]
    chunks*: seq[XpkChunk]

  ShriState = object
    initialized: bool
    valueLength, nextUpgrade, interval: uint32
    frequencies: array[999, uint32]

proc ascii(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "truncated XPK text field")
  for index in offset ..< offset + length:
    result.add char(data[index])

proc be16(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 2:
    raise newException(ValueError, "truncated XPK 16-bit value")
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc be32(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset > data.len - 4:
    raise newException(ValueError, "truncated XPK 32-bit value")
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc headerChecksum(data: openArray[byte], offset, length: int): bool =
  if length <= 0 or offset < 0 or offset > data.len - length:
    return false
  var checksum: byte
  for index in offset ..< offset + length:
    checksum = checksum xor data[index]
  checksum == 0

proc chunkChecksum(data: openArray[byte], offset, length,
    expected: int): bool =
  if length <= 0 or offset < 0 or offset > data.len - length:
    return false
  var high, low: byte
  for index in 0 ..< length:
    if index mod 2 == 0: high = high xor data[offset + index]
    else: low = low xor data[offset + index]
  int(high) == expected shr 8 and int(low) == (expected and 0xff)

proc parseXpk*(data: openArray[byte]): XpkArchive =
  if data.len < 44 or ascii(data, 0, 4) != XpkMagic:
    raise newException(ValueError, "XPK data must begin with XPKF")
  let
    packedSize = int(be32(data, 4))
    rawSize = int(be32(data, 12))
    flags = int(data[32])
  if packedSize <= 0 or packedSize != data.len - 8:
    raise newException(ValueError, "XPK packed size does not match the file")
  if rawSize <= 0 or rawSize > XpkMaxUnpackedSize:
    raise newException(ValueError, "invalid XPK unpacked size")
  if (flags and 2) != 0:
    raise newException(ValueError, "password-protected XPK is unsupported")
  if not headerChecksum(data, 0, 36):
    raise newException(ValueError, "invalid XPK master-header checksum")
  result.compression = ascii(data, 8, 4)
  if result.compression != XpkShriMethod:
    raise newException(ValueError, "unsupported XPK compression method: " &
      result.compression)
  result.unpackedSize = rawSize
  result.rawPrefix = @data[16 ..< min(32, 16 + rawSize)]
  let longHeaders = (flags and 1) != 0
  var position = 36
  if (flags and 4) != 0:
    let extraLength = be16(data, 36)
    position = 38 + extraLength
    if position > data.len:
      raise newException(ValueError, "truncated XPK extended header")
  var totalRaw = 0
  while true:
    let headerLength = if longHeaders: 12 else: 8
    if position > data.len - headerLength or
        not headerChecksum(data, position, headerLength):
      raise newException(ValueError, "invalid XPK chunk header")
    let
      kind = int(data[position])
      expectedChecksum = be16(data, position + 2)
      packedLength = if longHeaders: int(be32(data, position + 4))
                     else: be16(data, position + 4)
      unpackedLength = if longHeaders: int(be32(data, position + 8))
                       else: be16(data, position + 6)
      payload = position + headerLength
    if packedLength < 0 or unpackedLength < 0 or
        payload > data.len - packedLength:
      raise newException(ValueError, "truncated XPK chunk")
    if packedLength > 0 and not chunkChecksum(data, payload, packedLength,
        expectedChecksum):
      raise newException(ValueError, "invalid XPK chunk checksum")
    if kind == 15:
      if packedLength != 0 or unpackedLength != 0:
        raise newException(ValueError, "invalid XPK end chunk")
      if position + headerLength != data.len:
        raise newException(ValueError, "XPK data follows the end chunk")
      break
    if kind notin [0, 1]:
      raise newException(ValueError, "unsupported XPK chunk type")
    if totalRaw > rawSize - unpackedLength:
      raise newException(ValueError, "XPK chunks exceed unpacked size")
    result.chunks.add XpkChunk(kind: kind,
      packed: @data[payload ..< payload + packedLength],
      unpackedSize: unpackedLength)
    totalRaw += unpackedLength
    position = payload + ((packedLength + 3) and not 3)
  if totalRaw != rawSize:
    raise newException(ValueError, "XPK chunks do not fill unpacked size")

proc isXpk*(data: openArray[byte]): bool =
  try:
    discard parseXpk(data)
    true
  except ValueError:
    false

proc decompressShri(packed, previous: seq[byte], expectedSize: int,
    state: var ShriState): seq[byte] =
  if packed.len < 6:
    raise newException(ValueError, "truncated SHRI chunk")
  let version = int(packed[0])
  if version notin [1, 2]:
    raise newException(ValueError, "unsupported SHRI chunk version")
  var startOffset, rawSize: int
  if packed[2] < 0x80:
    rawSize = be16(packed, 2)
    startOffset = 4
  else:
    rawSize = int(0'u32 - be32(packed, 2))
    startOffset = 6
  if rawSize != expectedSize:
    raise newException(ValueError, "SHRI and XPK chunk sizes disagree")
  if version == 2 and not state.initialized:
    raise newException(ValueError, "SHRI continuation has no initial state")

  {.push overflowChecks: off.}
  var
    frequencies: array[999, uint32]
    valueLength, nextUpgrade, interval: uint32
    streamStatus = true
    inputOffset = startOffset
    stream: uint32

  proc resum() =
    for index in countdown(498, 1):
      frequencies[index] = frequencies[index * 2] + frequencies[index * 2 + 1]

  proc initialize() =
    for index in 0 ..< 499: frequencies[index] = 0
    for index in 0 ..< 256:
      frequencies[index + 499] = if index < 32 or index > 126: 1 else: 3
    for index in 755 ..< 999: frequencies[index] = 0
    resum()

  proc update(updateIndex, increment: uint32) =
    if updateIndex >= 499: return
    var index = updateIndex + 499
    while index != 0:
      frequencies[index] += increment
      index = index shr 1
    if frequencies[1] >= 0x2000:
      for leaf in 499 ..< 998:
        if frequencies[leaf] != 0:
          frequencies[leaf] = (frequencies[leaf] shr 1) + 1
      resum()

  proc scale(a, b, multiplier: uint32): uint32 =
    if b == 0:
      streamStatus = false
      return 0
    let
      shifted = a shl 16
      first = shifted div b
      second = ((shifted mod b) shl 16) div b
    ((multiplier and 0xffff) * first shr 16) +
      ((multiplier shr 16) * second shr 16) + (multiplier shr 16) * first

  proc refill() =
    while interval < 0x1000000:
      if inputOffset >= packed.len:
        streamStatus = false
        return
      stream = (stream shl 8) or uint32(packed[inputOffset])
      inc inputOffset
      interval = interval shl 8

  proc getSymbol(): uint32 =
    if (interval shr 16) == 0:
      streamStatus = false
      return 0
    let
      value = (stream div (interval shr 16)) and 0xffff
      threshold = (frequencies[1] * value) shr 16
    var
      treeIndex = 1'u32
      cumulative = 0'u32
    while true:
      treeIndex = treeIndex shl 1
      let candidate = frequencies[treeIndex] + cumulative
      if threshold >= candidate:
        cumulative = candidate
        inc treeIndex
      if treeIndex >= 499: break
    var low = scale(cumulative, frequencies[1], interval)
    if low > stream:
      while low > stream:
        dec treeIndex
        if treeIndex < 499: treeIndex += 499
        cumulative -= frequencies[treeIndex]
        low = scale(cumulative, frequencies[1], interval)
    else:
      cumulative += frequencies[treeIndex]
      while cumulative < frequencies[1]:
        let comparison = scale(cumulative, frequencies[1], interval)
        if stream < comparison: break
        inc treeIndex
        if treeIndex >= 998: treeIndex -= 499
        cumulative += frequencies[treeIndex]
        low = comparison
    stream -= low
    interval = scale(frequencies[treeIndex], frequencies[1], interval)
    let addition = (frequencies[1] shr 10) + 3
    treeIndex -= 499
    update(treeIndex, addition)
    refill()
    treeIndex

  proc getCode(size: uint32): uint32 =
    var remaining = size
    while remaining != 0:
      result = result shl 1
      interval = interval shr 1
      if stream >= interval:
        inc result
        stream -= interval
      refill()
      dec remaining

  proc upgrade() =
    if nextUpgrade >= 65532:
      nextUpgrade = high(uint32)
    elif valueLength == 0:
      nextUpgrade = 1
    else:
      var value = nextUpgrade - 1
      if value < 48: update(value + 256, 1)
      var bits = 0'u32
      var comparison = 4'u32
      while value >= comparison:
        value -= comparison
        comparison = comparison shl 1
        inc bits
      if bits >= 14:
        nextUpgrade = high(uint32)
      else:
        if value == 0:
          if bits < 7:
            for index in 304'u32 .. 307'u32: update((bits shl 2) + index, 1)
          if bits < 13:
            for index in 332'u32 .. 333'u32: update((bits shl 1) + index, 1)
          for index in [358'u32, 359, 386, 387, 414, 415]:
            update((bits shl 1) + index, 1)
          for index in [442'u32, 456, 470, 484]:
            update(bits + index, 1)
        if nextUpgrade < 49: inc nextUpgrade
        elif nextUpgrade == 49: nextUpgrade = 61
        else: nextUpgrade = (nextUpgrade shl 1) + 3

  if version == 1:
    initialize()
    update(498, 1)
    interval = 0x80000000'u32
  else:
    valueLength = state.valueLength
    nextUpgrade = state.nextUpgrade
    interval = state.interval
    frequencies = state.frequencies
  if inputOffset > packed.len - 4:
    raise newException(ValueError, "truncated SHRI arithmetic stream")
  stream = be32(packed, inputOffset)
  inputOffset += 4
  result = newSeq[byte](rawSize)
  var outputOffset = 0
  proc distanceAddition(index: uint32): uint32 =
    ((1'u32 shl (index + 2)) - 1) and not 3'u32

  while streamStatus and outputOffset < rawSize:
    while valueLength >= nextUpgrade: upgrade()
    let symbol = getSymbol()
    if symbol < 256:
      result[outputOffset] = byte(symbol)
      inc outputOffset
      inc valueLength
    else:
      var count, distance: uint32
      if symbol < 304:
        count = 2
        distance = symbol - 255
      elif symbol < 332:
        let temporary = symbol - 304
        distance = (getCode(temporary shr 2) shl 2 or
          (temporary and 3)) + distanceAddition(temporary shr 2) + 1
        count = 3
      elif symbol < 358:
        let temporary = symbol - 332
        distance = (getCode((temporary shr 1) + 1) shl 1 or
          (temporary and 1)) + distanceAddition(temporary shr 1) + 1
        count = 4
      elif symbol < 386:
        let temporary = symbol - 358
        distance = (getCode((temporary shr 1) + 1) shl 1 or
          (temporary and 1)) + distanceAddition(temporary shr 1) + 1
        count = 5
      elif symbol < 414:
        let temporary = symbol - 386
        distance = (getCode((temporary shr 1) + 1) shl 1 or
          (temporary and 1)) + distanceAddition(temporary shr 1) + 1
        count = 6
      elif symbol < 442:
        let temporary = symbol - 414
        distance = (getCode((temporary shr 1) + 1) shl 1 or
          (temporary and 1)) + distanceAddition(temporary shr 1) + 1
        count = 7
      elif symbol < 498:
        let
          temporary = symbol - 442
          distanceBits = temporary div 14
          countBits = temporary mod 14
        count = getCode(distanceBits + 2) + distanceAddition(distanceBits) + 8
        distance = getCode(countBits + 2) + distanceAddition(countBits) + 1
      else:
        count = getCode(16)
        distance = getCode(16)
      valueLength += count
      if count == 0 or distance == 0 or
          distance > uint32(outputOffset + previous.len) or
          count > uint32(rawSize - outputOffset):
        streamStatus = false
      else:
        for unused in 0 ..< int(count):
          let sourceOffset = outputOffset - int(distance)
          if sourceOffset >= 0:
            result[outputOffset] = result[sourceOffset]
          else:
            result[outputOffset] = previous[previous.len + sourceOffset]
          inc outputOffset
  if not streamStatus or outputOffset != rawSize:
    raise newException(ValueError, "invalid SHRI compressed stream")
  state.initialized = true
  state.valueLength = valueLength
  state.nextUpgrade = nextUpgrade
  state.interval = interval
  state.frequencies = frequencies
  {.pop.}

proc unpackXpk*(archive: XpkArchive): seq[byte] =
  result = newSeqOfCap[byte](archive.unpackedSize)
  var state: ShriState
  for chunk in archive.chunks:
    if chunk.kind == 0:
      if chunk.packed.len != chunk.unpackedSize:
        raise newException(ValueError, "XPK raw chunk sizes disagree")
      result.add chunk.packed
    else:
      result.add decompressShri(chunk.packed, result,
        chunk.unpackedSize, state)
  if result.len != archive.unpackedSize or
      result[0 ..< archive.rawPrefix.len] != archive.rawPrefix:
    raise newException(ValueError, "XPK unpacked data fails prefix check")

proc unpackXpk*(data: openArray[byte]): seq[byte] =
  unpackXpk(parseXpk(data))
