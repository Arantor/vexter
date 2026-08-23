## Static DOS ANSI terminal emulation and IBM VGA CP437 rendering.

import std/base64
import ../archetypes/raster
import ../containers/ansi_art

const
  AnsiImageTypeId* = "ansi.image"
  AnsiImageResourcePath* = "/image"
  # Mechanically extracted IBM VGA 9x16 CP437 bitmap strike from VileR's
  # Ultimate Oldschool PC Font Pack v2.2, CC BY-SA 4.0. FontData is the
  # gzip/base64 representation of that licensed glyph data; see THIRD_PARTY.md.
  FontData = "H4sIAAAAAAACA6VZT2vjRhQXKegkvOlNNCa55AOIFhzRCgeWfoXeRbaoexhan7yCCq1zyUcohJ576XcIuBGIHkyOi0Guycm+lGJYyPoQpL43krPrWf2elvZ5lxx+em9m3v83Y1ldlF7+dnl5c315mQK8KqoqW1dViiSokijxDxF+6CcS7AbBer123QDiKS2O8VqE245UmtYZH4Cp9aMgev48CjB/dn1zc50B/uPeF1/GM6LYAsKJApcO0I6ff3XuEY029+346xevXxD9sF5NweHdIlgHBZA/md5vtuV2cz+dtOIHdu94WA6Pe/YBVL/ruilSsBXVRH/B/oui+PmIqRVO8tBXea58J08EL2UX69hfKuFMSH2a8AHpE6d0XGFzXliGnhRj0+m0FODTqIpOMXzo+0lSloJuksTH8dVBFDsBKwfoh0x7KgtQqlT6f7t2k/x2mtj2VZ4gC9zmjuuF+VU76ivljxcUX+N23XteKG6PZGtyHWA819HkYgtGQRVEkgpxdH/oZoKLlJ9gJ7jCgc36A/FN+SfLiiLLQIKzXD9uIsACAVqLz0uI24Ft2yh8nX6gZiUp+BgcnYLjUeD3Q8JzIoCXtH5tY7Q/YhX4GUtpfScWNS8YuMGRebX6yMtsXIL1P0Sal2XA/TtC/OoPlsvlYpqg7ELpt2QFteOPlAESzvCPyL9uyYLTW+RfW1UXCLUF9osuXsYvw4uoFPEw3AjrL/M8+rod55Pp44HzBU0BQP3Fsc4OuL6v6GhxTIdcteObUBM8H3cmFJ5EYP+rh3J5h/evfVvwb22/EOuv4X+zTJwe5GcbriB/6Ds2XL8qrkX95h37z2qKUH3WaFFUqP/QrC5nQcgfBcL+quyKg++PrAL+4zWE+lPqwEZ+H/ZXgdNQgKLzk0t51VYe3W6+2ElgfbXuwzDWIYzbsySnBIDs16eTqRmWr/lLzO+r78ON4L9EYxY/S5zWEKX9q3GE/Zfypi/5p21bPVtT1JriSH6dAIB8vyO/cAqpCiaIL5oWG+tPiJ8n/gSqcKc/VKIX40jUP/fwsH0/9LxHDo9BH/Lr5QX/EOO/xjkBYJyYKQFAvM4/qe2gEjXj/hTk7x6ZdsT27eH5whLmD+ZlGe4IGGfRFb66gqPtNfWZyrNjt1poJuuf+2IpPmlxOX/M5PxC3Y2I+8qX5fMJKQTpeCiByvkll/MP70/kjywxf5DjiTjLl/D8fYOG1CPh3DaWUUixH+EZ48dvjtL54lU7OKTkXbJ/3FlYv0L+yeX8VOsX4148E/2T+cX8kX8Q33EbnIj9R27J/QnNTRnFV4YmwKfytXrEyamiH+Cn9iu5iH6i/P22Pf0cuXr8JJqPgANI8cPxLfov8Uv2YVzUP+UvoX4R+tTgtge3UkNpOuLrAUu6OaK50OPxVbpe4hl0Kt0+cflHVzu3OZeHu19t5wTj0d0vw3YRdXUIAqG+DdRcDYTtEarm7dDn3+7/TPy73/d/Jv7Xq/0fuD17IoBvRXyL8UFND81fpIVSxLvkP9hQ/sAg4B4y/4MNc2/DVgrXRlo/HS3AtkP/pmdODLxC+G6yMOSb/CcIB5PJR+uL8k8M+ZP3eKO/M0P/+/iZd26svr+/c2+f35T/zti/yV9Z70T+Myy/4Yfym/Wh/MZ6Mv9gINu3Muw7+dh+on4Hg3PRvieG/5nyBfvuLNSxPtxf413wfLv81BFf0L8rgyYGmZ/t+He0Mchc+JlBpvzKeNbaX/apyM7n8wWoz/x2NZ9R+Z2h+1We7qUCydf/TAjOqUfD8xPff86ZRvD6vZle0QbGC+l9x0rdoH6Bgx2Ebp+pjYBwzsf7B9wPeq4z1G98+Hw03OMW5jOb8LcpOl7fC7l9D72+1XEBKDwulNITQ/N8UVnwgYSvn2ET1lxvI7x3dNTdH7iS/Ykrle7fuYmEU7LuD//H48ruAwQ803d3fysV9EFvJoQGj/9zL/xTTj9JTdZ/oX8BG14JMQAgAAA="
  DosPalette = [
    VextRgb(r:0,g:0,b:0), VextRgb(r:0,g:0,b:170),
    VextRgb(r:0,g:170,b:0), VextRgb(r:0,g:170,b:170),
    VextRgb(r:170,g:0,b:0), VextRgb(r:170,g:0,b:170),
    VextRgb(r:170,g:85,b:0), VextRgb(r:170,g:170,b:170),
    VextRgb(r:85,g:85,b:85), VextRgb(r:85,g:85,b:255),
    VextRgb(r:85,g:255,b:85), VextRgb(r:85,g:255,b:255),
    VextRgb(r:255,g:85,b:85), VextRgb(r:255,g:85,b:255),
    VextRgb(r:255,g:255,b:85), VextRgb(r:255,g:255,b:255)]

