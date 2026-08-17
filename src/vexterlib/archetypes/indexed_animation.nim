## Generic indexed-colour image and animation values.

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

proc pixelAt*(image: VextIndexedImage, x, y: int): uint8 =
  ## Returns the palette index at `(x, y)`.
  if x < 0 or x >= image.width or y < 0 or y >= image.height:
    raise newException(IndexDefect, "indexed image coordinate is out of bounds")
  image.pixels[y * image.width + x]

proc colourAt*(image: VextIndexedImage, x, y: int): VextRgb =
  ## Returns the RGB colour at `(x, y)`.
  image.palette[int(image.pixelAt(x, y))]
