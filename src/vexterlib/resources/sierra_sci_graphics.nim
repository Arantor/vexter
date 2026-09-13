## Documented Sierra SCI cursor, SCI0 view, and bitmap-font decoding.
## Format facts are derived from the supplied SCI Specifications chapter 3.

import ../archetypes/[font, raster]
import ./sierra_agi_view

type
  SciViewCel* = object
    width*, height*, xOffset*, yOffset*, transparentColour*: int
    pixels*: seq[uint8]
  SciViewLoop* = object
    mirrored*: bool
    cels*: seq[SciViewCel]
  SciView* = object
    loops*: seq[SciViewLoop]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI little-endian word")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc signedByte(value: byte): int =
  if value < 0x80: int(value) else: int(value) - 256

proc sciCursorHotspot*(data: openArray[byte], sci1 = false): tuple[x, y: int] =
  if data.len != 68:
    raise newException(ValueError, "SCI cursor resource must be exactly 68 bytes")
  if sci1:
    (le16(data, 0), le16(data, 2))
  elif le16(data, 2) == 3:
    (8, 8)
  else:
    (0, 0)

proc decodeSciCursor*(data: openArray[byte], sci1Colours = false): VextRaster =
  if data.len != 68:
    raise newException(ValueError, "SCI cursor resource must be exactly 68 bytes")
  var image = VextIndexedImage(width: 16, height: 16,
    palette: @AgiEgaPalette, pixels: newSeq[uint8](256),
    alpha: newSeq[uint8](256))
  for y in 0 ..< 16:
    let transparency = le16(data, 4 + y * 2)
    let colour = le16(data, 36 + y * 2)
    for x in 0 ..< 16:
      let mask = 1 shl (15 - x)
      let a = (transparency and mask) != 0
      let b = (colour and mask) != 0
      let pixel = y * 16 + x
      # Authentic SCI0 cursors in the supplied KQ4, LSL2, LSL3, and Colonel's
      # Bequest corpora use set first-plane bits for their transparent exterior,
      # contrary to the SCI0 truth table in the supplied chapter. SCI01/SCI1
      # retains the documented table.
      if (not sci1Colours and a) or (sci1Colours and not a and not b):
        image.alpha[pixel] = 0
      else:
        image.alpha[pixel] = 255
        image.pixels[pixel] = uint8(if not b: 0 elif sci1Colours and a: 7 else: 15)
  VextRaster(kind: vrkIndexedImage, image: image)

proc parseSci0View*(data: openArray[byte]): SciView =
  if data.len < 8: raise newException(ValueError, "truncated SCI0 view header")
  let loopCount = le16(data, 0)
  let mirrored = le16(data, 2)
  if loopCount <= 0 or loopCount > 16 or 8 + loopCount * 2 > data.len:
    raise newException(ValueError, "invalid SCI0 view loop table")
  for loopIndex in 0 ..< loopCount:
    let loopAt = le16(data, 8 + loopIndex * 2)
    if loopAt < 8 + loopCount * 2 or loopAt > data.len - 4:
      raise newException(ValueError, "SCI0 view loop is outside the resource")
    let celCount = le16(data, loopAt)
    if celCount <= 0 or loopAt + 4 + celCount * 2 > data.len:
      raise newException(ValueError, "invalid SCI0 view cel table")
    var loop = SciViewLoop(mirrored: (mirrored and (1 shl loopIndex)) != 0)
    for celIndex in 0 ..< celCount:
      let celAt = le16(data, loopAt + 4 + celIndex * 2)
      if celAt < 8 + loopCount * 2 or celAt > data.len - 7:
        raise newException(ValueError, "SCI0 view cel is outside the resource")
      var cel = SciViewCel(width: le16(data, celAt), height: le16(data, celAt + 2),
        xOffset: signedByte(data[celAt + 4]), yOffset: signedByte(data[celAt + 5]),
        transparentColour: int(data[celAt + 6]))
      if cel.width <= 0 or cel.height <= 0 or cel.transparentColour > 15 or
          cel.width > 320 or cel.height > 200 or
          cel.width > high(int) div cel.height:
        raise newException(ValueError, "invalid SCI0 view cel dimensions or colour key")
      cel.pixels = newSeq[uint8](cel.width * cel.height)
      for pixel in cel.pixels.mitems: pixel = uint8(cel.transparentColour)
      var at = celAt + 7
      var written = 0
      while written < cel.pixels.len:
        if at >= data.len: raise newException(ValueError, "truncated SCI0 view cel data")
        let token = data[at]; inc at
        # Supplied authentic SCI0 views may place zero no-op bytes before or
        # among the rectangle-filling runs. They contribute no pixels.
        if token == 0: continue
        let count = int(token shr 4)
        if count == 0 or written > cel.pixels.len - count:
          raise newException(ValueError, "SCI0 view run exceeds the cel")
        let colour = token and 0x0f
        for offset in 0 ..< count: cel.pixels[written + offset] = colour
        written += count
      loop.cels.add move(cel)
    result.loops.add move(loop)

proc raster*(cel: SciViewCel, mirrored = false): VextRaster =
  var image = VextIndexedImage(width: cel.width, height: cel.height,
    palette: @AgiEgaPalette, pixels: newSeq[uint8](cel.pixels.len),
    alpha: newSeq[uint8](cel.pixels.len))
  for y in 0 ..< cel.height:
    for x in 0 ..< cel.width:
      let sourceX = if mirrored: cel.width - 1 - x else: x
      let value = cel.pixels[y * cel.width + sourceX]
      let target = y * cel.width + x
      image.pixels[target] = value
      image.alpha[target] = if int(value) == cel.transparentColour: 0 else: 255
  VextRaster(kind: vrkIndexedImage, image: image)

proc decodeSciFont*(data: openArray[byte], name = "SCI font"): VextBitmapFont =
  if data.len < 6 or le16(data, 0) != 0:
    raise newException(ValueError, "invalid SCI font header")
  let count = le16(data, 2)
  let lineHeight = le16(data, 4)
  if count <= 0 or count > 65536 or lineHeight <= 0 or
      6 + count * 2 > data.len:
    raise newException(ValueError, "invalid SCI font character table")
  result = VextBitmapFont(name: name, lineHeight: lineHeight,
    baseline: lineHeight, ascent: lineHeight)
  for index in 0 ..< count:
    let at = le16(data, 6 + index * 2)
    if at < 6 + count * 2 or at > data.len - 2:
      raise newException(ValueError, "SCI font character is outside the resource")
    let width = int(data[at])
    let height = int(data[at + 1])
    let stride = (width + 7) div 8
    if height > lineHeight or stride > 0 and height > (data.len - at - 2) div stride:
      raise newException(ValueError, "truncated SCI font character bitmap")
    var coverage = newSeq[uint8](width * height)
    for y in 0 ..< height:
      for x in 0 ..< width:
        if (data[at + 2 + y * stride + x div 8] and (0x80'u8 shr (x mod 8))) != 0:
          coverage[y * width + x] = 255
    result.glyphs.add VextBitmapGlyph(name: "character " & $index,
      sourceIndex: index, bitmap: VextGlyphBitmap(kind: vgbkMonochrome,
        width: width, height: height, coverage: coverage), advanceX: width)
    if index <= 0x10ffff and index notin 0xd800 .. 0xdfff:
      result.mappings.add VextGlyphMapping(codePoint: index, glyphIndex: index)
  result.validate()
