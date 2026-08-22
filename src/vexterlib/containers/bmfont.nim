## AngelCode BMFont descriptor identification and text-format parsing.

import std/[parseutils, strutils]

const BmFontTypeId* = "bitmap-font.bmfont"

type
  BmFontEncoding* = enum
    bfeText
    bfeXml
    bfeBinary

  BmFontPage* = object
    id*: int
    filename*: string

  BmFontCharacter* = object
    id*, x*, y*, width*, height*: int
    xOffset*, yOffset*, xAdvance*, page*, channel*: int

  BmFontKerningPair* = object
    first*, second*, amount*: int

  BmFontSource* = object
    encoding*: BmFontEncoding
    rawData*: seq[byte]
    face*: string
    charset*: string
    size*, lineHeight*, baseline*, scaleWidth*, scaleHeight*: int
    bold*, italic*, unicode*, smooth*, antialias*, stretchHeight*: int
    padding*: array[4, int]
    spacing*: array[2, int]
    outline*, packed*: int
    alphaChannel*, redChannel*, greenChannel*, blueChannel*: int
    declaredPages*, declaredCharacters*, declaredKernings*: int
    pages*: seq[BmFontPage]
    characters*: seq[BmFontCharacter]
    kernings*: seq[BmFontKerningPair]

proc bytesText(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc littleWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc littleLong(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc signedWord(data: openArray[byte], offset: int): int {.inline.} =
  let value = data.littleWord(offset)
  if value >= 0x8000: value - 0x10000 else: value

proc validateSource(source: BmFontSource) =
  if source.lineHeight <= 0 or source.baseline < 0 or
      source.scaleWidth <= 0 or source.scaleHeight <= 0 or
      source.declaredPages <= 0 or source.pages.len != source.declaredPages or
      source.declaredCharacters < 0 or source.declaredKernings < 0:
    raise newException(ValueError, "BMFont descriptor is inconsistent")
  if source.bold notin 0 .. 1 or source.italic notin 0 .. 1 or
      source.unicode notin 0 .. 1 or source.smooth notin 0 .. 1 or
      source.antialias < 0 or source.packed notin 0 .. 1 or
      source.stretchHeight <= 0 or source.outline < 0 or
      source.alphaChannel notin 0 .. 4 or source.redChannel notin 0 .. 4 or
      source.greenChannel notin 0 .. 4 or source.blueChannel notin 0 .. 4:
    raise newException(ValueError, "BMFont style or channel metadata is invalid")
  for value in source.padding:
    if value < 0: raise newException(ValueError, "BMFont padding is invalid")
  for value in source.spacing:
    if value < 0: raise newException(ValueError, "BMFont spacing is invalid")
  var pageIds: seq[int]
  for page in source.pages:
    if page.id < 0 or page.id >= source.declaredPages or
        page.id in pageIds or page.filename.len == 0:
      raise newException(ValueError, "BMFont page table is invalid")
    pageIds.add page.id
  for character in source.characters:
    if character.id < 0 or character.id > 0x10ffff or
        character.id in 0xd800 .. 0xdfff or character.page notin pageIds or
        character.x < 0 or character.y < 0 or character.width < 0 or
        character.height < 0 or
        character.x > source.scaleWidth - character.width or
        character.y > source.scaleHeight - character.height:
      raise newException(ValueError, "BMFont character record is invalid")

proc fields(line: string): seq[(string, string)] =
  var offset = 0
  while offset < line.len and line[offset] != ' ': inc offset
  while offset < line.len:
    while offset < line.len and line[offset] == ' ': inc offset
    if offset >= line.len: break
    let keyStart = offset
    while offset < line.len and line[offset] notin {'=', ' '}: inc offset
    if offset >= line.len or line[offset] != '=':
      raise newException(ValueError, "invalid BMFont text field")
    let key = line[keyStart ..< offset]
    inc offset
    # Some generators append a diagnostic letter="..." value without
    # escaping quote or backslash glyphs. It is redundant with char.id and is
    # deliberately ignored after all normative character fields.
    if key == "letter": break
    var value: string
    if offset < line.len and line[offset] == '"':
      inc offset
      while offset < line.len and line[offset] != '"':
        if line[offset] == '\\' and offset + 1 < line.len:
          inc offset
        value.add line[offset]
        inc offset
      if offset >= line.len:
        raise newException(ValueError, "unterminated BMFont quoted field")
      inc offset
    else:
      let valueStart = offset
      while offset < line.len and line[offset] != ' ': inc offset
      value = line[valueStart ..< offset]
    result.add (key, value)

proc value(items: openArray[(string, string)], key: string,
    required = true): string =
  for item in items:
    if item[0] == key: return item[1]
  if required: raise newException(ValueError, "BMFont field is missing: " & key)

proc number(items: openArray[(string, string)], key: string,
    required = true): int =
  let text = items.value(key, required)
  if not required and text.len == 0: return 0
  if text.parseInt(result) != text.len:
    raise newException(ValueError, "BMFont integer field is invalid: " & key)

proc numbers(items: openArray[(string, string)], key: string,
    count: int, required = true): seq[int] =
  let text = items.value(key, required)
  if not required and text.len == 0: return newSeq[int](count)
  let parts = text.split(',')
  if parts.len != count:
    raise newException(ValueError, "BMFont tuple field has the wrong length: " & key)
  for part in parts:
    var parsed: int
    if part.parseInt(parsed) != part.len:
      raise newException(ValueError, "BMFont tuple field is invalid: " & key)
    result.add parsed

proc parseBmFontText(data: openArray[byte]): BmFontSource =
  result.encoding = bfeText
  var sawInfo, sawCommon, sawChars: bool
  for rawLine in data.bytesText.splitLines:
    let line = rawLine.strip
    if line.len == 0: continue
    let items = line.fields
    if line.startsWith("info "):
      if sawInfo: raise newException(ValueError, "duplicate BMFont info record")
      sawInfo = true
      result.face = items.value("face")
      result.size = items.number("size")
      result.bold = items.number("bold", false)
      result.italic = items.number("italic", false)
      result.charset = items.value("charset", false)
      result.unicode = items.number("unicode", false)
      result.stretchHeight = items.number("stretchH", false)
      if result.stretchHeight == 0: result.stretchHeight = 100
      result.smooth = items.number("smooth", false)
      result.antialias = items.number("aa", false)
      let padding = items.numbers("padding", 4, false)
      for index, value in padding: result.padding[index] = value
      let spacing = items.numbers("spacing", 2, false)
      for index, value in spacing: result.spacing[index] = value
      result.outline = items.number("outline", false)
    elif line.startsWith("common "):
      if sawCommon: raise newException(ValueError, "duplicate BMFont common record")
      sawCommon = true
      result.lineHeight = items.number("lineHeight")
      result.baseline = items.number("base")
      result.scaleWidth = items.number("scaleW")
      result.scaleHeight = items.number("scaleH")
      result.declaredPages = items.number("pages")
      result.packed = items.number("packed", false)
      result.alphaChannel = items.number("alphaChnl", false)
      result.redChannel = items.number("redChnl", false)
      result.greenChannel = items.number("greenChnl", false)
      result.blueChannel = items.number("blueChnl", false)
    elif line.startsWith("page "):
      result.pages.add BmFontPage(id: items.number("id"),
        filename: items.value("file"))
    elif line.startsWith("chars "):
      if sawChars: raise newException(ValueError, "duplicate BMFont chars record")
      sawChars = true
      result.declaredCharacters = items.number("count")
    elif line.startsWith("char "):
      result.characters.add BmFontCharacter(id: items.number("id"),
        x: items.number("x"), y: items.number("y"),
        width: items.number("width"), height: items.number("height"),
        xOffset: items.number("xoffset"), yOffset: items.number("yoffset"),
        xAdvance: items.number("xadvance"), page: items.number("page"),
        channel: items.number("chnl", false))
    elif line.startsWith("kernings "):
      result.declaredKernings = items.number("count")
    elif line.startsWith("kerning "):
      result.kernings.add BmFontKerningPair(first: items.number("first"),
        second: items.number("second"), amount: items.number("amount"))
    else:
      raise newException(ValueError, "unsupported BMFont text record")
  if not sawInfo or not sawCommon or not sawChars or result.lineHeight <= 0 or
      result.baseline < 0 or
      result.scaleWidth <= 0 or result.scaleHeight <= 0 or
      result.declaredPages <= 0 or result.pages.len != result.declaredPages or
      result.declaredCharacters < 0 or result.declaredKernings < 0:
    raise newException(ValueError, "BMFont text descriptor is inconsistent")
  result.validateSource

proc parseBmFontBinary(data: openArray[byte]): BmFontSource =
  if data.len < 4 or data[0] != byte('B') or data[1] != byte('M') or
      data[2] != byte('F') or data[3] != 3:
    raise newException(ValueError, "unsupported BMFont binary version")
  result = BmFontSource(encoding: bfeBinary, rawData: @data,
    stretchHeight: 100)
  var offset = 4
  var sawInfo, sawCommon, sawPages, sawCharacters, sawKernings: bool
  while offset < data.len:
    if offset > data.len - 5:
      raise newException(ValueError, "BMFont binary block header is truncated")
    let kind = int(data[offset])
    let sizeValue = data.littleLong(offset + 1)
    if sizeValue > uint32(high(int)):
      raise newException(ValueError, "BMFont binary block is too large")
    let size = int(sizeValue)
    offset += 5
    if size > data.len - offset:
      raise newException(ValueError, "BMFont binary block is truncated")
    let finish = offset + size
    case kind
    of 1:
      if sawInfo or size < 15 or data[finish - 1] != 0:
        raise newException(ValueError, "BMFont binary info block is invalid")
      sawInfo = true
      result.size = data.signedWord(offset)
      let flags = data[offset + 2]
      result.smooth = int((flags shr 7) and 1)
      result.unicode = int((flags shr 6) and 1)
      result.italic = int((flags shr 5) and 1)
      result.bold = int((flags shr 4) and 1)
      result.charset = $int(data[offset + 3])
      result.stretchHeight = data.littleWord(offset + 4)
      result.antialias = int(data[offset + 6])
      for index in 0 .. 3: result.padding[index] = int(data[offset + 7 + index])
      for index in 0 .. 1: result.spacing[index] = int(data[offset + 11 + index])
      result.outline = int(data[offset + 13])
      for index in offset + 14 ..< finish - 1:
        if data[index] == 0:
          raise newException(ValueError, "BMFont binary face name is invalid")
        result.face.add char(data[index])
    of 2:
      if sawCommon or size != 15:
        raise newException(ValueError, "BMFont binary common block is invalid")
      sawCommon = true
      result.lineHeight = data.littleWord(offset)
      result.baseline = data.littleWord(offset + 2)
      result.scaleWidth = data.littleWord(offset + 4)
      result.scaleHeight = data.littleWord(offset + 6)
      result.declaredPages = data.littleWord(offset + 8)
      result.packed = int(data[offset + 10] and 1)
      result.alphaChannel = int(data[offset + 11])
      result.redChannel = int(data[offset + 12])
      result.greenChannel = int(data[offset + 13])
      result.blueChannel = int(data[offset + 14])
    of 3:
      if sawPages or size == 0:
        raise newException(ValueError, "BMFont binary pages block is invalid")
      sawPages = true
      var name: string
      for index in offset ..< finish:
        if data[index] == 0:
          if name.len == 0:
            raise newException(ValueError, "BMFont binary page name is invalid")
          result.pages.add BmFontPage(id: result.pages.len, filename: name)
          name.setLen(0)
        else:
          name.add char(data[index])
      if name.len > 0:
        raise newException(ValueError, "BMFont binary page name is unterminated")
    of 4:
      if sawCharacters or size mod 20 != 0:
        raise newException(ValueError, "BMFont binary characters block is invalid")
      sawCharacters = true
      for item in countup(offset, finish - 1, 20):
        let id = data.littleLong(item)
        if id > uint32(high(int)):
          raise newException(ValueError, "BMFont character ID is too large")
        result.characters.add BmFontCharacter(id: int(id),
          x: data.littleWord(item + 4), y: data.littleWord(item + 6),
          width: data.littleWord(item + 8), height: data.littleWord(item + 10),
          xOffset: data.signedWord(item + 12),
          yOffset: data.signedWord(item + 14),
          xAdvance: data.signedWord(item + 16), page: int(data[item + 18]),
          channel: int(data[item + 19]))
      result.declaredCharacters = result.characters.len
    of 5:
      if sawKernings or size mod 10 != 0:
        raise newException(ValueError, "BMFont binary kerning block is invalid")
      sawKernings = true
      for item in countup(offset, finish - 1, 10):
        let first = data.littleLong(item)
        let second = data.littleLong(item + 4)
        if first > uint32(high(int)) or second > uint32(high(int)):
          raise newException(ValueError, "BMFont kerning ID is too large")
        result.kernings.add BmFontKerningPair(first: int(first),
          second: int(second), amount: data.signedWord(item + 8))
      result.declaredKernings = result.kernings.len
    else:
      raise newException(ValueError, "unsupported BMFont binary block type")
    offset = finish
  if not sawInfo or not sawCommon or not sawPages or not sawCharacters:
    raise newException(ValueError, "BMFont binary descriptor is incomplete")
  result.validateSource

proc parseBmFont*(data: openArray[byte]): BmFontSource =
  if data.len >= 4 and data[0] == byte('B') and data[1] == byte('M') and
      data[2] == byte('F'):
    result = parseBmFontBinary(data)
  else:
    let text = data.bytesText.strip
    if text.startsWith("<?xml") or text.startsWith("<font"):
      if "<font" notin text:
        raise newException(ValueError, "XML is not a BMFont descriptor")
      result = BmFontSource(encoding: bfeXml, rawData: @data)
    else:
      result = parseBmFontText(data)

proc isBmFont*(data: openArray[byte]): bool =
  try: discard parseBmFont(data); true
  except ValueError: false
