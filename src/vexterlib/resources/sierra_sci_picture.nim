## Recovery-oriented Sierra SCI0 picture rendering, based on the supplied SCI
## Specifications chapter 3 and supplemental Picture Resource reference.
## Extended operations whose behavior remains incomplete are rejected.

import ../archetypes/raster
import ./sierra_agi_view

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

type SciPicture* = object
  visual*, priority*, control*: VextRaster

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

proc renderSci0Picture*(data: openArray[byte]): SciPicture =
  var visual = newSeq[uint8](SciPictureWidth * SciPictureHeight)
  var priority = newSeq[uint8](visual.len)
  var control = newSeq[uint8](visual.len)
  for pixel in visual.mitems: pixel = 15
  var enabled = 3 # visual and priority
  var palettes: array[4, array[40, (uint8, uint8)]]
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
      for dx in -(size div 2) .. (size + 1) div 2:
        let inside = rectangle or size == 0 or
          dx * dx * 4 + dy * dy <= size * size + size
        var enabledPixel = true
        if textured:
          enabledPixel = ((TextureBits[textureAt shr 3] shr
            (7 - (textureAt and 7))) and 1) != 0
          textureAt = (textureAt + 1) mod 256
        if inside and enabledPixel: plot(cx + dx, cy + dy)

  while at < data.len:
    let command = data[at]; inc at
    case command
    of 0xf0:
      let code = byteArgument()
      if code >= 160:
        raise newException(ValueError, "SCI0 picture colour is outside all palettes")
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
          "SCI picture extended operation requires additional documentation")
    of 0xff:
      result.visual = asRaster(move(visual))
      result.priority = asRaster(move(priority))
      result.control = asRaster(move(control))
      return
    else:
      raise newException(ValueError, "unknown SCI0 picture operation")
  raise newException(ValueError, "SCI0 picture is missing its end operation")
