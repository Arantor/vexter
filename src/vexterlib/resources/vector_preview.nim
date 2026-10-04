## Bounded raster previews for format-neutral vector drawings.

import std/math
import ../archetypes/[raster, vector]

type
  ScreenPoint = object
    x, y: float64

  ScreenSubpath = object
    points: seq[ScreenPoint]
    closed: bool

proc blend(destination: var VextRgb, source: VextRgba) =
  let alpha = int(source.a)
  if alpha == 255:
    destination = source.rgb
  elif alpha != 0:
    destination.r = uint8((int(source.r) * alpha +
      int(destination.r) * (255 - alpha) + 127) div 255)
    destination.g = uint8((int(source.g) * alpha +
      int(destination.g) * (255 - alpha) + 127) div 255)
    destination.b = uint8((int(source.b) * alpha +
      int(destination.b) * (255 - alpha) + 127) div 255)

proc cubic(a, b, c, d: ScreenPoint, t: float64): ScreenPoint =
  let
    inverse = 1.0 - t
    aa = inverse * inverse * inverse
    bb = 3.0 * inverse * inverse * t
    cc = 3.0 * inverse * t * t
    dd = t * t * t
  ScreenPoint(x: aa * a.x + bb * b.x + cc * c.x + dd * d.x,
    y: aa * a.y + bb * b.y + cc * c.y + dd * d.y)

proc flatten(path: VextVectorPath, drawing: VextVectorDrawing,
    width, height: int): seq[ScreenSubpath] =
  let
    xSpan = drawing.bounds.right - drawing.bounds.left
    ySpan = drawing.bounds.bottom - drawing.bounds.top
  proc screen(point: VextVectorPoint): ScreenPoint =
    ScreenPoint(
      x: (point.x - drawing.bounds.left) / xSpan * float64(width),
      y: (point.y - drawing.bounds.top) / ySpan * float64(height))

  var current = -1
  for command in path.commands:
    case command.kind
    of vvckMove:
      result.add ScreenSubpath(points: @[screen(command.point)])
      current = result.high
    of vvckLine:
      if current >= 0: result[current].points.add screen(command.point)
    of vvckCubic:
      if current >= 0 and result[current].points.len > 0:
        let
          start = result[current].points[^1]
          control1 = screen(command.control1)
          control2 = screen(command.control2)
          finish = screen(command.point)
        for step in 1 .. 24:
          result[current].points.add cubic(start, control1, control2, finish,
            float64(step) / 24.0)
    of vvckClose:
      if current >= 0: result[current].closed = true

proc insideEvenOdd(subpaths: openArray[ScreenSubpath], point: ScreenPoint): bool =
  var crossings = 0
  for subpath in subpaths:
    if subpath.points.len < 3: continue
    for index in 0 ..< subpath.points.len:
      let
        a = subpath.points[index]
        b = subpath.points[(index + 1) mod subpath.points.len]
      if (a.y > point.y) != (b.y > point.y):
        let crossingX = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
        if crossingX > point.x: inc crossings
  (crossings and 1) != 0

proc segmentDistance(point, a, b: ScreenPoint): tuple[distance, along: float64] =
  let
    dx = b.x - a.x
    dy = b.y - a.y
    squared = dx * dx + dy * dy
  if squared == 0:
    return (hypot(point.x - a.x, point.y - a.y), 0.0)
  let position = max(0.0, min(1.0,
    ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared))
  (hypot(point.x - (a.x + position * dx),
    point.y - (a.y + position * dy)), position * sqrt(squared))

proc dashVisible(distance: float64, pattern: openArray[float64], scale: float64): bool =
  if pattern.len == 0: return true
  var cycle = 0.0
  for length in pattern: cycle += length * scale
  if cycle <= 0: return true
  var position = distance mod cycle
  for index, length in pattern:
    let scaledLength = length * scale
    if position < scaledLength: return (index and 1) == 0
    position -= scaledLength
  true

