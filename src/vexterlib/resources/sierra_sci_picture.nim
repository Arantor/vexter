## Recovery-oriented Sierra SCI0 picture rendering, based on the supplied SCI
## Specifications chapter 3 and supplemental Picture Resource reference.
## Extended operations whose behavior remains incomplete are rejected.

import ../archetypes/raster
import ./sierra_agi_view
import ./sierra_sci_graphics

const
  SciPictureWidth* = 320
  SciPictureHeight* = 200
  TextureBits = [0x20'u8, 0x94, 0x02, 0x24, 0x90, 0x82, 0xa4, 0xa2,
    0x82, 0x09, 0x0a, 0x22, 0x12, 0x10, 0x42, 0x14, 0x91, 0x4a,
    0x91, 0x11, 0x08, 0x12, 0x25, 0x10, 0x22, 0xa8, 0x14, 0x24,
    0x00, 0x50, 0x24, 0x04]
  TextureStarts = [0x00'u8, 0x18, 0x30, 0xc4, 0xdc, 0x65, 0xeb, 0x48,
    0x60, 0xbd, 0x89, 0x04, 0x0a, 0xf4, 0x7d, 0x6d, 0x85, 0xb0,
    0x8e, 0x95, 0x1f, 0x22, 0x0d, 0xdf, 0x2a, 0x78, 0xd5, 0x73,
    0x1c, 0xb4, 0x40, 0xa1, 0xb9, 0x3c, 0xca, 0x58, 0x92, 0x34,
    0xcc, 0xce, 0xd7, 0x42, 0x90, 0x0f, 0x8b, 0x7f, 0x32, 0xed,
    0x5c, 0x9d, 0xc8, 0x99, 0xad, 0x4e, 0x56, 0xa6, 0xf7, 0x68,
    0xb7, 0x25, 0x82, 0x37, 0x3a, 0x51, 0x69, 0x26, 0x38, 0x52,
    0x9e, 0x9a, 0x4f, 0xa7, 0x43, 0x10, 0x80, 0xee, 0x3d, 0x59,
    0x35, 0xcf, 0x79, 0x74, 0xb5, 0xa2, 0xb1, 0x96, 0x23, 0xe0,
    0xbe, 0x05, 0xf5, 0x6e, 0x19, 0xc5, 0x66, 0x49, 0xf0, 0xd1,
    0x54, 0xa9, 0x70, 0x4b, 0xa4, 0xe2, 0xe6, 0xe5, 0xab, 0xe4,
    0xd2, 0xaa, 0x4c, 0xe3, 0x06, 0x6f, 0xc6, 0x4a, 0x75, 0xa3,
    0x97, 0xe1]
  CircleRowStarts = [0, 1, 4, 9, 16, 25, 36, 49]
  CircleHalfWidths = [
    0,
    0, 1, 0,
    1, 2, 2, 2, 1,
    1, 2, 3, 3, 3, 2, 1,
    1, 3, 4, 4, 4, 4, 4, 3, 1,
    1, 3, 4, 4, 5, 5, 5, 4, 4, 3, 1,
    2, 4, 5, 5, 6, 6, 6, 6, 6, 5, 5, 4, 2,
    2, 4, 5, 6, 6, 7, 7, 7, 7, 7, 6, 6, 5, 4, 2]

type SciPicture* = object
  visual*, priority*, control*: VextRaster

proc picLe16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI picture word")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc picLe32(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 4:
    raise newException(ValueError, "truncated SCI picture dword")
  int(data[at]) or (int(data[at + 1]) shl 8) or
    (int(data[at + 2]) shl 16) or (int(data[at + 3]) shl 24)

proc picSignedByte(value: byte): int =
  if value < 0x80: int(value) else: int(value) - 256

