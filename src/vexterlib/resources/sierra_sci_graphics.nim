## Documented Sierra SCI cursor, SCI0 view, and bitmap-font decoding.
## Format facts are derived from the supplied SCI Specifications chapter 3.

import ../archetypes/[font, raster]
import ./sierra_agi_view

type
  SciViewCel* = object
    width*, height*, xOffset*, yOffset*, transparentColour*: int
    pixels*: seq[uint8]
    palette*: seq[VextRgb]
  SciViewLoop* = object
    mirrored*: bool
    cels*: seq[SciViewCel]
  SciView* = object
    loops*: seq[SciViewLoop]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI little-endian word")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc le32(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 4:
    raise newException(ValueError, "truncated SCI little-endian dword")
  int(data[at]) or (int(data[at + 1]) shl 8) or
    (int(data[at + 2]) shl 16) or (int(data[at + 3]) shl 24)

proc signedWord(value: int): int =
  if value < 0x8000: value else: value - 0x10000

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

proc parseSci11Palette*(data: openArray[byte], start = 0,
    length = -1): seq[VextRgb] =
  ## Corpus-derived SCI1.1 palette framing. The supplied Dagger palette 999
  ## and embedded VIEW palettes share this 37-byte header and bounded entry
  ## representation.
  let size = if length < 0: data.len - start else: length
  if start < 0 or size < 37 or start > data.len - size:
    raise newException(ValueError, "invalid SCI1.1 palette bounds")
  let count = le16(data, start + 29)
  let representation = int(data[start + 31])
  let stride = case representation
    of 1: 3
    of 3: 4
    else: raise newException(ValueError, "unsupported SCI1.1 palette representation")
  if count <= 0 or count > 256 or 37 + count * stride != size:
    raise newException(ValueError, "invalid SCI1.1 palette entry table")
  result = newSeq[VextRgb](256)
  var at = start + 37
  for index in 0 ..< count:
    if stride == 4:
      # The leading per-entry value is retained as structurally observed but
      # not yet assigned semantics; authentic Dagger entries normally use 3.
      inc at
    result[index] = VextRgb(r: data[at], g: data[at + 1], b: data[at + 2])
    at += 3

proc parseSci11View*(data: openArray[byte],
    fallbackPalette: openArray[VextRgb] = []): SciView =
  ## Corpus-derived split-stream SCI1.1 VIEW subset, validated against the
  ## supplied Dagger CD resources. Unknown flag semantics remain unlabelled.
  if data.len < 16 or le16(data, 0) != 16:
    raise newException(ValueError, "invalid SCI1.1 VIEW header")
  let loopCount = int(data[2])
  if loopCount <= 0 or loopCount > 16 or 16 + loopCount * 16 > data.len:
    raise newException(ValueError, "invalid SCI1.1 VIEW loop table")
  var palette = @fallbackPalette
  let paletteAt = le32(data, 8)
  if paletteAt != 0:
    if paletteAt < 4:
      raise newException(ValueError, "SCI1.1 VIEW palette has no length")
    let paletteSize = le32(data, paletteAt - 4)
    palette = parseSci11Palette(data, paletteAt, paletteSize)
  if palette.len == 0:
    palette = newSeq[VextRgb](256)
    for index, colour in AgiEgaPalette: palette[index] = colour
  if palette.len != 256:
    raise newException(ValueError, "SCI1.1 VIEW palette must contain 256 entries")

  var loopRecords: seq[tuple[count, celTableAt: int]]
  for loopIndex in 0 ..< loopCount:
    let loopAt = 16 + loopIndex * 16
    loopRecords.add (count: int(data[loopAt + 4]),
      celTableAt: le16(data, loopAt + 14))
  for loopIndex in 0 ..< loopCount:
    var celCount = loopRecords[loopIndex].count
    let celTableAt = loopRecords[loopIndex].celTableAt
    var mirrored = false
    if celCount == 0:
      for sourceIndex, source in loopRecords:
        if sourceIndex != loopIndex and source.count > 0 and
            source.celTableAt == celTableAt:
          celCount = source.count
          mirrored = true
          break
    if celCount <= 0 or celCount > 64 or celTableAt < 16 + loopCount * 16 or
        celTableAt > data.len - celCount * 36:
      raise newException(ValueError, "invalid SCI1.1 VIEW cel table: loop " &
        $loopIndex & ", count " & $celCount & ", offset " & $celTableAt)
    var loop = SciViewLoop(mirrored: mirrored)
    for celIndex in 0 ..< celCount:
      let celAt = celTableAt + celIndex * 36
      var cel = SciViewCel(width: le16(data, celAt),
        height: le16(data, celAt + 2),
        xOffset: signedWord(le16(data, celAt + 4)),
        yOffset: signedWord(le16(data, celAt + 6)),
        transparentColour: int(data[celAt + 8]), palette: palette)
      if cel.width <= 0 or cel.height <= 0 or cel.width > 640 or
          cel.height > 480 or cel.width > high(int) div cel.height:
        raise newException(ValueError, "invalid SCI1.1 VIEW cel dimensions")
      if data[celAt + 9] != 10:
        raise newException(ValueError, "unsupported SCI1.1 VIEW cel encoding")
      let controlSize = le32(data, celAt + 16)
      let controlAt = le32(data, celAt + 24)
      var literalAt = le32(data, celAt + 28)
      if controlSize <= 0 or controlAt < 0 or controlAt > data.len - controlSize or
          literalAt < 0 or literalAt > data.len:
        raise newException(ValueError, "invalid SCI1.1 VIEW cel stream bounds")
      cel.pixels = newSeq[uint8](cel.width * cel.height)
      var written = 0
      for controlIndex in 0 ..< controlSize:
        let control = data[controlAt + controlIndex]
        let count = int(control and 0x3f)
        if count == 0 or written > cel.pixels.len - count:
          raise newException(ValueError, "SCI1.1 VIEW run exceeds the cel")
        case control shr 6
        of 0:
          if literalAt > data.len - count:
            raise newException(ValueError, "truncated SCI1.1 VIEW literal run")
          for offset in 0 ..< count: cel.pixels[written + offset] = data[literalAt + offset]
          literalAt += count
        of 2:
          if literalAt >= data.len:
            raise newException(ValueError, "truncated SCI1.1 VIEW repeated literal")
          for offset in 0 ..< count: cel.pixels[written + offset] = data[literalAt]
          inc literalAt
        of 3:
          for offset in 0 ..< count:
            cel.pixels[written + offset] = uint8(cel.transparentColour)
        else:
          raise newException(ValueError, "unsupported SCI1.1 VIEW run type")
        written += count
      if written != cel.pixels.len:
        raise newException(ValueError, "SCI1.1 VIEW runs do not fill the cel")
      loop.cels.add move(cel)
    result.loops.add move(loop)