type
  AnsiLetterSpacing* = enum
    alsAuto
    alsEight
    alsNine

  AnsiPresentationAspect* = enum
    apaAuto
    apaLegacy
    apaSquare

  ZStream = object
    nextIn: ptr byte
    availIn: uint32
    totalIn: culong
    nextOut: ptr byte
    availOut: uint32
    totalOut: culong
    msg: cstring
    state, zalloc, zfree, opaque: pointer
    dataType: cint
    adler, reserved: culong
  Cell = object
    character, foreground, background: uint8

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
elif defined(macosx):
  const ZlibLibrary = "libz.dylib"
else:
  const ZlibLibrary = "libz.so(|.1)"
proc zlibVersion(): cstring {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateInit2(s: ptr ZStream, bits: cint, version: cstring, size: cint): cint
  {.cdecl, importc: "inflateInit2_", dynlib: ZlibLibrary.}
proc inflate(s: ptr ZStream, flush: cint): cint {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateEnd(s: ptr ZStream): cint {.cdecl, importc, dynlib: ZlibLibrary.}

proc fontBytes(): seq[byte] =
  let packedString = decode(FontData)
  var packed = newSeq[byte](packedString.len)
  for i, value in packedString: packed[i] = byte(value)
  result = newSeq[byte](8192)
  var stream: ZStream
  stream.nextIn = addr packed[0]; stream.availIn = uint32(packed.len)
  stream.nextOut = addr result[0]; stream.availOut = uint32(result.len)
  if inflateInit2(addr stream, 31, zlibVersion(), cint(sizeof(ZStream))) != 0:
    raise newException(ValueError, "could not initialize ANSI font inflater")
  let status = inflate(addr stream, 4)
  discard inflateEnd(addr stream)
  if status != 1 or stream.totalOut != culong(result.len):
    raise newException(ValueError, "invalid embedded ANSI font")

proc parameters(data: openArray[byte], first, last: int): seq[int] =
  var value = 0; var have = false
  for i in first ..< last:
    if data[i] >= byte('0') and data[i] <= byte('9'):
      value = value * 10 + int(data[i] - byte('0')); have = true
    elif data[i] == byte(';'):
      result.add(if have: value else: 0); value = 0; have = false
  result.add(if have: value else: 0)

proc ansiGlyphWidth*(source: AnsiArtSource,
    spacing = alsAuto): int =
  case spacing
  of alsEight: 8
  of alsNine: 9
  of alsAuto:
    if source.sauce.present:
      case (source.sauce.flags shr 1) and 3
      of 1: 8
      of 2: 9
      else: 9
    else: 9

proc ansiLegacyAspect*(source: AnsiArtSource,
    aspect = apaAuto): bool =
  case aspect
  of apaLegacy: true
  of apaSquare: false
  of apaAuto:
    if source.sauce.present:
      case (source.sauce.flags shr 3) and 3
      of 2: false
      else: true
    else: true

proc renderAnsiArt*(source: AnsiArtSource, spacing = alsAuto,
    aspect = apaAuto): VextIndexedImage =
  let width = if source.sauce.present and source.sauce.info1 > 0: int(source.sauce.info1) else: 80
  let glyphWidth = source.ansiGlyphWidth(spacing)
  let ice = source.sauce.present and (source.sauce.flags and 1) != 0
  var cells = newSeq[Cell](width)
  var row, column, maximumRow, maximumWrittenRow, savedRow, savedColumn: int
  var foreground = 7; var background = 0; var bright = false; var blink = false
  const ansiColours = [0, 4, 2, 6, 1, 5, 3, 7]
  var pendingWrap = false
  template ensureRow(y: int) =
    while cells.len < (y + 1) * width: cells.setLen(cells.len + width)
  template move() =
    pendingWrap = false; ensureRow(row); maximumRow = max(maximumRow, row)
  proc erase(first, last: int) =
    for i in max(0, first) .. min(cells.high, last): cells[i] = Cell()
  var position = 0
  while position < source.payload.len:
    let value = source.payload[position]
    if value == 0x1a: break
    case value
    of 8: column = max(0, column - 1); pendingWrap = false; inc position
    of 9: column = min(width - 1, ((column div 8) + 1) * 8); pendingWrap = false; inc position
    of 10, 11, 12: inc row; move(); inc position
    of 13: column = 0; pendingWrap = false; inc position
    of 27:
      if source.payload[position + 1] != byte('['):
        case char(source.payload[position + 1])
        of '7': savedRow = row; savedColumn = column
        of '8': row = savedRow; column = savedColumn; move()
        of 'M': row = max(0, row - 1); move()
        else: discard
        position += 2; continue
      var final = position + 2
      while source.payload[final] >= 0x20 and source.payload[final] <= 0x3f: inc final
      let p = parameters(source.payload, position + 2, final)
      let count = if p[0] == 0: 1 else: p[0]
      case char(source.payload[final])
      of 'A': row = max(0, row - count); move()
      of 'B': row += count; move()
      of 'C': column = min(width - 1, column + count); pendingWrap = false
      of 'D': column = max(0, column - count); pendingWrap = false
      of 'E': row += count; column = 0; move()
      of 'F': row = max(0, row - count); column = 0; move()
      of 'G': column = min(width - 1, max(0, count - 1)); pendingWrap = false
      of 'H', 'f':
        row = max(0, (if p.len > 0 and p[0] > 0: p[0] else: 1) - 1)
        column = min(width - 1, max(0, (if p.len > 1 and p[1] > 0: p[1] else: 1) - 1)); move()
      of 'J':
        ensureRow(row)
        if p[0] == 2: erase(0, cells.high)
        elif p[0] == 1: erase(0, row * width + column)
        else: erase(row * width + column, cells.high)
      of 'K':
        ensureRow(row)
        if p[0] == 2: erase(row * width, row * width + width - 1)
        elif p[0] == 1: erase(row * width, row * width + column)
        else: erase(row * width + column, row * width + width - 1)
      of 's': savedRow = row; savedColumn = column
      of 'u': row = savedRow; column = savedColumn; move()
      of 'm':
        for code in p:
          case code
          of 0: foreground = 7; background = 0; bright = false; blink = false
          of 1: bright = true
          of 5: blink = true
          of 22: bright = false
          of 25: blink = false
          of 30..37: foreground = ansiColours[code - 30]
          of 39: foreground = 7
          of 40..47: background = ansiColours[code - 40]
          of 49: background = 0
          of 90..97: foreground = ansiColours[code - 90] + 8
          of 100..107: background = ansiColours[code - 100] + 8
          else: discard
      else: discard
      position = final + 1
    else:
      if value >= 32:
        if pendingWrap: inc row; column = 0; pendingWrap = false
        move()
        cells[row * width + column] = Cell(character: value,
          foreground: uint8(foreground + (if bright and foreground < 8: 8 else: 0)),
          background: uint8(background + (if ice and blink and background < 8: 8 else: 0)))
        maximumWrittenRow = max(maximumWrittenRow, row)
        if column == width - 1: pendingWrap = true else: inc column
      inc position
  let legacyAspect = source.ansiLegacyAspect(aspect)
  # Square-pixel references crop at the last written row. The provisional
  # terminal tail remains for legacy presentation; see docs/outstanding.md.
  let rows = if legacyAspect: maximumRow + 4 else: maximumWrittenRow + 1
  let naturalHeight = rows * 16
  let outputHeight = if legacyAspect:
      naturalHeight * 27 div 20 else: naturalHeight
  let font = fontBytes()
  var natural = newSeq[uint8](width * glyphWidth * naturalHeight)
  for cellIndex in 0 ..< min(cells.len, rows * width):
    let cell = cells[cellIndex]
    for y in 0 ..< 16:
      for x in 0 ..< glyphWidth:
        let set = if x < 8:
          (font[int(cell.character) * 32 + y] and byte(0x80 shr x)) != 0
        else:
          (font[int(cell.character) * 32 + 16 + y] and 0x80) != 0
        let px = (cellIndex mod width) * glyphWidth + x
        let py = (cellIndex div width) * 16 + y
        natural[py * width * glyphWidth + px] = if set: cell.foreground else: cell.background
  result = VextIndexedImage(width: width * glyphWidth, height: outputHeight,
    palette: @DosPalette, pixels: newSeq[uint8](width * glyphWidth * outputHeight))
  for y in 0 ..< outputHeight:
    let sourceY = if legacyAspect: y * 20 div 27 else: y
    for x in 0 ..< result.width:
      result.pixels[y * result.width + x] = natural[sourceY * result.width + x]