proc renderPath(image: var VextTrueColourImage, path: VextVectorPath,
    drawing: VextVectorDrawing, xScale, yScale: float64) =
  let subpaths = flatten(path, drawing, image.width, image.height)
  if subpaths.len == 0: return
  var
    minimumX = float64(image.width)
    minimumY = float64(image.height)
    maximumX = 0.0
    maximumY = 0.0
  for subpath in subpaths:
    for point in subpath.points:
      minimumX = min(minimumX, point.x)
      minimumY = min(minimumY, point.y)
      maximumX = max(maximumX, point.x)
      maximumY = max(maximumY, point.y)
  let
    strokeWidth = path.style.strokeWidth * (abs(xScale) + abs(yScale)) / 2.0
    margin = if path.style.hasStroke: strokeWidth / 2.0 + 1.0 else: 1.0
    left = max(0, int(floor(minimumX - margin)))
    top = max(0, int(floor(minimumY - margin)))
    right = min(image.width - 1, int(ceil(maximumX + margin)))
    bottom = min(image.height - 1, int(ceil(maximumY + margin)))
  if left > right or top > bottom: return

  for y in top .. bottom:
    for x in left .. right:
      var accumulatedR, accumulatedG, accumulatedB: int
      for sampleY in 0 .. 1:
        for sampleX in 0 .. 1:
          let sample = ScreenPoint(x: float64(x) + (float64(sampleX) + 0.5) / 2.0,
            y: float64(y) + (float64(sampleY) + 0.5) / 2.0)
          var colour = image.pixels[y * image.width + x]
          if path.style.hasFill and insideEvenOdd(subpaths, sample):
            colour.blend(path.style.fill)
          if path.style.hasStroke and strokeWidth > 0:
            var cumulative = 0.0
            var hit = false
            for subpath in subpaths:
              if subpath.points.len < 2: continue
              let segmentCount = subpath.points.len - 1 + ord(subpath.closed)
              for index in 0 ..< segmentCount:
                let
                  a = subpath.points[index]
                  b = subpath.points[(index + 1) mod subpath.points.len]
                  measured = segmentDistance(sample, a, b)
                  length = hypot(b.x - a.x, b.y - a.y)
                if measured.distance <= strokeWidth / 2.0 and
                    dashVisible(cumulative + measured.along,
                      path.style.dashPattern,
                      (abs(xScale) + abs(yScale)) / 2.0):
                  hit = true
                cumulative += length
            if hit: colour.blend(path.style.stroke)
          accumulatedR += int(colour.r)
          accumulatedG += int(colour.g)
          accumulatedB += int(colour.b)
      image.pixels[y * image.width + x] = VextRgb(
        r: uint8((accumulatedR + 2) div 4),
        g: uint8((accumulatedG + 2) div 4),
        b: uint8((accumulatedB + 2) div 4))

proc renderVectorDrawing*(drawing: VextVectorDrawing,
    maximumDimension = 1024): VextTrueColourImage =
  drawing.validate()
  if maximumDimension <= 0:
    raise newException(ValueError, "vector preview maximum dimension must be positive")
  let
    sourceWidth = abs(drawing.bounds.right - drawing.bounds.left)
    sourceHeight = abs(drawing.bounds.bottom - drawing.bounds.top)
    scale = float64(maximumDimension) / max(sourceWidth, sourceHeight)
    width = max(1, int(round(sourceWidth * scale)))
    height = max(1, int(round(sourceHeight * scale)))
    xScale = float64(width) / (drawing.bounds.right - drawing.bounds.left)
    yScale = float64(height) / (drawing.bounds.bottom - drawing.bounds.top)
    background = drawing.background.rgb
  var image = VextTrueColourImage(width: width, height: height,
    pixels: newSeq[VextRgb](width * height))
  for index in 0 ..< image.pixels.len: image.pixels[index] = background

  proc renderElement(element: VextVectorElement) =
    if not element.visible: return
    case element.kind
    of vvekPath:
      image.renderPath(element.path, drawing, xScale, yScale)
    of vvekGroup:
      for child in element.children: renderElement(child)
    else: discard
  for element in drawing.elements: renderElement(element)
  result = move(image)

proc vectorPreviewWarnings*(drawing: VextVectorDrawing): seq[string] =
  let counts = drawing.vectorElementCounts
  if counts.texts > 0:
    result.add "Text is retained structurally but omitted from this PNG preview because its source font is external."
  if counts.images > 0:
    result.add "External bitmap references are retained structurally but omitted from this PNG preview."