proc raster*(cel: SciViewCel, mirrored = false): VextRaster =
  var image = VextIndexedImage(width: cel.width, height: cel.height,
    palette: (if cel.palette.len > 0: cel.palette else: @AgiEgaPalette),
    pixels: newSeq[uint8](cel.pixels.len),
    alpha: newSeq[uint8](cel.pixels.len))
  for y in 0 ..< cel.height:
    for x in 0 ..< cel.width:
      let sourceX = if mirrored: cel.width - 1 - x else: x
      let value = cel.pixels[y * cel.width + sourceX]
      let target = y * cel.width + x
      image.pixels[target] = value
      image.alpha[target] = if int(value) == cel.transparentColour: 0 else: 255
  VextRaster(kind: vrkIndexedImage, image: image)

proc animation*(loop: SciViewLoop, frameDurationMs = 100): VextRaster =
  ## Composes differently sized cels around their common placement origin.
  ## SCI VIEWs carry no timing; callers must identify this duration as synthetic.
  if loop.cels.len == 0 or frameDurationMs <= 0:
    raise newException(ValueError, "SCI view animation needs frames and a preview duration")
  var minX = loop.cels[0].xOffset
  var minY = loop.cels[0].yOffset
  var maxX = minX + loop.cels[0].width
  var maxY = minY + loop.cels[0].height
  for cel in loop.cels:
    minX = min(minX, cel.xOffset)
    minY = min(minY, cel.yOffset)
    maxX = max(maxX, cel.xOffset + cel.width)
    maxY = max(maxY, cel.yOffset + cel.height)
  let width = maxX - minX
  let height = maxY - minY
  if width <= 0 or height <= 0 or width > 576 or height > 456:
    raise newException(ValueError, "SCI view animation canvas is invalid")
  var animation = VextIndexedAnimation(width: width, height: height)
  for cel in loop.cels:
    let source = cel.raster(loop.mirrored).image
    var image = VextIndexedImage(width: width, height: height,
      palette: source.palette, pixels: newSeq[uint8](width * height),
      alpha: newSeq[uint8](width * height))
    let left = cel.xOffset - minX
    let top = cel.yOffset - minY
    for y in 0 ..< source.height:
      for x in 0 ..< source.width:
        let sourceAt = y * source.width + x
        if source.alpha[sourceAt] != 0:
          let targetAt = (top + y) * width + left + x
          image.pixels[targetAt] = source.pixels[sourceAt]
          image.alpha[targetAt] = source.alpha[sourceAt]
    animation.frames.add VextIndexedAnimationFrame(
      image: move(image), durationMs: frameDurationMs)
  VextRaster(kind: vrkIndexedAnimation, animation: move(animation))

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
