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
  if result.bold notin 0 .. 1 or result.italic notin 0 .. 1 or
      result.unicode notin 0 .. 1 or result.smooth notin 0 .. 1 or
      result.antialias < 0 or result.packed notin 0 .. 1 or
      result.stretchHeight <= 0 or result.outline < 0 or
      result.alphaChannel notin 0 .. 4 or result.redChannel notin 0 .. 4 or
      result.greenChannel notin 0 .. 4 or result.blueChannel notin 0 .. 4:
    raise newException(ValueError, "BMFont style or channel metadata is invalid")
  for value in result.padding:
    if value < 0: raise newException(ValueError, "BMFont padding is invalid")
  for value in result.spacing:
    if value < 0: raise newException(ValueError, "BMFont spacing is invalid")
  var pageIds: seq[int]
  for page in result.pages:
    if page.id < 0 or page.id >= result.declaredPages or
        page.id in pageIds or page.filename.len == 0:
      raise newException(ValueError, "BMFont page table is invalid")
    pageIds.add page.id
  for character in result.characters:
    if character.id < 0 or character.id > 0x10ffff or
        character.id in 0xd800 .. 0xdfff or character.page notin pageIds or
        character.x < 0 or character.y < 0 or character.width < 0 or
        character.height < 0 or character.x > result.scaleWidth - character.width or
        character.y > result.scaleHeight - character.height:
      raise newException(ValueError, "BMFont character record is invalid")

proc parseBmFont*(data: openArray[byte]): BmFontSource =
  if data.len >= 4 and data[0] == byte('B') and data[1] == byte('M') and
      data[2] == byte('F'):
    result = BmFontSource(encoding: bfeBinary, rawData: @data)
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
