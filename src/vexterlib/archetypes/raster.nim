## Generic raster image and animation values.

type
  VextRgb* = object
    r*, g*, b*: uint8

  VextIndexedImage* = object
    width*, height*: int
    palette*: seq[VextRgb]
    pixels*: seq[uint8]

  VextIndexedAnimationFrame* = object
    image*: VextIndexedImage
    durationMs*: int

  VextIndexedAnimation* = object
    width*, height*: int
    frames*: seq[VextIndexedAnimationFrame]

  VextRasterKind* = enum
    vrkIndexedImage
    vrkIndexedAnimation

  VextRaster* = object
    case kind*: VextRasterKind
    of vrkIndexedImage:
      image*: VextIndexedImage
    of vrkIndexedAnimation:
      animation*: VextIndexedAnimation

proc pixelAt*(image: VextIndexedImage, x, y: int): uint8 =
  ## Returns the palette index at `(x, y)`.
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "indexed image coordinate is out of bounds")
  image.pixels[y * image.width + x]

proc colourAt*(image: VextIndexedImage, x, y: int): VextRgb =
  ## Returns the RGB colour at `(x, y)`.
  image.palette[int(image.pixelAt(x, y))]

proc width*(raster: VextRaster): int =
  case raster.kind
  of vrkIndexedImage: raster.image.width
  of vrkIndexedAnimation: raster.animation.width

proc height*(raster: VextRaster): int =
  case raster.kind
  of vrkIndexedImage: raster.image.height
  of vrkIndexedAnimation: raster.animation.height

proc archetypeName*(raster: VextRaster): string =
  case raster.kind
  of vrkIndexedImage: "VextIndexedImage"
  of vrkIndexedAnimation: "VextIndexedAnimation"

proc naturalImage*(raster: VextRaster): VextIndexedImage =
  ## Returns a static raster directly or the natural first animation frame.
  case raster.kind
  of vrkIndexedImage:
    raster.image
  of vrkIndexedAnimation:
    if raster.animation.frames.len == 0:
      raise newException(ValueError, "indexed animation contains no frames")
    raster.animation.frames[0].image

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
