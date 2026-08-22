## Structural parsing for FLI, FLC, CEL, FLH, FLT, and FLX animations.

import std/[os, strutils]

const
  FlicTypeId* = "flic"
  FlicMagicFli* = 0xaf11
  FlicMagicFlc* = 0xaf12
  FlicMagicCompressed* = 0xaf30
  FlicMagicFrameShift* = 0xaf31
  FlicMagicDta* = 0xaf44
  FlicFrameChunk* = 0xf1fa
  FlicPrefixChunk* = 0xf100
  FlicSegmentTableChunk* = 0xf1fb
  FlicHuffmanTableChunk* = 0xf1fc
  FlicScriptChunk* = 0xf1e0

type
  FlicHuffmanCode* = object
    code*: uint16
    length*: int
    value*: byte

  FlicSubchunk* = object
    kind*: int
    data*: seq[byte]

  FlicFrame* = object
    delayMs*: int
    width*, height*: int
    chunks*: seq[FlicSubchunk]

  FlicSource* = object
    fileMagic*: int
    declaredSize*: int
    frameCount*: int
    width*, height*, depth*: int
    flags*: int
    speed*: uint32
    creator*, updater*: uint32
    aspectX*, aspectY*: int
    extensionFlags*, keyframeFrequency*, totalFrames*: int
    requiredMemory*: uint32
    maxRegions*, transparencyLevels*: int
    firstFrameOffset*, secondFrameOffset*: uint32
    celCenterX*, celCenterY*: int
    transparentIndex*: int
    prefixChunks*: seq[FlicSubchunk]
    frames*: seq[FlicFrame]
    hasSegmentTable*, hasHuffmanTable*, hasScript*: bool
    huffmanCodeLength*: int
    huffmanCodes*: seq[FlicHuffmanCode]

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc checkedChunkEnd(data: openArray[byte], offset, limit: int): int =
  if offset < 0 or offset > limit - 6:
    raise newException(ValueError, "truncated FLIC chunk header")
  let size = uint64(leDword(data, offset))
  if size < 6 or size > uint64(limit - offset):
    raise newException(ValueError, "invalid FLIC chunk size")
  offset + int(size)

proc parseSubchunks(data: openArray[byte], startOffset, limit, count: int):
    seq[FlicSubchunk] =
  var offset = startOffset
  for unused in 0 ..< count:
    let chunkEnd = checkedChunkEnd(data, offset, limit)
    var chunk = FlicSubchunk(kind: leWord(data, offset + 4))
    if chunkEnd > offset + 6:
      chunk.data.add data.toOpenArray(offset + 6, chunkEnd - 1)
    result.add chunk
    offset = chunkEnd
  if offset != limit:
    raise newException(ValueError, "FLIC chunk has data outside its declared subchunks")

