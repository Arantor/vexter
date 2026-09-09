## Sierra AGI PIC vector rendering.
## Format facts are derived from the supplied AGI Specifications chapter 7.

import std/math
import ../archetypes/raster
import ./sierra_agi_view

const
  AgiPictureWidth* = 160
  AgiPictureHeight* = 168
  textureBits = [0x20'u8, 0x94, 0x02, 0x24, 0x90, 0x82, 0xa4, 0xa2,
    0x82, 0x09, 0x0a, 0x22, 0x12, 0x10, 0x42, 0x14, 0x91, 0x4a,
    0x91, 0x11, 0x08, 0x12, 0x25, 0x10, 0x22, 0xa8, 0x14, 0x24,
    0x00, 0x50, 0x24, 0x04]
  textureStarts = [0x00'u8, 0x18, 0x30, 0xc4, 0xdc, 0x65, 0xeb, 0x48,
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

type AgiPicture* = object
  visual*, priority*: VextRaster
  drawing*: VextRaster
  drawingSteps*: int

proc displayRaster(pixels: seq[uint8]): VextRaster =
  var image = VextIndexedImage(width: AgiPictureWidth * 2,
    height: AgiPictureHeight, palette: @AgiEgaPalette,
    pixels: newSeq[uint8](AgiPictureWidth * 2 * AgiPictureHeight))
  for y in 0 ..< AgiPictureHeight:
    for x in 0 ..< AgiPictureWidth:
      image.pixels[y * image.width + x * 2] = pixels[y * AgiPictureWidth + x]
      image.pixels[y * image.width + x * 2 + 1] = pixels[y * AgiPictureWidth + x]
  VextRaster(kind: vrkIndexedImage, image: image)

proc renderAgiPicture*(data: openArray[byte], captureProgress = false,
    progressStepsHint = 0): AgiPicture =
  var visual = newSeq[uint8](AgiPictureWidth * AgiPictureHeight)
  var priority = newSeq[uint8](visual.len)
  for pixel in visual.mitems: pixel = 15
  for pixel in priority.mitems: pixel = 4
  var visualOn, priorityOn = false
  var visualColour = 0'u8
  var priorityColour = 0'u8
  var pen = 0
  var at = 0
  var frames: seq[VextIndexedAnimationFrame]
  let stride = max(1, (progressStepsHint + 77) div 78)

  proc recordFrame(duration = 80) =
    if captureProgress and frames.len < 79:
      frames.add VextIndexedAnimationFrame(
        image: displayRaster(visual).image, durationMs: duration)

  if captureProgress: recordFrame()

  proc point(x, y: int) =
    if x < 0 or x >= AgiPictureWidth or y < 0 or y >= AgiPictureHeight: return
    let index = y * AgiPictureWidth + x
    if visualOn: visual[index] = visualColour
    if priorityOn: priority[index] = priorityColour

  proc agiRound(value, direction: float): int =
    let lower = floor(value)
    if direction < 0:
      int(if value - lower <= 0.501: lower else: ceil(value))
    else:
      int(if value - lower < 0.499: lower else: ceil(value))

  proc line(x1, y1, x2, y2: int) =
    let width = x2 - x1
    let height = y2 - y1
    if abs(width) > abs(height):
      let sx = if width < 0: -1 else: 1
      let sy = if width == 0: 0.0 else: float(height) / float(abs(width))
      var y = float(y1)
      var x = x1
      while x != x2:
        point(x, agiRound(y, sy)); x += sx; y += sy
      point(x2, y2)
    else:
      let sy = if height < 0: -1 else: 1
      let sx = if height == 0: 0.0 else: float(width) / float(abs(height))
      var x = float(x1)
      var y = y1
      while y != y2:
        point(agiRound(x, sx), y); y += sy; x += sx
      point(x2, y2)

  proc fill(x, y: int) =
    if x < 0 or x >= AgiPictureWidth or y < 0 or y >= AgiPictureHeight: return
    if (not visualOn or visualColour == 15) and
        (not priorityOn or priorityColour == 4): return
    proc eligible(index: int): bool =
      (not visualOn or visual[index] == 15) and
        (not priorityOn or priority[index] == 4)
    if (not visualOn and not priorityOn) or not eligible(y * AgiPictureWidth + x): return
    proc paint(index: int) =
      if visualOn: visual[index] = visualColour
      if priorityOn: priority[index] = priorityColour
    var queue = @[(x, y)]
    paint(y * AgiPictureWidth + x)
    var head = 0
    while head < queue.len:
      let (px, py) = queue[head]; inc head
      for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]:
        if nx >= 0 and nx < AgiPictureWidth and ny >= 0 and ny < AgiPictureHeight:
          let next = ny * AgiPictureWidth + nx
          if eligible(next):
            paint(next)
            queue.add (nx, ny)

  proc plot(texture, cx, cy: int) =
    let size = pen and 7
    let rectangle = (pen and 0x10) != 0
    let splatter = (pen and 0x20) != 0
    var bit = if splatter: int(textureStarts[(texture shr 1) mod textureStarts.len]) else: 0
    for dy in -size .. size:
      for dx in -(size div 2) .. (size + 1) div 2:
        let inside = rectangle or size == 0 or
          (dx * dx * 4 + dy * dy <= size * size + size)
        var textured = true
        if splatter:
          textured = ((textureBits[bit shr 3] shr (7 - (bit and 7))) and 1) != 0
          bit = (bit + 1) mod 255
        if inside and textured: point(cx + dx, cy + dy)

  template argument(): int =
    block:
      if at >= data.len or data[at] >= 0xf0:
        raise newException(ValueError, "truncated AGI PIC command")
      let value = int(data[at]); inc at; value

  while at < data.len:
    let command = data[at]; inc at
    var drew = false
    case command
    of 0xf0: visualColour = uint8(argument()); visualOn = true
    of 0xf1: visualOn = false
    of 0xf2: priorityColour = uint8(argument()); priorityOn = true
    of 0xf3: priorityOn = false
    of 0xf4, 0xf5:
      var x = argument(); var y = argument(); point(x, y)
      var vertical = command == 0xf4
      while at < data.len and data[at] < 0xf0:
        let value = argument()
        let nx = if vertical: x else: value
        let ny = if vertical: value else: y
        line(x, y, nx, ny); x = nx; y = ny; vertical = not vertical
      drew = true
    of 0xf6:
      var x = argument(); var y = argument(); point(x, y)
      while at < data.len and data[at] < 0xf0:
        let nx = argument(); let ny = argument()
        line(x, y, nx, ny); x = nx; y = ny
      drew = true
    of 0xf7:
      var x = argument(); var y = argument(); point(x, y)
      while at < data.len and data[at] < 0xf0:
        let value = argument()
        let dx = (value shr 4) and 7
        let dy = value and 7
        let nx = x + (if (value and 0x80) != 0: -dx else: dx)
        let ny = y + (if (value and 0x08) != 0: -dy else: dy)
        line(x, y, nx, ny); x = nx; y = ny
      drew = true
    of 0xf8:
      while at < data.len and data[at] < 0xf0:
        let x = argument(); let y = argument(); fill(x, y)
      drew = true
    of 0xf9: pen = argument()
    of 0xfa:
      while at < data.len and data[at] < 0xf0:
        let texture = if (pen and 0x20) != 0: argument() else: 0
        let x = argument(); let y = argument(); plot(texture, x, y)
      drew = true
    of 0xff:
      result.visual = displayRaster(visual)
      result.priority = displayRaster(priority)
      if captureProgress:
        let finalImage = result.visual.image
        if frames.len >= 1000: frames[^1] = VextIndexedAnimationFrame(
          image: finalImage, durationMs: 800)
        else: frames.add VextIndexedAnimationFrame(
          image: finalImage, durationMs: 800)
        result.drawing = VextRaster(kind: vrkIndexedAnimation,
          animation: VextIndexedAnimation(width: finalImage.width,
            height: finalImage.height, frames: frames))
      return
    else: raise newException(ValueError, "unsupported AGI PIC command")
    if drew:
      inc result.drawingSteps
      if result.drawingSteps mod stride == 0: recordFrame()
  raise newException(ValueError, "AGI PIC is missing its end marker")