proc renderSci11PictureVisual(data: openArray[byte],
    fallbackPalette: openArray[VextRgb] = []): VextRaster =
  ## Corpus-derived Dagger/SQ4/KQ6 256-colour bitmap PIC subset. It shares
  ## SCI1.1 VIEW split control/literal runs and palette framing.
  if data.len < 114 or picLe16(data, 0) != 38:
    raise newException(ValueError, "invalid SCI1.1 picture header")
  let paletteAt = picLe32(data, 28)
  let celAt = picLe32(data, 32)
  if celAt < 38 or celAt > data.len - 42:
    raise newException(ValueError, "invalid SCI1.1 picture cel offset")
  let width = picLe16(data, celAt)
  let height = picLe16(data, celAt + 2)
  if width <= 0 or height <= 0 or width > 640 or height > 480 or
      width > high(int) div height:
    raise newException(ValueError, "invalid SCI1.1 picture dimensions")
  if data[celAt + 9] != 10:
    raise newException(ValueError, "unsupported SCI1.1 picture encoding")
  let controlSize = picLe32(data, celAt + 16)
  let controlAt = picLe32(data, celAt + 24)
  var literalAt = picLe32(data, celAt + 28)
  if controlSize <= 0 or controlAt < celAt + 42 or
      controlAt > data.len - controlSize or
      literalAt < controlAt + controlSize or literalAt > data.len or
      paletteAt < literalAt or paletteAt > data.len - 37:
    raise newException(ValueError, "invalid SCI1.1 picture stream bounds")
  let paletteCount = picLe16(data, paletteAt + 29)
  let paletteStride = case data[paletteAt + 31]
    of 1: 3
    of 3: 4
    else: raise newException(ValueError,
      "unsupported SCI1.1 palette representation")
  let paletteSize = 37 + paletteCount * paletteStride
  if paletteCount <= 0 or paletteCount > 256 or
      paletteAt > data.len - paletteSize:
    raise newException(ValueError, "invalid SCI1.1 picture palette bounds")
  var palette = parseSci11Palette(data, paletteAt, paletteSize,
    basePalette = fallbackPalette)
  var image = VextIndexedImage(width: width, height: height,
    palette: move(palette), pixels: newSeq[uint8](width * height),
    alpha: newSeq[uint8](width * height))
  for value in image.alpha.mitems: value = 255
  var written = 0
  for controlIndex in 0 ..< controlSize:
    let control = data[controlAt + controlIndex]
    let count = int(control and 0x3f)
    if count == 0 or written > image.pixels.len - count:
      raise newException(ValueError, "SCI1.1 picture run exceeds the image")
    case control shr 6
    of 0:
      if literalAt > paletteAt - count:
        raise newException(ValueError, "truncated SCI1.1 picture literal run")
      for offset in 0 ..< count:
        image.pixels[written + offset] = data[literalAt + offset]
      literalAt += count
    of 2:
      if literalAt >= paletteAt:
        raise newException(ValueError, "truncated SCI1.1 picture repeated literal")
      for offset in 0 ..< count:
        image.pixels[written + offset] = data[literalAt]
      inc literalAt
    of 3:
      for offset in 0 ..< count:
        image.pixels[written + offset] = data[celAt + 8]
    else:
      raise newException(ValueError, "unsupported SCI1.1 picture run type")
    written += count
  if written != image.pixels.len:
    raise newException(ValueError, "SCI1.1 picture runs do not fill the image")
  VextRaster(kind: vrkIndexedImage, image: move(image))

const DefaultPairs = [
  (0'u8, 0'u8), (1'u8, 1'u8), (2'u8, 2'u8), (3'u8, 3'u8),
  (4'u8, 4'u8), (5'u8, 5'u8), (6'u8, 6'u8), (7'u8, 7'u8),
  (8'u8, 8'u8), (9'u8, 9'u8), (10'u8, 10'u8), (11'u8, 11'u8),
  (12'u8, 12'u8), (13'u8, 13'u8), (14'u8, 14'u8), (8'u8, 8'u8),
  (8'u8, 8'u8), (0'u8, 1'u8), (0'u8, 2'u8), (0'u8, 3'u8),
  (0'u8, 4'u8), (0'u8, 5'u8), (0'u8, 6'u8), (8'u8, 8'u8),
  (8'u8, 8'u8), (15'u8, 9'u8), (15'u8, 10'u8), (15'u8, 11'u8),
  (15'u8, 12'u8), (15'u8, 13'u8), (15'u8, 14'u8), (15'u8, 15'u8),
  (0'u8, 8'u8), (9'u8, 1'u8), (2'u8, 10'u8), (3'u8, 11'u8),
  (4'u8, 12'u8), (5'u8, 13'u8), (6'u8, 14'u8), (8'u8, 8'u8)]

proc asRaster(pixels: sink seq[uint8]): VextRaster =
  VextRaster(kind: vrkIndexedImage, image: VextIndexedImage(
    width: SciPictureWidth, height: SciPictureHeight,
    palette: @AgiEgaPalette, pixels: move(pixels)))

