## Parsing for AMOS `Samples` bank payloads.

import std/strutils

const
  AmosSampleResourceTypeId* = "amos.sample"
  AmosSampleRecordHeaderSize* = 14
  MaximumAmosSamples* = 4096

type
  AmosSample* = object
    name*: string
    sampleRate*: int
    data*: seq[byte]

  AmosSampleBank* = object
    samples*: seq[AmosSample]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 24) or (int(data[offset + 1]) shl 16) or
    (int(data[offset + 2]) shl 8) or int(data[offset + 3])

proc fixedName(data: openArray[byte], offset: int): string =
  for index in 0 ..< 8:
    let value = data[offset + index]
    if value == 0: break
    if value > 0x7f:
      raise newException(ValueError, "AMOS sample name is not ASCII")
    result.add char(value)
  result = result.strip(leading = false, trailing = true, chars = {' '})

proc parseAmosSampleBank*(data: openArray[byte]): AmosSampleBank =
  if data.len < 2:
    raise newException(ValueError, "truncated AMOS sample bank")
  let count = beWord(data, 0)
  if count > MaximumAmosSamples or count > (data.len - 2) div 4:
    raise newException(ValueError, "invalid AMOS sample count")
  let tableEnd = 2 + count * 4
  var expectedOffset = tableEnd
  for index in 0 ..< count:
    let offset = beDword(data, 2 + index * 4)
    if offset != expectedOffset or offset > data.len - AmosSampleRecordHeaderSize:
      raise newException(ValueError, "invalid AMOS sample offset")
    let
      sampleRate = beWord(data, offset + 8)
      length = beDword(data, offset + 10)
    if sampleRate <= 0 or length <= 0 or
        length > data.len - offset - AmosSampleRecordHeaderSize:
      raise newException(ValueError, "invalid AMOS sample header")
    let sampleEnd = offset + AmosSampleRecordHeaderSize + length
    if index + 1 < count and beDword(data, 2 + (index + 1) * 4) != sampleEnd:
      raise newException(ValueError, "AMOS sample records are not contiguous")
    result.samples.add AmosSample(
      name: fixedName(data, offset), sampleRate: sampleRate,
      data: @data[offset + AmosSampleRecordHeaderSize ..< sampleEnd])
    expectedOffset = sampleEnd
  if expectedOffset != data.len:
    raise newException(ValueError, "unexpected data after AMOS sample bank")
