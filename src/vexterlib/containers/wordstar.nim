## Bounded WordStar document-family parsing based on developer-supplied
## WordStar International documentation and authentic WS4/WS7 samples.

import std/[math, options, os, strutils]
import ../archetypes/document

const
  WordStarTypeId* = "wordstar.document"
  WordStarResourcePath* = "/document"
  WordStarMaximumBytes* = 64 * 1024 * 1024
  KnownWordStarDotCommands = [
    "av", "aw", "bn", "bp", "cc", "co", "cp", "cs", "cv", "cw",
    "df", "dm", "e#", "ei", "el", "f#", "fi", "fm", "fo", "f1",
    "f2", "f3", "f4", "f5", "go", "he", "h1", "h2", "h3", "h4",
    "h5", "hm", "hy", "if", "ig", "ix", "kr", "l#", "lh", "lm",
    "lq", "ls", "ma", "mb", "mt", "oc", "oj", "op", "p#", "pa",
    "pc", "pe", "pf", "pg", "pl", "pm", "pn", "po", "pr", "ps",
    "rm", "rp", "rr", "rv", "sb", "sr", "sv", "tb", "tc", "tc1",
    "tc2", "tc3", "tc4", "tc5", "tc6", "tc7", "tc8", "tc9", "uj",
    "ul", "xe", "xq", "xr", "xw", "xl", "xx"]

type
  WordStarSource* = object
    document*: VextFlowDocument
    hasHeader*: bool
    versionByte*: byte
    driverName*: string
    styleLibraryOffset*: int
    contentOffset*, contentEnd*: int
    hardReturns*, softReturns*, softSpaces*: int
    highBitBytes*, formattingControls*: int
    retainedControls*, dotCommands*: int
    eofPaddingBytes*: int

proc sourceRange(offset, length: int): VextSourceRange =
  VextSourceRange(present: true, offset: offset, length: length)

proc bytes(data: openArray[byte], first, past: int): seq[byte] =
  @data[first ..< past]

proc controlName(code: byte): string =
  case code
  of 0x00: "fix-print-position"
  of 0x01: "alternate-font"
  of 0x03: "print-pause"
  of 0x04: "double-strike"
  of 0x05: "custom-print-e"
  of 0x06: "phantom-space"
  of 0x07: "phantom-rubout"
  of 0x08: "overprint"
  of 0x0b: "index-or-header-suppression"
  of 0x0e: "normal-character-width"
  of 0x10: "reserved-10"
  of 0x11: "custom-print-q"
  of 0x12: "custom-print-r"
  of 0x15: "reserved-15"
  of 0x17: "custom-print-w"
  of 0x1b: "escape"
  of 0x1c: "reserved-1c"
  else: "control-" & code.toHex(2).toLowerAscii

proc sameStyle(left, right: VextCharacterStyle): bool = left == right

proc addText(content: var seq[VextDocumentInline], value: char,
    style: VextCharacterStyle, offset: int) =
  if content.len > 0 and content[^1].kind == vdikText and
      content[^1].style.sameStyle(style) and content[^1].source.present and
      content[^1].source.offset + content[^1].source.length == offset:
    content[^1].text.add value
    inc content[^1].source.length
  else:
    content.add VextDocumentInline(kind: vdikText, text: $value,
      style: style, source: sourceRange(offset, 1))

proc addInlineControl(content: var seq[VextDocumentInline], name,
    description: string, rawData: seq[byte], offset, length: int) =
  content.add VextDocumentInline(kind: vdikRetainedControl,
    source: sourceRange(offset, length), control: VextDocumentControl(
      name: "wordstar." & name, description: description, rawData: rawData))

proc addBlockControl(document: var VextFlowDocument, name, description: string,
    rawData: seq[byte], offset, length: int, argument = "",
    interpreted = false) =
  document.blocks.add VextDocumentBlock(kind: vdbkRetainedControl,
    source: sourceRange(offset, length), blockControl: VextDocumentControl(
      name: "wordstar." & name, description: description, argument: argument,
      interpreted: interpreted, rawData: rawData))

proc decodeAsciiLine(data: openArray[byte], first, past: int): string =
  for position in first ..< past:
    let value = data[position] and 0x7f
    if value >= 0x20 and value <= 0x7e: result.add char(value)
    else: result.add '?'

