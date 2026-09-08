## Dependency-free raw LZMA decoding primitives.
##
## Container framing and property serialization belong to callers such as
## Inno Setup and, later, XZ and 7z.

type
  RawLzmaProperties* = object
    lc*, lp*, pb*: int
    dictionarySize*: int

const
  ProbabilityBits = 11
  ProbabilityTotal = 1 shl ProbabilityBits
  NormalizeThreshold = 1'u32 shl 24
  MaximumDictionarySize* = 1024 * 1024 * 1024

type RangeDecoder = object
  source: seq[byte]
  position: int
  range, code: uint32

proc initRangeDecoder(source: sink seq[byte]): RangeDecoder =
  if source.len < 5 or source[0] != 0:
    raise newException(ValueError, "invalid or truncated raw LZMA range header")
  result.source = move(source)
  result.range = high(uint32)
  for index in 1 .. 4:
    result.code = (result.code shl 8) or uint32(result.source[index])
  result.position = 5

proc normalize(reader: var RangeDecoder) =
  if reader.range < NormalizeThreshold:
    if reader.position >= reader.source.len:
      raise newException(ValueError, "truncated raw LZMA stream")
    reader.range = reader.range shl 8
    reader.code = (reader.code shl 8) or uint32(reader.source[reader.position])
    inc reader.position

proc decodeBit(reader: var RangeDecoder, probability: var uint16): int =
  let bound = (reader.range shr ProbabilityBits) * uint32(probability)
  if reader.code < bound:
    reader.range = bound
    probability = uint16(int(probability) +
      ((ProbabilityTotal - int(probability)) shr 5))
  else:
    reader.range -= bound
    reader.code -= bound
    probability = uint16(int(probability) - (int(probability) shr 5))
    result = 1
  reader.normalize()

proc bitTree(reader: var RangeDecoder, probabilities: var seq[uint16],
    offset, bits: int): int =
  var symbol = 1
  for unused in 0 ..< bits:
    symbol = (symbol shl 1) or reader.decodeBit(probabilities[offset + symbol])
  symbol - (1 shl bits)

proc reverseBitTree(reader: var RangeDecoder, probabilities: var seq[uint16],
    offset, bits: int): int =
  var symbol = 1
  for bit in 0 ..< bits:
    let value = reader.decodeBit(probabilities[offset + symbol])
    symbol = (symbol shl 1) or value
    result = result or (value shl bit)

proc directBits(reader: var RangeDecoder, count: int): uint32 =
  for unused in 0 ..< count:
    reader.range = reader.range shr 1
    let mask = 0'u32 - (if reader.code >= reader.range: 1'u32 else: 0'u32)
    reader.code -= reader.range and mask
    result = (result shl 1) or (mask and 1)
    reader.normalize()

type LengthDecoder = object
  choice: array[2, uint16]
  low, mid: seq[uint16]
  high: seq[uint16]

type LzmaDecoderState = object
  isMatch, isRep, isRepG0, isRepG1, isRepG2, isRep0Long: seq[uint16]
  posSlot, posSpecial, posAlign, literal: seq[uint16]
  length, repLength: LengthDecoder
  state: int
  reps: array[4, uint32]
  previous: int

proc initLengthDecoder(posStates: int): LengthDecoder =
  result.choice = [1024'u16, 1024'u16]
  result.low = newSeq[uint16](posStates * 8)
  result.mid = newSeq[uint16](posStates * 8)
  result.high = newSeq[uint16](256)
  for item in result.low.mitems: item = 1024
  for item in result.mid.mitems: item = 1024
  for item in result.high.mitems: item = 1024

proc decodeLength(decoder: var LengthDecoder, reader: var RangeDecoder,
    posState: int): int =
  if reader.decodeBit(decoder.choice[0]) == 0:
    return reader.bitTree(decoder.low, posState * 8, 3)
  if reader.decodeBit(decoder.choice[1]) == 0:
    return 8 + reader.bitTree(decoder.mid, posState * 8, 3)
  16 + reader.bitTree(decoder.high, 0, 8)

proc validate*(properties: RawLzmaProperties) =
  if properties.lc notin 0 .. 8 or properties.lp notin 0 .. 4 or
      properties.pb notin 0 .. 4 or properties.lc + properties.lp > 4:
    raise newException(ValueError, "invalid raw LZMA properties")
  if properties.dictionarySize < 1 or
      properties.dictionarySize > MaximumDictionarySize:
    raise newException(ValueError, "invalid raw LZMA dictionary size")

