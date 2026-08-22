## Structural parsing for classic Amiga bitmap diskfont descriptor files.

import std/strutils
import ./amiga_hunk_executable

const
  AmigaDiskfontTypeId* = "amiga.bitmap-diskfont"
  AmigaDiskfontIndexTypeId* = "amiga.bitmap-diskfont-index"
  DfhId = 0x0f80
  FchId = 0x0f00
  TfchId = 0x0f02
  FsfColorFont* = 0x40
  TaDeviceDpi* = 0x80000001'u32

type
  AmigaDiskfontTag* = object
    identifier*: uint32
    value*: uint32

  AmigaDiskfontIndexEntry* = object
    filename*: string
    ySize*, style*, flags*: int
    tags*: seq[AmigaDiskfontTag]

  AmigaDiskfontIndex* = object
    tagged*: bool
    entries*: seq[AmigaDiskfontIndexEntry]

  AmigaDiskfontGlyphSource* = object
    sourceIndex*: int
    bitOffset*, width*, spacing*, kern*: int

  AmigaDiskfontSource* = object
    name*: string
    revision*, ySize*, style*, flags*, xSize*, baseline*, boldSmear*: int
    lowCharacter*, highCharacter*, modulo*: int
    glyphs*: seq[AmigaDiskfontGlyphSource]
    planes*: seq[seq[byte]]
    colourFlags*, depth*, foregroundColour*, lowColour*, highColour*: int
    planePick*, planeOnOff*: int
    palette*: seq[uint16]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc beLong(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 24) or (int(data[offset + 1]) shl 16) or
    (int(data[offset + 2]) shl 8) or int(data[offset + 3])

proc signedWord(value: int): int {.inline.} =
  if value >= 0x8000: value - 0x10000 else: value

proc nulTerminated(data: openArray[byte], offset, maximum: int): string =
  for index in 0 ..< maximum:
    let value = data[offset + index]
    if value == 0: break
    result.add char(value)

proc parseAmigaDiskfontIndex*(data: openArray[byte]): AmigaDiskfontIndex =
  if data.len < 4:
    raise newException(ValueError, "Amiga diskfont index is truncated")
  let identifier = data.beWord(0)
  if identifier notin [FchId, TfchId]:
    raise newException(ValueError, "Amiga bitmap diskfont index ID was not found")
  result.tagged = identifier == TfchId
  let count = data.beWord(2)
  if count <= 0 or count > (high(int) - 4) div 260 or
      data.len != 4 + count * 260:
    raise newException(ValueError, "Amiga diskfont index has an invalid entry count")
  for index in 0 ..< count:
    let offset = 4 + index * 260
    let filenameLength = if result.tagged: 254 else: 256
    var entry = AmigaDiskfontIndexEntry(
      filename: data.nulTerminated(offset, filenameLength),
      ySize: data.beWord(offset + 256),
      style: int(data[offset + 258]), flags: int(data[offset + 259]))
    if entry.filename.len == 0 or entry.ySize <= 0:
      raise newException(ValueError, "Amiga diskfont index entry is invalid")
    if result.tagged:
      let tagCount = data.beWord(offset + 254)
      if tagCount * 8 > 254:
        raise newException(ValueError, "Amiga diskfont index tag list is too large")
      let tagOffset = offset + 254 - tagCount * 8
      for tagIndex in 0 ..< tagCount:
        entry.tags.add AmigaDiskfontTag(
          identifier: uint32(data.beLong(tagOffset + tagIndex * 8)),
          value: uint32(data.beLong(tagOffset + tagIndex * 8 + 4)))
    result.entries.add entry

proc isAmigaDiskfontIndex*(data: openArray[byte]): bool =
  try: discard parseAmigaDiskfontIndex(data); true
  except ValueError: false

proc requireRange(data: openArray[byte], offset, length: int, label: string) =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "Amiga diskfont " & label & " is out of bounds")

proc pointer(data: openArray[byte], fieldOffset: int, length: int,
    label: string): int =
  data.requireRange(fieldOffset, 4, label & " pointer")
  result = data.beLong(fieldOffset)
  data.requireRange(result, length, label)

proc copyRange(data: openArray[byte], offset, length: int): seq[byte] =
  if length > 0:
    result.add data.toOpenArray(offset, offset + length - 1)