proc dotCommandName(line: string): string =
  if line.len < 2 or line[0] != '.': return
  if line[1] == '.': return "ig"
  let commandText = line[1 .. ^1].toLowerAscii
  for candidate in KnownWordStarDotCommands:
    if commandText.startsWith(candidate) and candidate.len > result.len:
      let past = candidate.len
      let attached = if past < commandText.len:
          commandText[past .. ^1].strip else: ""
      if past == commandText.len or candidate[^1] in {'0' .. '9', '#'} or
          commandText[past] notin {'a' .. 'z', '#'} or
          attached in ["on", "off", "dis", "c", "r"] or candidate == "rr":
        result = candidate

proc dotCommandArgument(line, name: string): string =
  if name == "ig":
    return if line.len > 2: line[2 .. ^1].strip else: ""
  let first = 1 + name.len
  if first < line.len: line[first .. ^1].strip else: ""

proc parseMargin(argument: string, physical: var Option[int],
    columns: var Option[int]): bool =
  let value = argument.strip.toLowerAscii
  if value.len == 0: return false
  try:
    if value.endsWith("pt"):
      physical = some(int(round(parseFloat(value[0 ..< value.len - 2]) * 1000)))
      columns = none(int)
    elif value.endsWith("\"") or value.endsWith("i"):
      physical = some(int(round(parseFloat(value[0 ..< value.len - 1]) * 72000)))
      columns = none(int)
    else:
      columns = some(parseInt(value))
      physical = none(int)
    result = physical.get(0) >= 0 and columns.get(0) >= 0
  except ValueError:
    discard

proc applyDotCommand(name, argument: string,
    style: var VextParagraphStyle): bool =
  let setting = argument.strip.toLowerAscii
  case name
  of "lm": result = parseMargin(argument, style.leftIndentMillipoints,
      style.leftMarginColumns)
  of "rm": result = parseMargin(argument, style.rightIndentMillipoints,
      style.rightMarginColumns)
  of "oj":
    case setting
    of "on": style.alignment = vpaJustified; result = true
    of "off": style.alignment = vpaLeft; result = true
    of "c": style.alignment = vpaCentred; result = true
    of "r": style.alignment = vpaRight; result = true
    else: discard
  of "uj":
    case setting
    of "on": style.justificationMethod = vjmMicrospacing; result = true
    of "off": style.justificationMethod = vjmWordSpacing; result = true
    of "dis": style.justificationMethod = vjmDeviceDefined; result = true
    else: discard
  else: discard

proc symmetricalEnd(data: openArray[byte], position, limit: int): int =
  if position > limit - 6:
    raise newException(ValueError, "truncated WordStar symmetrical sequence at " &
      $position)
  let count = int(data[position + 1]) or (int(data[position + 2]) shl 8)
  if count < 4 or count > limit - position - 3:
    raise newException(ValueError,
      "invalid WordStar symmetrical-sequence count at " & $position)
  let trailing = position + count
  if data[trailing] != data[position + 1] or
      data[trailing + 1] != data[position + 2] or
      data[trailing + 2] != 0x1d:
    raise newException(ValueError,
      "WordStar symmetrical sequence at " & $position &
      " has no matching trailer")
  trailing + 3

proc parseHeader(data: openArray[byte], source: var WordStarSource) =
  if data.len < 128 or data[0] != 0x1d or data[1] != 0x7d or
      data[2] != 0 or data[3] != 0:
    return
  if symmetricalEnd(data, 0, data.len) != 128:
    raise newException(ValueError, "invalid WordStar header sequence")
  source.hasHeader = true
  source.versionByte = data[4]
  if (source.versionByte shr 4) < 5 or (source.versionByte shr 4) > 9 or
      (source.versionByte and 0x0f) > 9:
    raise newException(ValueError, "unsupported WordStar header version")
  for position in 5 .. 13:
    if data[position] == 0: break
    if data[position] < 0x20 or data[position] > 0x7e:
      raise newException(ValueError, "invalid WordStar printer-driver name")
    source.driverName.add char(data[position])
  source.styleLibraryOffset = int(data[16]) or (int(data[17]) shl 8) or
    (int(data[18]) shl 16) or (int(data[19]) shl 24)
  if source.styleLibraryOffset != 0 and
      (source.styleLibraryOffset < 128 or
       source.styleLibraryOffset > data.len or
       source.styleLibraryOffset mod 128 != 0):
    raise newException(ValueError, "invalid WordStar style-library offset")
  source.contentOffset = 128
  source.contentEnd = if source.styleLibraryOffset > 0:
      source.styleLibraryOffset else: data.len

