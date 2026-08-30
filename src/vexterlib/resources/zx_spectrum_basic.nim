## Text reconstruction for tokenised 48K ZX Spectrum BASIC listings.

import std/strutils

const
  ZxSpectrumBasicTypeId* = "zx-spectrum.basic"
  ZxSpectrumBasicResourcePath* = "/listing"

  BasicTokens: array[0xa5'u8 .. 0xff'u8, string] = [
    "RND", "INKEY$", "PI", "FN", "POINT", "SCREEN$", "ATTR", "AT",
    "TAB", "VAL$", "CODE", "VAL", "LEN", "SIN", "COS", "TAN", "ASN",
    "ACS", "ATN", "LN", "EXP", "INT", "SQR", "SGN", "ABS", "PEEK",
    "IN", "USR", "STR$", "CHR$", "NOT", "BIN", "OR", "AND", "<=",
    ">=", "<>", "LINE", "THEN", "TO", "STEP", "DEF FN", "CAT",
    "FORMAT", "MOVE", "ERASE", "OPEN #", "CLOSE #", "MERGE", "VERIFY",
    "BEEP", "CIRCLE", "INK", "PAPER", "FLASH", "BRIGHT", "INVERSE",
    "OVER", "OUT", "LPRINT", "LLIST", "STOP", "READ", "DATA",
    "RESTORE", "NEW", "BORDER", "CONTINUE", "DIM", "REM", "FOR",
    "GO TO", "GO SUB", "INPUT", "LOAD", "LIST", "LET", "PAUSE", "NEXT",
    "POKE", "PRINT", "PLOT", "RUN", "SAVE", "RANDOMIZE", "IF", "CLS",
    "DRAW", "CLEAR", "RETURN", "COPY"]

  # Spectrum block graphics encode TR, TL, BR and BL as bits 0 through 3.
  BlockGraphics: array[0x80'u8 .. 0x8f'u8, string] = [
    " ", "▝", "▘", "▀", "▗", "▐", "▚", "▜",
    "▖", "▞", "▌", "▛", "▄", "▟", "▙", "█"]

type
  DecodeNotes = object
    hasUdg: bool
    hasControls: bool
    hasUnknown: bool

proc littleEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc bigEndianWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc hexByte(value: byte): string =
  "$" & toHex(int(value), 2)

proc annotation(name: string, values: openArray[byte]): string =
  result = "⟦" & name
  for value in values:
    result.add " " & $value
  result.add "⟧"

proc decodeBody(data: openArray[byte], notes: var DecodeNotes): string =
  var
    index = 0
    insideQuote = false
    lastWasNumber = false

  while index < data.len:
    let value = data[index]
    if value == 0x0d'u8 and index == data.high:
      break
    if value >= 0xa5'u8:
      if result.len > 0 and result[^1] != ' ' and
          (result[^1].isAlphaNumeric or result[^1] in {')', ':', ';'}):
        result.add ' '
      result.add BasicTokens[value]
      if value > 0xa7'u8:
        result.add ' '
      lastWasNumber = false
      inc index
    elif value >= 0x80'u8 and value <= 0x8f'u8:
      result.add BlockGraphics[value]
      lastWasNumber = false
      inc index
    elif value >= 0x90'u8 and value <= 0xa4'u8:
      result.add "⟦UDG " & char(ord('A') + int(value) - 0x90) & "⟧"
      notes.hasUdg = true
      lastWasNumber = false
      inc index
    elif value == 0x0e'u8 and lastWasNumber and not insideQuote and
        index + 5 < data.len:
      # The textual digits are followed by a marker and five-byte calculator
      # representation; only the textual spelling belongs in the listing.
      index += 6
    elif value in {0x10'u8 .. 0x15'u8} and index + 1 < data.high:
      const names = ["INK", "PAPER", "FLASH", "BRIGHT", "INVERSE", "OVER"]
      result.add annotation(names[int(value) - 0x10], [data[index + 1]])
      notes.hasControls = true
      lastWasNumber = false
      index += 2
    elif value == 0x16'u8 and index + 2 < data.high:
      result.add annotation("AT", [data[index + 1], data[index + 2]])
      notes.hasControls = true
      lastWasNumber = false
      index += 3
    elif value == 0x17'u8 and index + 1 < data.high:
      result.add annotation("TAB", [data[index + 1]])
      notes.hasControls = true
      lastWasNumber = false
      index += 2
    elif value >= 32'u8 and value <= 127'u8:
      result.add char(value)
      if value == byte('"'):
        insideQuote = not insideQuote
      lastWasNumber = value >= byte('0') and value <= byte('9')
      inc index
    else:
      result.add "⟦ZX:" & hexByte(value) & "⟧"
      notes.hasUnknown = true
      lastWasNumber = false
      inc index

  result = result.strip(leading = true, trailing = true)

proc decodeZxSpectrumBasic*(data: openArray[byte]): string =
  ## Decodes consecutive Spectrum BASIC line records. The input begins with a
  ## big-endian line number and ends when the next bytes are not a valid line.
  var
    offset = 0
    lines: seq[string]
    notes: DecodeNotes

  while offset + 4 <= data.len:
    let
      lineNumber = bigEndianWord(data, offset)
      lineLength = littleEndianWord(data, offset + 2)
      bodyStart = offset + 4
      bodyEnd = bodyStart + lineLength
    if lineNumber >= 32768:
      break
    if lineLength < 1 or bodyEnd > data.len or data[bodyEnd - 1] != 0x0d'u8:
      if lines.len == 0:
        raise newException(ValueError, "invalid ZX Spectrum BASIC line")
      break
    lines.add align($lineNumber, 3) & " " & decodeBody(data.toOpenArray(bodyStart,
      bodyEnd - 1), notes)
    offset = bodyEnd

  if lines.len == 0:
    raise newException(ValueError, "ZX Spectrum BASIC listing contains no lines")

  var preamble: seq[string]
  if notes.hasUdg:
    preamble.add "REM VEXTER: ⟦UDG A⟧ through ⟦UDG U⟧ denote runtime-defined characters."
  if notes.hasControls:
    preamble.add "REM VEXTER: ⟦INK n⟧ and similar markers preserve parameterised display controls."
  if notes.hasUnknown:
    preamble.add "REM VEXTER: ⟦ZX:$HH⟧ preserves an unrecognised source byte."
  result = (preamble & lines).join("\n")
