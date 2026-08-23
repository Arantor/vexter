## Bounded DOS ANSI-art and trailing SAUCE parsing.

import std/[os, strutils]

const
  AnsiArtTypeId* = "ansi.art"
  SauceRecordLength* = 128

type
  SauceRecord* = object
    present*: bool
    title*, author*, group*, date*, fontName*: string
    fileSize*: uint32
    dataType*, fileType*, comments*, flags*: uint8
    info1*, info2*, info3*, info4*: uint16
    commentLines*: seq[string]

  AnsiArtSource* = object
    payload*: seq[byte]
    sauce*: SauceRecord
    meaningfulSequences*: int

proc leWord(data: openArray[byte], offset: int): uint16 =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc leLong(data: openArray[byte], offset: int): uint32 =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc field(data: openArray[byte], offset, length: int, zeroTerminated = false): string =
  var finish = offset + length
  if zeroTerminated:
    for position in offset ..< finish:
      if data[position] == 0: finish = position; break
  else:
    while finish > offset and data[finish - 1] in [0'u8, 32'u8]: dec finish
  for position in offset ..< finish: result.add char(data[position])

proc hasSauce*(data: openArray[byte]): bool =
  data.len >= SauceRecordLength and
    data.field(data.len - SauceRecordLength, 7) == "SAUCE00"

proc parseSauce*(data: openArray[byte]): tuple[record: SauceRecord, payloadEnd: int] =
  result.payloadEnd = data.len
  if not data.hasSauce: return
  let start = data.len - SauceRecordLength
  result.record = SauceRecord(present: true,
    title: data.field(start + 7, 35), author: data.field(start + 42, 20),
    group: data.field(start + 62, 20), date: data.field(start + 82, 8),
    fileSize: data.leLong(start + 90), dataType: data[start + 94],
    fileType: data[start + 95], info1: data.leWord(start + 96),
    info2: data.leWord(start + 98), info3: data.leWord(start + 100),
    info4: data.leWord(start + 102), comments: data[start + 104],
    flags: data[start + 105], fontName: data.field(start + 106, 22, true))
  var materialStart = start
  if result.record.comments > 0:
    let commentLength = 5 + int(result.record.comments) * 64
    if materialStart < commentLength or
        data.field(materialStart - commentLength, 5) != "COMNT":
      raise newException(ValueError, "SAUCE comment count has no valid COMNT block")
    materialStart -= commentLength
    for line in 0 ..< int(result.record.comments):
      result.record.commentLines.add data.field(materialStart + 5 + line * 64, 64)
  if materialStart > 0 and data[materialStart - 1] == 0x1a:
    result.payloadEnd = materialStart - 1
  else:
    result.payloadEnd = materialStart

proc scanAnsi(payload: openArray[byte]): int =
  var position = 0
  while position < payload.len:
    if payload[position] == 0x1a: break
    if payload[position] != 0x1b: inc position; continue
    if position + 1 >= payload.len: raise newException(ValueError, "truncated ANSI escape")
    if payload[position + 1] in [byte('7'), byte('8'), byte('M')]:
      inc result; position += 2; continue
    if payload[position + 1] != byte('['):
      raise newException(ValueError, "unsupported ANSI escape")
    var final = position + 2
    while final < payload.len and payload[final] >= 0x20 and payload[final] <= 0x3f:
      inc final
    if final >= payload.len or payload[final] < 0x40 or payload[final] > 0x7e:
      raise newException(ValueError, "truncated ANSI control sequence")
    if char(payload[final]) in {'A','B','C','D','E','F','G','H','f','J','K','m','s','u'}:
      inc result
    position = final + 1

proc parseAnsiArt*(data: openArray[byte]): AnsiArtSource =
  let parsed = parseSauce(data)
  result.sauce = parsed.record
  result.payload = @data[0 ..< parsed.payloadEnd]
  result.meaningfulSequences = scanAnsi(result.payload)
  if result.sauce.present and
      (result.sauce.dataType != 1 or result.sauce.fileType notin [1'u8, 2'u8]):
    raise newException(ValueError, "SAUCE does not classify the payload as ANSI")
  if result.meaningfulSequences == 0:
    raise newException(ValueError, "text has no meaningful ANSI control sequences")

proc isAnsiArt*(data: openArray[byte]): bool =
  try: discard parseAnsiArt(data); true
  except ValueError: false

proc hasAnsiArtExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".ans", ".art", ".ice", ".nfo"]
