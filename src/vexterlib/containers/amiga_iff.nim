## Generic parser for EA IFF FORM containers.

import std/[os, strutils]

const
  AmigaIffTypeId* = "amiga.iff"
  AmigaIffFormMagic* = "FORM"

type
  AmigaIffChunk* = object
    id*: string
    data*: seq[byte]

  AmigaIffForm* = object
    formType*: string
    chunks*: seq[AmigaIffChunk]

proc ascii(data: openArray[byte], offset, length: int): string =
  for index in offset ..< offset + length:
    result.add char(data[index])

proc bigEndianLong(data: openArray[byte], offset: int): uint64 {.inline.} =
  (uint64(data[offset]) shl 24) or (uint64(data[offset + 1]) shl 16) or
    (uint64(data[offset + 2]) shl 8) or uint64(data[offset + 3])

proc parseChunks(data: openArray[byte], offset: int): seq[AmigaIffChunk] =
  var position = offset
  while position < data.len:
    if data.len - position < 8:
      raise newException(ValueError, "truncated IFF chunk header")
    let
      chunkId = ascii(data, position, 4)
      chunkSize = bigEndianLong(data, position + 4)
      payloadStart = position + 8
    if chunkSize > uint64(data.len - payloadStart):
      raise newException(ValueError, "truncated IFF " & chunkId & " chunk")
    let payloadEnd = payloadStart + int(chunkSize)
    result.add AmigaIffChunk(
      id: chunkId, data: @data[payloadStart ..< payloadEnd])
    position = payloadEnd + int(chunkSize and 1'u64)
    if position > data.len:
      raise newException(ValueError, "missing IFF chunk pad byte")

proc parseAmigaIffFormPayload*(data: openArray[byte]): AmigaIffForm =
  ## Parses the payload of a nested FORM chunk: form type followed by chunks.
  if data.len < 4:
    raise newException(ValueError, "IFF FORM payload is missing its type")
  result.formType = ascii(data, 0, 4)
  result.chunks = parseChunks(data, 4)

proc parseAmigaIff*(data: openArray[byte]): AmigaIffForm =
  if data.len < 12 or ascii(data, 0, 4) != AmigaIffFormMagic:
    raise newException(ValueError, "IFF data must begin with a FORM header")
  let formSize = bigEndianLong(data, 4)
  if formSize < 4 or formSize + 8'u64 != uint64(data.len):
    raise newException(ValueError, "IFF FORM length does not match the file")
  result.formType = ascii(data, 8, 4)

  result.chunks = parseChunks(data, 12)

proc isAmigaIff*(data: openArray[byte]): bool =
  try:
    discard parseAmigaIff(data)
    true
  except ValueError:
    false

proc hasAmigaIffExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".iff", ".ilbm", ".lbm"]