proc parseFlic*(data: openArray[byte]): FlicSource =
  if data.len < 128:
    raise newException(ValueError, "FLIC file is shorter than its 128-byte header")
  let declaredSize = uint64(leDword(data, 0))
  if declaredSize < 128 or declaredSize != uint64(data.len):
    raise newException(ValueError, "FLIC declared size does not match the file")
  result.declaredSize = data.len
  result.transparentIndex = -1
  result.fileMagic = leWord(data, 4)
  if result.fileMagic notin [FlicMagicFli, FlicMagicFlc,
      FlicMagicCompressed, FlicMagicFrameShift, FlicMagicDta]:
    raise newException(ValueError, "unsupported FLIC file type")
  result.frameCount = leWord(data, 6)
  result.width = leWord(data, 8)
  result.height = leWord(data, 10)
  result.depth = leWord(data, 12)
  result.flags = leWord(data, 14)
  result.speed = leDword(data, 16)
  result.creator = leDword(data, 22)
  result.updater = leDword(data, 30)
  result.aspectX = leWord(data, 34)
  result.aspectY = leWord(data, 36)
  result.extensionFlags = leWord(data, 38)
  result.keyframeFrequency = leWord(data, 40)
  result.totalFrames = leWord(data, 42)
  result.requiredMemory = leDword(data, 44)
  result.maxRegions = leWord(data, 48)
  result.transparencyLevels = leWord(data, 50)
  result.firstFrameOffset = leDword(data, 80)
  result.secondFrameOffset = leDword(data, 84)
  if result.frameCount <= 0 or result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "FLIC dimensions and frame count must be positive")
  if uint64(result.width) * uint64(result.height) > uint64(high(int)):
    raise newException(ValueError, "FLIC dimensions exceed platform capacity")
  case result.fileMagic
  of FlicMagicFli:
    if result.width != 320 or result.height != 200 or result.depth notin [0, 8]:
      raise newException(ValueError, "invalid FLI dimensions or colour depth")
    if result.depth == 0: result.depth = 8
    result.creator = 0
    result.updater = 0
    result.aspectX = 0
    result.aspectY = 0
    result.extensionFlags = 0
    result.keyframeFrequency = 0
    result.totalFrames = 0
    result.requiredMemory = 0
    result.maxRegions = 0
    result.transparencyLevels = 0
    result.firstFrameOffset = 0
    result.secondFrameOffset = 0
  of FlicMagicFlc:
    if result.depth notin [0, 8, 15, 16]:
      raise newException(ValueError, "unsupported FLC/FLX colour depth")
    if result.depth == 0: result.depth = 8
  of FlicMagicDta:
    if result.depth notin [1, 15, 16, 24]:
      raise newException(ValueError, "unsupported DTA FLIC colour depth")
  of FlicMagicCompressed, FlicMagicFrameShift:
    if result.depth notin [1, 8, 15, 16, 24]:
      raise newException(ValueError, "unsupported extended FLIC colour depth")
  else:
    discard

  var offset = 128
  while offset < data.len:
    let chunkEnd = checkedChunkEnd(data, offset, data.len)
    let kind = leWord(data, offset + 4)
    case kind
    of FlicFrameChunk:
      if chunkEnd - offset < 16:
        raise newException(ValueError, "truncated FLIC frame header")
      let chunkCount = leWord(data, offset + 6)
      var frame = FlicFrame(delayMs: leWord(data, offset + 8),
        width: leWord(data, offset + 12), height: leWord(data, offset + 14))
      frame.chunks = parseSubchunks(data, offset + 16, chunkEnd, chunkCount)
      result.frames.add frame
    of FlicPrefixChunk:
      if chunkEnd - offset < 16:
        raise newException(ValueError, "truncated FLIC prefix header")
      result.prefixChunks = parseSubchunks(data, offset + 16, chunkEnd,
        leWord(data, offset + 6))
      for chunk in result.prefixChunks:
        if chunk.kind == 3:
          if chunk.data.len != 58:
            raise newException(ValueError, "invalid FLIC CEL_DATA size")
          result.celCenterX = int(cast[int16](uint16(leWord(chunk.data, 0))))
          result.celCenterY = int(cast[int16](uint16(leWord(chunk.data, 2))))
          result.transparentIndex = leWord(chunk.data, 20)
          if result.transparentIndex > 255:
            raise newException(ValueError, "invalid FLIC CEL transparent index")
    of FlicSegmentTableChunk:
      result.hasSegmentTable = true
    of FlicHuffmanTableChunk:
      result.hasHuffmanTable = true
      if chunkEnd - offset < 16:
        raise newException(ValueError, "truncated FLIC Huffman table")
      result.huffmanCodeLength = leWord(data, offset + 6)
      let codeCount = leWord(data, offset + 8)
      if result.huffmanCodeLength <= 0 or result.huffmanCodeLength > 16 or
          codeCount <= 0 or codeCount > 256 or chunkEnd - offset != 16 + codeCount * 4:
        raise newException(ValueError, "invalid FLIC Huffman table")
      for index in 0 ..< codeCount:
        let entry = offset + 16 + index * 4
        let length = int(data[entry + 2])
        if length <= 0 or length > result.huffmanCodeLength:
          raise newException(ValueError, "invalid FLIC Huffman code length")
        result.huffmanCodes.add FlicHuffmanCode(
          code: uint16(leWord(data, entry)), length: length,
          value: data[entry + 3])
    of FlicScriptChunk:
      result.hasScript = true
    else:
      discard
    offset = chunkEnd
  if result.frames.len < result.frameCount:
    raise newException(ValueError, "FLIC contains fewer frames than declared")

proc isFlic*(data: openArray[byte]): bool =
  try: discard parseFlic(data); true
  except ValueError: false

proc hasFlicExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in
    [".fli", ".flc", ".cel", ".flh", ".flt", ".flx"]