proc decodeRawLzmaSegment(source: sink seq[byte], properties: RawLzmaProperties,
    maximumOutput: int, expectedSize = -1,
    presetDictionary: seq[byte], decoder: var LzmaDecoderState,
    resetState: bool): seq[byte] =
  ## Decodes one raw LZMA1 stream. `expectedSize == -1` requires an LZMA end
  ## marker; otherwise decoding stops exactly at the declared byte count.
  properties.validate()
  if maximumOutput < 0 or expectedSize > maximumOutput:
    raise newException(ValueError, "raw LZMA output exceeds its active limit")
  var reader = initRangeDecoder(move(source))
  result = presetDictionary
  let outputStart = result.len
  let posStates = 1 shl properties.pb
  let posMask = posStates - 1
  if resetState:
    decoder = LzmaDecoderState(
      isMatch: newSeq[uint16](12 * 16), isRep: newSeq[uint16](12),
      isRepG0: newSeq[uint16](12), isRepG1: newSeq[uint16](12),
      isRepG2: newSeq[uint16](12), isRep0Long: newSeq[uint16](12 * 16),
      posSlot: newSeq[uint16](4 * 64), posSpecial: newSeq[uint16](114),
      posAlign: newSeq[uint16](16),
      literal: newSeq[uint16](0x300 shl (properties.lc + properties.lp)),
      length: initLengthDecoder(posStates), repLength: initLengthDecoder(posStates),
      previous: (if result.len > 0: int(result[^1]) else: 0))
    for models in [decoder.isMatch.addr, decoder.isRep.addr,
        decoder.isRepG0.addr, decoder.isRepG1.addr, decoder.isRepG2.addr,
        decoder.isRep0Long.addr, decoder.posSlot.addr,
        decoder.posSpecial.addr, decoder.posAlign.addr, decoder.literal.addr]:
      for item in models[].mitems: item = 1024
  template isMatch: untyped = decoder.isMatch
  template isRep: untyped = decoder.isRep
  template isRepG0: untyped = decoder.isRepG0
  template isRepG1: untyped = decoder.isRepG1
  template isRepG2: untyped = decoder.isRepG2
  template isRep0Long: untyped = decoder.isRep0Long
  template posSlot: untyped = decoder.posSlot
  template posSpecial: untyped = decoder.posSpecial
  template posAlign: untyped = decoder.posAlign
  template literal: untyped = decoder.literal
  template length: untyped = decoder.length
  template repLength: untyped = decoder.repLength
  template state: untyped = decoder.state
  template reps: untyped = decoder.reps
  template previous: untyped = decoder.previous
  let literalPosMask = (1 shl properties.lp) - 1
  let literalContextMask = (1 shl properties.lc) - 1
  while expectedSize < 0 or result.len - outputStart < expectedSize:
    if result.len - outputStart >= maximumOutput:
      raise newException(ValueError, "raw LZMA output exceeds its active limit")
    let posState = result.len and posMask
    if reader.decodeBit(isMatch[state * 16 + posState]) == 0:
      let context = (((result.len and literalPosMask) shl properties.lc) or
        ((previous shr (8 - properties.lc)) and literalContextMask)) * 0x300
      var symbol = 1
      if state >= 7:
        if reps[0] >= uint32(result.len):
          raise newException(ValueError, "invalid raw LZMA match distance")
        var matchByte = int(result[result.len - int(reps[0]) - 1])
        while symbol < 0x100:
          let matchBit = (matchByte shr 7) and 1
          matchByte = (matchByte shl 1) and 0xff
          let bit = reader.decodeBit(literal[context + 0x100 +
            (matchBit shl 8) + symbol])
          symbol = (symbol shl 1) or bit
          if bit != matchBit:
            while symbol < 0x100:
              symbol = (symbol shl 1) or reader.decodeBit(
                literal[context + symbol])
            break
      else:
        while symbol < 0x100:
          symbol = (symbol shl 1) or reader.decodeBit(literal[context + symbol])
      previous = symbol - 0x100
      result.add byte(previous)
      state = if state < 4: 0 elif state < 10: state - 3 else: state - 6
      continue
    var matchLength: int
    if reader.decodeBit(isRep[state]) == 1:
      if reader.decodeBit(isRepG0[state]) == 0:
        if reader.decodeBit(isRep0Long[state * 16 + posState]) == 0:
          state = if state < 7: 9 else: 11
          matchLength = 1
      else:
        var distance: uint32
        if reader.decodeBit(isRepG1[state]) == 0:
          distance = reps[1]
        else:
          if reader.decodeBit(isRepG2[state]) == 0:
            distance = reps[2]
          else:
            distance = reps[3]
            reps[3] = reps[2]
          reps[2] = reps[1]
        reps[1] = reps[0]
        reps[0] = distance
      if matchLength == 0:
        matchLength = repLength.decodeLength(reader, posState) + 2
        state = if state < 7: 8 else: 11
    else:
      reps[3] = reps[2]; reps[2] = reps[1]; reps[1] = reps[0]
      matchLength = length.decodeLength(reader, posState) + 2
      state = if state < 7: 7 else: 10
      let slot = reader.bitTree(posSlot, min(matchLength - 2, 3) * 64, 6)
      if slot < 4:
        reps[0] = uint32(slot)
      else:
        let directCount = (slot shr 1) - 1
        reps[0] = uint32(2 or (slot and 1)) shl directCount
        if slot < 14:
          reps[0] += uint32(reader.reverseBitTree(posSpecial,
            int(reps[0]) - slot - 1, directCount))
        else:
          reps[0] += reader.directBits(directCount - 4) shl 4
          reps[0] += uint32(reader.reverseBitTree(posAlign, 0, 4))
          if reps[0] == high(uint32):
            if expectedSize >= 0:
              raise newException(ValueError, "early raw LZMA end marker")
            return
    if reps[0] >= uint32(result.len):
      raise newException(ValueError, "invalid raw LZMA match distance")
    if matchLength > maximumOutput - (result.len - outputStart):
      raise newException(ValueError, "raw LZMA match exceeds declared output")
    let copyLength = if expectedSize >= 0:
      min(matchLength, expectedSize - (result.len - outputStart))
      else: matchLength
    for unused in 0 ..< copyLength:
      previous = int(result[result.len - int(reps[0]) - 1])
      result.add byte(previous)
  if expectedSize >= 0 and result.len - outputStart != expectedSize:
    raise newException(ValueError, "raw LZMA output length mismatch")
  if outputStart > 0:
    result = result[outputStart .. ^1]