proc renderSci0Picture*(data: openArray[byte], directColours = false,
    sci1Extensions = false): SciPicture =
  var visual = newSeq[uint8](SciPictureWidth * SciPictureHeight)
  var priority = newSeq[uint8](visual.len)
  var control = newSeq[uint8](visual.len)
  for pixel in visual.mitems: pixel = uint8(if sci1Extensions: 255 else: 15)
  var directPalette = newSeq[VextRgb](256)
  for index, colour in AgiEgaPalette: directPalette[index] = colour
  var enabled = 3 # visual and priority
  var palettes: array[4, array[40, (uint8, uint8)]]
  var monochromePalettes: array[4, array[40, uint8]]
  for palette in palettes.mitems:
    for index, pair in DefaultPairs: palette[index] = pair
  var colour1, colour2, priorityValue, controlValue = 0'u8
  var pattern = 0
  var at = 0

  template byteArgument(): int =
    block:
      if at >= data.len:
        raise newException(ValueError, "truncated SCI0 picture command")
      let decoded = int(data[at]); inc at
      decoded

  template itemArgument(): int =
    block:
      if at >= data.len or data[at] >= 0xf0:
        raise newException(ValueError, "truncated SCI0 picture command")
      byteArgument()

  template coordinates(): tuple[x, y: int] =
    block:
      let prefix = itemArgument()
      let lowX = byteArgument()
      let lowY = byteArgument()
      (lowX or ((prefix and 0xf0) shl 4),
        lowY or ((prefix and 0x0f) shl 8))

  proc eligible(index: int, boundary: seq[uint8], legal: uint8): bool =
    boundary[index] == legal

  proc plot(x, y: int) =
    if x < 0 or x >= SciPictureWidth or y < 0 or y >= SciPictureHeight: return
    let index = y * SciPictureWidth + x
    if (enabled and 1) != 0:
      visual[index] = if ((x + y) and 1) != 0: colour1 else: colour2
    if (enabled and 2) != 0: priority[index] = priorityValue
    if (enabled and 4) != 0: control[index] = controlValue

  proc line(x0, y0, x1, y1: int) =
    var x = x0; var y = y0
    let dx = abs(x1 - x0)
    let sx = if x0 < x1: 1 else: -1
    let dy = -abs(y1 - y0)
    let sy = if y0 < y1: 1 else: -1
    var error = dx + dy
    while true:
      plot(x, y)
      if x == x1 and y == y1: break
      let twice = 2 * error
      if twice >= dy: error += dy; x += sx
      if twice <= dx: error += dx; y += sy

  proc fill(x, y: int) =
    if x < 0 or x >= SciPictureWidth or y < 0 or y >= 190:
      return
    var boundary: seq[uint8]
    var legal = 0'u8
    if (enabled and 1) != 0:
      boundary = visual; legal = 15
    elif (enabled and 2) != 0: boundary = priority
    elif (enabled and 4) != 0: boundary = control
    else: return
    if not eligible(y * SciPictureWidth + x, boundary, legal): return
    var visited = newSeq[bool](visual.len)
    var queue = @[(x, y)]
    visited[y * SciPictureWidth + x] = true
    var head = 0
    while head < queue.len:
      let (px, py) = queue[head]; inc head
      plot(px, py)
      for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]:
        if nx >= 0 and nx < SciPictureWidth and ny >= 0 and ny < 190:
          let next = ny * SciPictureWidth + nx
          if not visited[next] and eligible(next, boundary, legal):
            visited[next] = true
            queue.add (nx, ny)

  proc drawPattern(texture, cx, cy: int) =
    let size = pattern and 7
    let rectangle = (pattern and 0x10) != 0
    let textured = (pattern and 0x20) != 0
    var textureAt = if textured:
      int(TextureStarts[(texture shr 1) mod TextureStarts.len]) else: 0
    for dy in -size .. size:
      let left = if rectangle and size == 0: 0 else: -size
      let right = if rectangle and size == 0: 1 else: size
      for dx in left .. right:
        let inside = rectangle or
          abs(dx) <= CircleHalfWidths[CircleRowStarts[size] + dy + size]
        var enabledPixel = true
        if textured and inside:
          enabledPixel = ((TextureBits[textureAt shr 3] shr
            (7 - (textureAt and 7))) and 1) != 0
          textureAt = (textureAt + 1) mod 256
        if inside and enabledPixel: plot(cx + dx, cy + dy)

  while at < data.len:
    let command = data[at]; inc at
    case command
    of 0xf0:
      let code = byteArgument()
      if directColours:
        colour1 = uint8(code)
        colour2 = uint8(code)
      elif code >= 160:
        raise newException(ValueError, "SCI0 picture colour is outside all palettes")
      else:
        (colour1, colour2) = palettes[code div 40][code mod 40]
      enabled = enabled or 1
    of 0xf1: enabled = enabled and not 1
    of 0xf2: priorityValue = uint8(byteArgument() and 0x0f); enabled = enabled or 2
    of 0xf3: enabled = enabled and not 2
    of 0xf4:
      var texture = if (pattern and 0x20) != 0: itemArgument() else: 0
      var point = coordinates()
      drawPattern(texture, point.x, point.y)
      while at < data.len and data[at] < 0xf0:
        if (pattern and 0x20) != 0: texture = itemArgument()
        let delta = itemArgument()
        point.x += (if (delta and 0x80) != 0: -((delta shr 4) and 7) else: delta shr 4)
        point.y += (if (delta and 0x08) != 0: -(delta and 7) else: delta and 7)
        drawPattern(texture, point.x, point.y)
    of 0xf5:
      var point = coordinates()
      while at < data.len and data[at] < 0xf0:
        let yDelta = itemArgument()
        let xByte = byteArgument()
        let next = (x: point.x + (if xByte < 128: xByte else: xByte - 256),
          y: point.y + (if (yDelta and 0x80) != 0: -(yDelta and 0x7f) else: yDelta))
        line(point.x, point.y, next.x, next.y)
        point = next
    of 0xf6:
      var point = coordinates()
      while at < data.len and data[at] < 0xf0:
        let next = coordinates()
        line(point.x, point.y, next.x, next.y)
        point = next
    of 0xf7:
      var point = coordinates()
      while at < data.len and data[at] < 0xf0:
        let delta = itemArgument()
        let next = (x: point.x + (if (delta and 0x80) != 0: -((delta shr 4) and 7) else: delta shr 4),
          y: point.y + (if (delta and 0x08) != 0: -(delta and 7) else: delta and 7))
        line(point.x, point.y, next.x, next.y)
        point = next
    of 0xf8:
      while at < data.len and data[at] < 0xf0:
        let point = coordinates()
        fill(point.x, point.y)
    of 0xfb: controlValue = uint8(byteArgument() and 0x0f); enabled = enabled or 4
    of 0xfc: enabled = enabled and not 4
    of 0xf9: pattern = byteArgument() and 0x37
    of 0xfa:
      while at < data.len and data[at] < 0xf0:
        let texture = if (pattern and 0x20) != 0: itemArgument() else: 0
        let point = coordinates()
        drawPattern(texture, point.x, point.y)
    of 0xfd:
      var texture = if (pattern and 0x20) != 0: itemArgument() else: 0
      var point = coordinates()
      drawPattern(texture, point.x, point.y)
      while at < data.len and data[at] < 0xf0:
        if (pattern and 0x20) != 0: texture = itemArgument()
        let yDelta = itemArgument()
        let xByte = byteArgument()
        point.x += (if xByte < 128: xByte else: xByte - 256)
        point.y += (if (yDelta and 0x80) != 0: -(yDelta and 0x7f) else: yDelta)
        drawPattern(texture, point.x, point.y)
    of 0xfe:
      let extended = byteArgument()
      if sci1Extensions and extended == 2:
        const paletteBytes = 256 + 4 + 256 * 4
        if at > data.len - paletteBytes:
          raise newException(ValueError, "truncated early SCI1 picture palette")
        let indicesAt = at
        let coloursAt = at + 256 + 4
        for item in 0 .. 255:
          let index = int(data[indicesAt + item])
          let colourAt = coloursAt + item * 4
          directPalette[index] = VextRgb(r: data[colourAt + 1],
            g: data[colourAt + 2], b: data[colourAt + 3])
        at += paletteBytes
        continue
      if sci1Extensions and extended == 4:
        const bandCount = 14
        if at > data.len - bandCount:
          raise newException(ValueError, "truncated early SCI1 priority bands")
        var previous = -1
        for band in 0 ..< bandCount:
          let boundary = int(data[at + band])
          if boundary < previous or boundary >= SciPictureHeight:
            raise newException(ValueError, "invalid early SCI1 priority bands")
          previous = boundary
        for y in 0 ..< SciPictureHeight:
          var value = 0'u8
          for band in 0 ..< bandCount:
            if y >= int(data[at + band]): value = uint8(band + 1)
          for x in 0 ..< SciPictureWidth:
            priority[y * SciPictureWidth + x] = value
        at += bandCount
        continue
      if sci1Extensions and extended == 1:
        if at > data.len - 5:
          raise newException(ValueError, "truncated early SCI1 picture cel header")
        let celSize = picLe16(data, at + 3)
        let celAt = at + 5
        if celSize < 8 or celAt > data.len - celSize:
          raise newException(ValueError, "invalid early SCI1 picture cel size")
        let width = picLe16(data, celAt)
        let height = picLe16(data, celAt + 2)
        let xOffset = picSignedByte(data[celAt + 4])
        let yOffset = picSignedByte(data[celAt + 5])
        let transparent = data[celAt + 6]
        if width <= 0 or height <= 0 or width > SciPictureWidth or
            height > SciPictureHeight or width > high(int) div height:
          raise newException(ValueError, "invalid early SCI1 picture cel dimensions")
        var celPixels = newSeq[uint8](width * height)
        var streamAt = celAt + 8
        let streamEnd = celAt + celSize
        var written = 0
        while written < celPixels.len:
          if streamAt >= streamEnd:
            raise newException(ValueError, "truncated early SCI1 picture cel data")
          let control = data[streamAt]; inc streamAt
          let count = int(control and 0x3f)
          if count == 0 or written > celPixels.len - count:
            raise newException(ValueError, "early SCI1 picture run exceeds the cel")
          case control shr 6
          of 0:
            if streamAt > streamEnd - count:
              raise newException(ValueError, "truncated early SCI1 picture literal run")
            for offset in 0 ..< count:
              celPixels[written + offset] = data[streamAt + offset]
            streamAt += count
          of 2:
            if streamAt >= streamEnd:
              raise newException(ValueError, "truncated early SCI1 picture repeat")
            for offset in 0 ..< count: celPixels[written + offset] = data[streamAt]
            inc streamAt
          of 3:
            for offset in 0 ..< count: celPixels[written + offset] = transparent
          else:
            raise newException(ValueError, "unsupported early SCI1 picture run type")
          written += count
        if streamAt != streamEnd:
          raise newException(ValueError, "early SCI1 picture cel has trailing data")
        for y in 0 ..< height:
          for x in 0 ..< width:
            let value = celPixels[y * width + x]
            let targetX = x + xOffset
            let targetY = y + yOffset
            if value != transparent and targetX in 0 ..< SciPictureWidth and
                targetY in 0 ..< SciPictureHeight:
              visual[targetY * SciPictureWidth + targetX] = value
        at = streamEnd
        continue
      if not sci1Extensions and extended == 2:
        let palette = byteArgument()
        if palette >= 4 or at > data.len - 40:
          raise newException(ValueError, "invalid SCI0 monochrome palette")
        for index in 0 ..< 40:
          monochromePalettes[palette][index] = uint8(byteArgument())
        continue
      if not sci1Extensions and extended == 3:
        let code = byteArgument()
        if code >= 160:
          raise newException(ValueError, "SCI0 monochrome visual colour is invalid")
        let colour = monochromePalettes[code div 40][code mod 40]
        if colour >= 16:
          raise newException(ValueError, "SCI0 monochrome palette colour is invalid")
        colour1 = colour; colour2 = colour
        enabled = enabled or 1
        continue
      if not sci1Extensions and extended == 4:
        enabled = enabled and not 1
        continue
      if not sci1Extensions and extended == 5:
        let colour = byteArgument()
        if colour >= 16:
          raise newException(ValueError, "SCI0 direct visual colour is invalid")
        colour1 = uint8(colour); colour2 = uint8(colour)
        enabled = enabled or 1
        continue
      if not sci1Extensions and extended == 6:
        enabled = enabled and not 1
        continue
      if not sci1Extensions and extended == 7:
        let origin = coordinates()
        if at > data.len - 2:
          raise newException(ValueError, "truncated SCI01 embedded cel size")
        let celSize = picLe16(data, at); at += 2
        let celAt = at
        if celSize < 8 or celAt > data.len - celSize:
          raise newException(ValueError, "invalid SCI01 embedded cel size")
        let width = picLe16(data, celAt)
        let height = picLe16(data, celAt + 2)
        let xOffset = picSignedByte(data[celAt + 4])
        let yOffset = picSignedByte(data[celAt + 5])
        let transparent = data[celAt + 6] and 0x0f
        if width <= 0 or height <= 0 or width > SciPictureWidth or
            height > SciPictureHeight or width > high(int) div height:
          raise newException(ValueError, "invalid SCI01 embedded cel dimensions")
        var streamAt = celAt + 8
        let streamEnd = celAt + celSize
        var written = 0
        while written < width * height:
          if streamAt >= streamEnd:
            raise newException(ValueError, "truncated SCI01 embedded cel data")
          let run = data[streamAt]; inc streamAt
          let count = int(run shr 4)
          let colour = run and 0x0f
          if count == 0 or written > width * height - count:
            raise newException(ValueError, "SCI01 embedded cel run " & $run &
              " exceeds " & $width & "x" & $height & " at pixel " & $written)
          if colour != transparent:
            for offset in 0 ..< count:
              let pixel = written + offset
              let targetX = origin.x + xOffset + pixel mod width
              let targetY = origin.y + yOffset + pixel div width
              if targetX in 0 ..< SciPictureWidth and
                  targetY in 0 ..< SciPictureHeight:
                visual[targetY * SciPictureWidth + targetX] = colour
          written += count
        at = streamEnd
        continue
      if not sci1Extensions and extended == 8:
        const bandCount = 14
        if at > data.len - bandCount:
          raise newException(ValueError, "truncated SCI01 priority bands")
        var previous = -1
        for band in 0 ..< bandCount:
          let boundary = int(data[at + band])
          if boundary < previous or boundary >= SciPictureHeight:
            raise newException(ValueError, "invalid SCI01 priority bands")
          previous = boundary
        for y in 0 ..< SciPictureHeight:
          var value = 0'u8
          for band in 0 ..< bandCount:
            if y >= int(data[at + band]): value = uint8(band + 1)
          for x in 0 ..< SciPictureWidth:
            priority[y * SciPictureWidth + x] = value
        at += bandCount
        continue
      case extended
      of 0:
        while at < data.len and data[at] < 0xf0:
          let index = itemArgument()
          let colours = byteArgument()
          if index >= 160: raise newException(ValueError, "SCI0 palette index is outside all palettes")
          palettes[index div 40][index mod 40] =
            (uint8(colours shr 4), uint8(colours and 0x0f))
      of 1:
        let palette = byteArgument()
        if palette >= 4: raise newException(ValueError, "SCI0 palette number is invalid")
        for index in 0 ..< 40:
          let colours = byteArgument()
          palettes[palette][index] =
            (uint8(colours shr 4), uint8(colours and 0x0f))
      else:
        raise newException(ValueError,
          "SCI picture extended operation " & $extended &
          " requires additional documentation")
    of 0xff:
      if sci1Extensions:
        result.visual = VextRaster(kind: vrkIndexedImage,
          image: VextIndexedImage(width: SciPictureWidth, height: SciPictureHeight,
            palette: move(directPalette), pixels: move(visual)))
      else:
        result.visual = asRaster(move(visual))
      result.priority = asRaster(move(priority))
      result.control = asRaster(move(control))
      return
    else:
      raise newException(ValueError, "unknown SCI0 picture operation")
  raise newException(ValueError, "SCI0 picture is missing its end operation")

proc renderSci11Picture*(data: openArray[byte],
    fallbackPalette: openArray[VextRgb] = []): SciPicture =
  ## SCI1.1 bitmap visual plus its trailing SCI vector operations. The latter
  ## retain the earlier priority/control drawing command language.
  result.visual = renderSci11PictureVisual(data, fallbackPalette)
  let vectorSize = picLe32(data, 12)
  let vectorAt = picLe32(data, 16)
  if vectorSize <= 0 or vectorAt < 38 or vectorAt > data.len - vectorSize:
    raise newException(ValueError, "invalid SCI1.1 picture vector bounds")
  let vectorLayers = renderSci0Picture(
    data.toOpenArray(vectorAt, vectorAt + vectorSize - 1), directColours = true)
  result.priority = vectorLayers.priority
  result.control = vectorLayers.control
