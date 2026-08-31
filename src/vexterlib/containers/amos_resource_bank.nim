## Parsing for fixture-confirmed AMOS `Resource` bank payloads.

import ./amos_packed_picture

const
  AmosResourceGraphicsTypeId* = "amos.resource-graphics"
  AmosResourceStringsTypeId* = "amos.resource-strings"
  AmosResourceStringTypeId* = "amos.resource-string"
  AmosResourceGraphicTypeId* = "amos.resource-graphic"

type
  AmosResourceGraphic* = object
    picture*: AmosPackedPicture

  AmosResourceBank* = object
    paletteWords*: seq[uint16]
    sourceName*: string
    graphics*: seq[AmosResourceGraphic]
    strings*: seq[string]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 24) or (int(data[offset + 1]) shl 16) or
    (int(data[offset + 2]) shl 8) or int(data[offset + 3])

proc parseText(data: openArray[byte], offset, length: int): string =
  if length < 0 or offset < 0 or length > data.len - offset:
    raise newException(ValueError, "truncated AMOS resource text")
  for index in 0 ..< length:
    let value = data[offset + index]
    if value > 0x7f:
      raise newException(ValueError, "AMOS resource text is not ASCII")
    result.add char(value)

proc parseAmosResourceBank*(data: openArray[byte]): AmosResourceBank =
  if data.len < 18 or beWord(data, 0) != 2:
    raise newException(ValueError, "unsupported AMOS resource directory")
  let
    graphicOffset = beDword(data, 2)
    stringOffset = beDword(data, 6)
    graphicLength = beDword(data, 10)
    stringLength = beDword(data, 14)
    hasStrings = stringOffset != 0 or stringLength != 0
    graphicEnd = graphicOffset + graphicLength
  if graphicOffset != 18 or graphicLength <= 0 or graphicEnd > data.len or
      (hasStrings and (stringOffset != graphicEnd or
        stringLength <= 0 or stringOffset + stringLength != data.len)) or
      (not hasStrings and graphicEnd != data.len):
    raise newException(ValueError, "invalid AMOS resource section boundaries")

  let graphicCount = beWord(data, graphicOffset)
  if graphicCount <= 0 or graphicCount > 256:
    raise newException(ValueError, "invalid AMOS resource graphic count")
  let sharedHeader = graphicOffset + 2 + graphicCount * 4
  if sharedHeader + 70 > graphicEnd:
    raise newException(ValueError, "truncated AMOS resource graphic header")
  var pictureOffsets: seq[int]
  for index in 0 ..< graphicCount:
    let offset = graphicOffset + beDword(data, graphicOffset + 2 + index * 4)
    if offset < sharedHeader + 70 or offset >= graphicEnd or
        (pictureOffsets.len > 0 and offset <= pictureOffsets[^1]):
      raise newException(ValueError, "invalid AMOS resource graphic offset")
    pictureOffsets.add offset
  for index in 0 ..< 32:
    result.paletteWords.add uint16(beWord(data, sharedHeader + 4 + index * 2))
  let sourceLengthOffset = sharedHeader + 68
  let sourceLength = beWord(data, sourceLengthOffset)
  if sourceLength > pictureOffsets[0] - sourceLengthOffset - 2:
    raise newException(ValueError, "truncated AMOS resource source name")
  result.sourceName = parseText(data, sourceLengthOffset + 2, sourceLength)
  for index, offset in pictureOffsets:
    let pictureEnd =
      if index + 1 < pictureOffsets.len: pictureOffsets[index + 1]
      else: graphicEnd
    result.graphics.add AmosResourceGraphic(
      picture: parseAmosPackedPicture(data.toOpenArray(offset, pictureEnd - 1)))

  if not hasStrings:
    return
  if stringLength < 3 or data[stringOffset] != 0:
    raise newException(ValueError, "truncated AMOS resource string")
  var cursor = stringOffset + 1
  let stringEnd = stringOffset + stringLength
  while cursor < stringEnd:
    if data[cursor] == 0xff:
      if cursor + 2 != stringEnd or data[cursor + 1] != 0:
        raise newException(ValueError, "invalid AMOS resource string terminator")
      return
    let textLength = int(data[cursor])
    inc cursor
    if textLength > stringEnd - cursor - 1 or
        data[cursor + textLength] != 0:
      raise newException(ValueError, "invalid AMOS resource string record")
    result.strings.add parseText(data, cursor, textLength)
    cursor += textLength + 1
  raise newException(ValueError, "AMOS resource string list is unterminated")
