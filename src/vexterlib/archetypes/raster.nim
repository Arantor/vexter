## Generic raster image and animation values.

type
  VextRgb* = object
    r*, g*, b*: uint8

  VextRgba* = object
    r*, g*, b*, a*: uint8

  VextColourCycleRange* = object
    low*, high*: int
    direction*: int
    stepDurationMs*: int

  VextIndexedImage* = object
    width*, height*: int
    palette*: seq[VextRgb]
    pixels*: seq[uint8]
    alpha*: seq[uint8]
    colourCycles*: seq[VextColourCycleRange]

  VextTrueColourImage* = object
    width*, height*: int
    pixels*: seq[VextRgb]
    alpha*: seq[uint8]

  VextTrueColourAnimationFrame* = object
    image*: VextTrueColourImage
    durationMs*: int

  VextTrueColourAnimation* = object
    width*, height*: int
    frames*: seq[VextTrueColourAnimationFrame]

  VextIndexedAnimationFrame* = object
    image*: VextIndexedImage
    durationMs*: int

  VextIndexedAnimation* = object
    width*, height*: int
    frames*: seq[VextIndexedAnimationFrame]
    colourCycles*: seq[VextColourCycleRange]

  VextRasterKind* = enum
    vrkIndexedImage
    vrkIndexedAnimation
    vrkTrueColourImage
    vrkTrueColourAnimation

  VextRaster* = object
    case kind*: VextRasterKind
    of vrkIndexedImage:
      image*: VextIndexedImage
    of vrkIndexedAnimation:
      animation*: VextIndexedAnimation
    of vrkTrueColourImage:
      trueColourImage*: VextTrueColourImage
    of vrkTrueColourAnimation:
      trueColourAnimation*: VextTrueColourAnimation

proc rgba*(colour: VextRgb, alpha = 255'u8): VextRgba =
  VextRgba(r: colour.r, g: colour.g, b: colour.b, a: alpha)

proc rgb*(colour: VextRgba): VextRgb =
  VextRgb(r: colour.r, g: colour.g, b: colour.b)

proc pixelAt*(image: VextIndexedImage, x, y: int): uint8 =
  ## Returns the palette index at `(x, y)`.
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "indexed image coordinate is out of bounds")
  image.pixels[y * image.width + x]

proc colourAt*(image: VextIndexedImage, x, y: int): VextRgb =
  ## Returns the RGB colour at `(x, y)`.
  image.palette[int(image.pixelAt(x, y))]

proc colourAt*(image: VextTrueColourImage, x, y: int): VextRgb =
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "true-colour image coordinate is out of bounds")
  image.pixels[y * image.width + x]

proc alphaAt*(image: VextIndexedImage, x, y: int): uint8 =
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "indexed image coordinate is out of bounds")
  if image.alpha.len == 0: 255'u8
  elif image.alpha.len != image.width * image.height:
    raise newException(ValueError, "indexed alpha buffer has the wrong length")
  else: image.alpha[y * image.width + x]

proc alphaAt*(image: VextTrueColourImage, x, y: int): uint8 =
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "true-colour image coordinate is out of bounds")
  if image.alpha.len == 0: 255'u8
  elif image.alpha.len != image.width * image.height:
    raise newException(ValueError, "true-colour alpha buffer has the wrong length")
  else: image.alpha[y * image.width + x]

proc rgbaAt*(image: VextIndexedImage, x, y: int): VextRgba =
  let colour = image.colourAt(x, y)
  VextRgba(r: colour.r, g: colour.g, b: colour.b, a: image.alphaAt(x, y))

proc rgbaAt*(image: VextTrueColourImage, x, y: int): VextRgba =
  let colour = image.colourAt(x, y)
  VextRgba(r: colour.r, g: colour.g, b: colour.b, a: image.alphaAt(x, y))

proc hasAlpha*(image: VextIndexedImage): bool =
  if image.alpha.len == 0: return false
  if image.alpha.len != image.width * image.height:
    raise newException(ValueError, "indexed alpha buffer has the wrong length")
  for value in image.alpha:
    if value != 255: return true

proc hasAlpha*(image: VextTrueColourImage): bool =
  if image.alpha.len == 0: return false
  if image.alpha.len != image.width * image.height:
    raise newException(ValueError, "true-colour alpha buffer has the wrong length")
  for value in image.alpha:
    if value != 255: return true

proc width*(raster: VextRaster): int =
  case raster.kind
  of vrkIndexedImage: raster.image.width
  of vrkIndexedAnimation: raster.animation.width
  of vrkTrueColourImage: raster.trueColourImage.width
  of vrkTrueColourAnimation: raster.trueColourAnimation.width

proc height*(raster: VextRaster): int =
  case raster.kind
  of vrkIndexedImage: raster.image.height
  of vrkIndexedAnimation: raster.animation.height
  of vrkTrueColourImage: raster.trueColourImage.height
  of vrkTrueColourAnimation: raster.trueColourAnimation.height

proc archetypeName*(raster: VextRaster): string =
  case raster.kind
  of vrkIndexedImage: "VextIndexedImage"
  of vrkIndexedAnimation: "VextIndexedAnimation"
  of vrkTrueColourImage: "VextTrueColourImage"
  of vrkTrueColourAnimation: "VextTrueColourAnimation"

proc naturalImage*(raster: VextRaster): VextIndexedImage =
  ## Returns a static raster directly or the natural first animation frame.
  case raster.kind
  of vrkIndexedImage:
    raster.image
  of vrkIndexedAnimation:
    if raster.animation.frames.len == 0:
      raise newException(ValueError, "indexed animation contains no frames")
    raster.animation.frames[0].image
  of vrkTrueColourImage, vrkTrueColourAnimation:
    raise newException(ValueError,
      "true-colour raster has no indexed natural image")

proc asIndexedAnimation*(raster: VextRaster): VextIndexedAnimation =
  ## Returns an animation directly or wraps an image as a one-frame animation.
  case raster.kind
  of vrkIndexedAnimation:
    raster.animation
  of vrkIndexedImage:
    VextIndexedAnimation(
      width: raster.image.width,
      height: raster.image.height,
      frames: @[VextIndexedAnimationFrame(
        image: raster.image,
        durationMs: 0)])
  of vrkTrueColourImage, vrkTrueColourAnimation:
    raise newException(ValueError,
      "true-colour raster cannot be converted to indexed animation")