proc flushParagraph(document: var VextFlowDocument,
    content: var seq[VextDocumentInline], paragraphStart: var int,
    past: int, style: VextParagraphStyle, evenWhenEmpty = true) =
  if evenWhenEmpty or content.len > 0:
    document.blocks.add VextDocumentBlock(kind: vdbkParagraph,
      source: sourceRange(paragraphStart, max(0, past - paragraphStart)),
      paragraphStyle: style,
      content: move(content))
    content = @[]
  paragraphStart = past

proc parseWordStar*(data: openArray[byte]): WordStarSource =
  if data.len == 0: raise newException(ValueError, "empty WordStar document")
  if data.len > WordStarMaximumBytes:
    raise newException(ValueError, "WordStar document exceeds the size limit")
  result.contentEnd = data.len
  parseHeader(data, result)

  let parsingLimit = result.contentEnd
  var position = result.contentOffset
  var lineStart = true
  var content: seq[VextDocumentInline]
  var paragraphStart = position
  var style: VextCharacterStyle
  var paragraphStyle: VextParagraphStyle

  while position < parsingLimit:
    let raw = data[position]
    if raw == 0x1a:
      result.contentEnd = position
      var padding = position
      while padding < parsingLimit and data[padding] == 0x1a:
        inc padding
      if not result.hasHeader and padding != parsingLimit:
        raise newException(ValueError,
          "headerless WordStar EOF marker is followed by non-padding data")
      result.eofPaddingBytes = padding - position
      break

    if lineStart and raw == byte('.'):
      var lineEnd = position
      while lineEnd < result.contentEnd:
        if data[lineEnd] == 0x1d:
          lineEnd = symmetricalEnd(data, lineEnd, result.contentEnd)
        elif data[lineEnd] == 0x1b and lineEnd <= result.contentEnd - 3 and
            data[lineEnd + 2] == 0x1c:
          lineEnd += 3
        elif (data[lineEnd] and 0x7f) in [0x0a'u8, 0x0d'u8]:
          break
        else:
          inc lineEnd
      var past = lineEnd
      if past < result.contentEnd and (data[past] and 0x7f) == 0x0d: inc past
      if past < result.contentEnd and (data[past] and 0x7f) == 0x0a: inc past
      let line = decodeAsciiLine(data, position, lineEnd)
      let command = dotCommandName(line)
      if command.len > 0:
        flushParagraph(result.document, content, paragraphStart,
          position, paragraphStyle, false)
        inc result.dotCommands
        if command == "pa":
          result.document.blocks.add VextDocumentBlock(kind: vdbkPageBreak,
            source: sourceRange(position, past - position))
        else:
          let argument = dotCommandArgument(line, command)
          let interpreted = applyDotCommand(command, argument, paragraphStyle)
          result.document.addBlockControl("dot." & command,
            "WordStar dot command: " & line,
            data.bytes(position, past), position, past - position, argument,
            interpreted)
          inc result.retainedControls
        position = past
        paragraphStart = position
        lineStart = true
        continue

    if raw == 0x1d:
      let past = symmetricalEnd(data, position, result.contentEnd)
      let sequenceType = data[position + 3]
      content.addInlineControl("sequence." &
        sequenceType.toHex(2).toLowerAscii,
        "WordStar symmetrical sequence type " & sequenceType.toHex(2),
        data.bytes(position, past), position, past - position)
      inc result.retainedControls
      position = past
      lineStart = false
      continue

    if raw == 0x1b and position <= result.contentEnd - 3 and
        data[position + 2] == 0x1c:
      content.addInlineControl("extended-character",
        "WordStar extended character with an unresolved character mapping",
        data.bytes(position, position + 3), position, 3)
      inc result.retainedControls
      position += 3
      lineStart = false
      continue

    if raw >= 0x80: inc result.highBitBytes
    if raw == 0x8d:
      if position + 1 >= result.contentEnd or
          (data[position + 1] and 0x7f) != 0x0a:
        raise newException(ValueError, "WordStar soft return has no line feed")
      content.add VextDocumentInline(kind: vdikSoftLineBreak,
        source: sourceRange(position, 2))
      inc result.softReturns
      position += 2
      lineStart = true
      continue
    if raw == 0xa0:
      content.add VextDocumentInline(kind: vdikSoftSpace,
        source: sourceRange(position, 1))
      inc result.softSpaces
      inc position
      lineStart = false
      continue

    let value = raw and 0x7f
    case value
    of 0x02, 0x13, 0x14, 0x16, 0x18, 0x19:
      case value
      of 0x02: style.bold = not style.bold
      of 0x13: style.underline = not style.underline
      of 0x14:
        style.position = if style.position == vtpSuperscript:
            vtpNormal else: vtpSuperscript
      of 0x16:
        style.position = if style.position == vtpSubscript:
            vtpNormal else: vtpSubscript
      of 0x18: style.strikeout = not style.strikeout
      of 0x19: style.italic = not style.italic
      else: discard
      inc result.formattingControls
      inc position
      lineStart = false
    of 0x09:
      content.add VextDocumentInline(kind: vdikTab,
        source: sourceRange(position, 1))
      inc position
      lineStart = false
    of 0x0a:
      content.add VextDocumentInline(kind: vdikLineBreak,
        source: sourceRange(position, 1))
      inc position
      lineStart = true
    of 0x0c:
      flushParagraph(result.document, content, paragraphStart,
        position, paragraphStyle, false)
      result.document.blocks.add VextDocumentBlock(kind: vdbkPageBreak,
        source: sourceRange(position, 1))
      inc position
      paragraphStart = position
      lineStart = true
    of 0x0d:
      var past = position + 1
      if past < result.contentEnd and (data[past] and 0x7f) == 0x0a:
        inc past
      flushParagraph(result.document, content, paragraphStart, past,
        paragraphStyle)
      inc result.hardReturns
      position = past
      lineStart = true
    of 0x0f:
      content.add VextDocumentInline(kind: vdikBindingSpace,
        source: sourceRange(position, 1))
      inc position
      lineStart = false
    of 0x1e, 0x1f:
      content.add VextDocumentInline(kind: vdikDiscretionaryHyphen,
        source: sourceRange(position, 1), active: value == 0x1f)
      inc position
      lineStart = false
    of 0x20 .. 0x7e:
      content.addText(char(value), style, position)
      inc position
      lineStart = false
    else:
      content.addInlineControl(controlName(value),
        "WordStar control code " & value.toHex(2), @[raw], position, 1)
      inc result.retainedControls
      inc position
      lineStart = false

  flushParagraph(result.document, content, paragraphStart,
    result.contentEnd, paragraphStyle, false)
  if not result.hasHeader and result.hardReturns + result.softReturns == 0:
    raise newException(ValueError,
      "headerless WordStar document has no validated return structure")
  if not result.hasHeader and result.highBitBytes == 0 and
      result.formattingControls == 0 and result.softReturns == 0 and
      result.softSpaces == 0 and result.dotCommands == 0:
    raise newException(ValueError,
      "headerless text has no WordStar-specific structure")
  if not result.hasHeader and result.retainedControls * 2 >
      max(1, result.contentEnd - result.contentOffset):
    raise newException(ValueError,
      "headerless stream contains too little recoverable WordStar text")
  result.document.validate

proc isWordStar*(data: openArray[byte]): bool =
  try:
    discard parseWordStar(data)
    true
  except ValueError:
    false

proc hasWordStarExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in
    [".ws", ".ws2", ".ws3", ".ws4", ".ws5", ".ws6", ".ws7", ".ws8",
     ".ws9", ".wsd"]

proc versionName*(source: WordStarSource): string =
  if not source.hasHeader: "headerless"
  elif (source.versionByte and 0x0f) == 0:
    $(source.versionByte shr 4) & ".0"
  else:
    $(source.versionByte shr 4) & "." & $(source.versionByte and 0x0f)