proc parseAmigaDiskfont*(data: openArray[byte]): AmigaDiskfontSource =
  let executable = parseAmigaHunkExecutable(data)
  if executable.hunks.len != 1 or executable.hunks[0].kind == ahkBss:
    raise newException(ValueError,
      "Amiga diskfont must contain one initialized loadable hunk")
  var payload = executable.hunks[0].data
  payload.setLen(executable.hunks[0].memoryLongwords * 4)
  # The loader supplies dfh_NextSegment immediately before this hunk. Only
  # the four-byte ReturnCode precedes the serialized DiskFontHeader.
  const diskHeader = 4
  const textFont = diskHeader + 54
  payload.requireRange(textFont, 52, "TextFont header")
  if payload.beWord(diskHeader + 14) != DfhId:
    raise newException(ValueError, "Amiga diskfont DFH_ID was not found")
  result.revision = payload.beWord(diskHeader + 16)
  for index in 0 ..< 32:
    let value = payload[diskHeader + 22 + index]
    if value == 0: break
    result.name.add char(value)
  result.name = result.name.strip(trailing = true)
  result.ySize = payload.beWord(textFont + 20)
  result.style = int(payload[textFont + 22])
  result.flags = int(payload[textFont + 23])
  result.xSize = payload.beWord(textFont + 24)
  result.baseline = payload.beWord(textFont + 26)
  result.boldSmear = payload.beWord(textFont + 28)
  result.lowCharacter = int(payload[textFont + 32])
  result.highCharacter = int(payload[textFont + 33])
  result.modulo = payload.beWord(textFont + 38)
  if result.ySize <= 0 or result.baseline >= result.ySize or
      result.highCharacter < result.lowCharacter or result.modulo <= 0:
    raise newException(ValueError, "Amiga diskfont has invalid font metrics")
  let glyphCount = result.highCharacter - result.lowCharacter + 2
  let mappedGlyphCount = glyphCount - 1
  let location = payload.pointer(textFont + 40, glyphCount * 4,
    "character-location table")
  let spacingPointer = payload.beLong(textFont + 44)
  let kernPointer = payload.beLong(textFont + 48)
  if spacingPointer != 0:
    payload.requireRange(spacingPointer, mappedGlyphCount * 2, "spacing table")
  if kernPointer != 0:
    payload.requireRange(kernPointer, mappedGlyphCount * 2, "kerning table")
  for index in 0 ..< glyphCount:
    result.glyphs.add AmigaDiskfontGlyphSource(
      sourceIndex: result.lowCharacter + index,
      bitOffset: payload.beWord(location + index * 4),
      width: payload.beWord(location + index * 4 + 2),
      spacing: if spacingPointer == 0 or
          spacingPointer > payload.len - (index + 1) * 2: result.xSize else:
        signedWord(payload.beWord(spacingPointer + index * 2)),
      kern: if kernPointer == 0 or
          kernPointer > payload.len - (index + 1) * 2: 0 else:
        signedWord(payload.beWord(kernPointer + index * 2)))
  let planeLength = result.modulo * result.ySize
  if (result.style and FsfColorFont) == 0:
    let plane = payload.pointer(textFont + 34, planeLength, "character bitmap")
    result.depth = 1
    result.planePick = 1
    result.planes.add payload.copyRange(plane, planeLength)
  else:
    const colourTextFont = textFont + 52
    payload.requireRange(colourTextFont, 44, "ColorTextFont extension")
    result.colourFlags = payload.beWord(colourTextFont)
    result.depth = int(payload[colourTextFont + 2])
    result.foregroundColour = int(payload[colourTextFont + 3])
    result.lowColour = int(payload[colourTextFont + 4])
    result.highColour = int(payload[colourTextFont + 5])
    result.planePick = int(payload[colourTextFont + 6])
    result.planeOnOff = int(payload[colourTextFont + 7])
    if result.depth <= 0 or result.depth > 8:
      raise newException(ValueError, "Amiga ColorFont has invalid bitplane depth")
    let colours = payload.pointer(colourTextFont + 8, 8, "colour descriptor")
    let colourCount = payload.beWord(colours + 2)
    let table = payload.pointer(colours + 4, colourCount * 2, "colour table")
    for index in 0 ..< colourCount:
      result.palette.add uint16(payload.beWord(table + index * 2))
    for index in 0 ..< result.depth:
      let plane = payload.pointer(colourTextFont + 12 + index * 4,
        planeLength, "colour bitplane")
      result.planes.add payload.copyRange(plane, planeLength)
  for glyph in result.glyphs:
    if glyph.width < 0 or glyph.bitOffset + glyph.width > result.modulo * 8:
      raise newException(ValueError, "Amiga diskfont glyph exceeds its strike bitmap")

proc isAmigaDiskfont*(data: openArray[byte]): bool =
  try: discard parseAmigaDiskfont(data); true
  except ValueError: false
