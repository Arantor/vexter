## Structural parsing for the FZX v1.0 compact bitmap-font format.

import std/[os, strutils]

const FzxTypeId* = "zx-spectrum.fzx-font"

type
  FzxGlyphSource* = object
    characterCode*: int
    kern*, shift*, width*, rowCount*: int
    bitmap*: seq[byte]

  FzxFontSource* = object
    height*, tracking*, lastCharacter*: int
    glyphs*: seq[FzxGlyphSource]

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc parseFzx*(data: openArray[byte]): FzxFontSource =
  if data.len < 8:
    raise newException(ValueError, "FZX font is shorter than its header and table")
  result.height = int(data[0])
  result.tracking = int(data[1])
  result.lastCharacter = int(data[2])
  if result.height == 0:
    raise newException(ValueError, "FZX baseline spacing must be positive")
  if result.lastCharacter < 32:
    raise newException(ValueError, "FZX last character must be at least 32")
  let glyphCount = result.lastCharacter - 31
  let tableEnd = 3 + glyphCount * 3 + 2
  if tableEnd > data.len:
    raise newException(ValueError, "truncated FZX character table")

  var starts = newSeq[int](glyphCount + 1)
  for index in 0 ..< glyphCount:
    let entryOffset = 3 + index * 3
    let packedOffset = leWord(data, entryOffset)
    starts[index] = entryOffset + (packedOffset and 0x3fff)
    if starts[index] < tableEnd or starts[index] > data.len:
      raise newException(ValueError,
        "FZX character definition points outside the bitmap area")
  let terminalOffset = 3 + glyphCount * 3
  starts[^1] = terminalOffset + leWord(data, terminalOffset)
  if starts[^1] != data.len:
    raise newException(ValueError,
      "FZX terminal offset does not end at the end of the font")
  for index in 0 ..< glyphCount:
    if starts[index + 1] < starts[index]:
      raise newException(ValueError,
        "FZX character definitions are not in table order")
    let entryOffset = 3 + index * 3
    let packedOffset = leWord(data, entryOffset)
    let dimensions = int(data[entryOffset + 2])
    let width = (dimensions and 0x0f) + 1
    let shift = dimensions shr 4
    let rowBytes = if width <= 8: 1 else: 2
    let byteLength = starts[index + 1] - starts[index]
    if byteLength mod rowBytes != 0:
      raise newException(ValueError,
        "FZX character bitmap is not a whole number of rows")
    let rows = byteLength div rowBytes
    if shift + rows > 192:
      raise newException(ValueError,
        "FZX character exceeds the 192-pixel height limit")
    var glyph = FzxGlyphSource(characterCode: index + 32,
      kern: packedOffset shr 14, shift: shift, width: width,
      rowCount: rows)
    if byteLength > 0:
      glyph.bitmap.add data.toOpenArray(starts[index], starts[index + 1] - 1)
    result.glyphs.add glyph

proc isFzx*(data: openArray[byte]): bool =
  try: discard parseFzx(data); true
  except ValueError: false

proc hasFzxExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".fzx"