proc decodeRawLzma1*(source: sink seq[byte], properties: RawLzmaProperties,
    maximumOutput: int, expectedSize = -1,
    presetDictionary: seq[byte] = @[]): seq[byte] =
  var decoder: LzmaDecoderState
  decodeRawLzmaSegment(move(source), properties, maximumOutput, expectedSize,
    presetDictionary, decoder, true)

proc decodeRawLzma2*(source: openArray[byte], dictionarySize,
    maximumOutput: int): seq[byte] =
  ## Decodes LZMA2 framing. Compressed substreams that reset coder state are
  ## delegated to the shared LZMA1 engine with the accumulated dictionary.
  var cursor = 0
  var properties = RawLzmaProperties(dictionarySize: dictionarySize)
  var haveProperties = false
  var decoder: LzmaDecoderState
  var haveDecoderState = false
  var dictionaryStart = 0
  while true:
    if cursor >= source.len:
      raise newException(ValueError, "truncated raw LZMA2 stream")
    let control = int(source[cursor]); inc cursor
    if control == 0: return
    if control in 1 .. 2:
      if cursor > source.len - 2:
        raise newException(ValueError, "truncated raw LZMA2 stored block")
      let size = (int(source[cursor]) shl 8 or int(source[cursor + 1])) + 1
      cursor += 2
      if size > source.len - cursor or size > maximumOutput - result.len:
        raise newException(ValueError, "invalid raw LZMA2 stored block")
      if control == 1: dictionaryStart = result.len
      result.add source.toOpenArray(cursor, cursor + size - 1)
      cursor += size
      if haveDecoderState and result.len > 0:
        decoder.previous = int(result[^1])
      continue
    if control < 0x80:
      raise newException(ValueError, "invalid raw LZMA2 control byte")
    if cursor > source.len - 4:
      raise newException(ValueError, "truncated raw LZMA2 block header")
    let unpacked = (((control and 0x1f) shl 16) or
      (int(source[cursor]) shl 8) or int(source[cursor + 1])) + 1
    let packed = ((int(source[cursor + 2]) shl 8) or int(source[cursor + 3])) + 1
    cursor += 4
    if control >= 0xc0:
      if cursor >= source.len:
        raise newException(ValueError, "truncated raw LZMA2 properties")
      let value = int(source[cursor]); inc cursor
      if value >= 9 * 5 * 5:
        raise newException(ValueError, "invalid raw LZMA2 properties")
      properties.lc = value mod 9
      properties.lp = (value div 9) mod 5
      properties.pb = value div (9 * 5)
      haveProperties = true
    if not haveProperties:
      raise newException(ValueError, "raw LZMA2 block has no properties")
    if packed > source.len - cursor or unpacked > maximumOutput - result.len:
      raise newException(ValueError, "invalid raw LZMA2 compressed block")
    var encoded = newSeq[byte](packed)
    for index in 0 ..< packed: encoded[index] = source[cursor + index]
    cursor += packed
    var dictionary: seq[byte]
    if control >= 0xe0:
      dictionaryStart = result.len
    elif dictionaryStart < result.len:
      dictionary = result[dictionaryStart .. ^1]
    let resetState = control >= 0xa0
    if not resetState and not haveDecoderState:
      raise newException(ValueError, "raw LZMA2 continuation has no coder state")
    try:
      result.add decodeRawLzmaSegment(move(encoded), properties,
        maximumOutput - result.len, unpacked, dictionary, decoder, resetState)
    except ValueError as error:
      raise newException(ValueError, "raw LZMA2 block control " & $control &
        " (output " & $unpacked & "): " & error.msg)
    haveDecoderState = true
