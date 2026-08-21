## Raster decoding for Quite OK Image (QOI) sources.

import ../archetypes/raster
import ../containers/qoi

const
  QoiImageTypeId* = "qoi.image"
  QoiImageResourcePath* = "/image"

proc decodeQoi*(source: QoiImageSource): VextRaster =
  let pixelCount = source.width * source.height
  var pixels = newSeq[VextRgb](pixelCount)
  var alpha = newSeq[uint8](pixelCount)
  var index: array[64, VextRgba]
  var previous = VextRgba(r: 0, g: 0, b: 0, a: 255)
  var input = 0
  var output = 0
  var hasTransparency = false

  template store(pixel: VextRgba) =
    if output >= pixelCount:
      raise newException(ValueError, "QOI decoder produced excess pixels")
    pixels[output] = VextRgb(r: pixel.r, g: pixel.g, b: pixel.b)
    alpha[output] = pixel.a
    if pixel.a != 255: hasTransparency = true
    index[(int(pixel.r) * 3 + int(pixel.g) * 5 + int(pixel.b) * 7 +
      int(pixel.a) * 11) mod 64] = pixel
    previous = pixel
    inc output

  while input < source.chunks.len:
    let tag = source.chunks[input]
    inc input
    if tag == 0xfe:
      previous.r = source.chunks[input]
      previous.g = source.chunks[input + 1]
      previous.b = source.chunks[input + 2]
      input += 3
      store(previous)
    elif tag == 0xff:
      previous = VextRgba(r: source.chunks[input],
        g: source.chunks[input + 1], b: source.chunks[input + 2],
        a: source.chunks[input + 3])
      input += 4
      store(previous)
    else:
      case tag and 0xc0
      of 0x00:
        store(index[int(tag and 0x3f)])
      of 0x40:
        previous.r = uint8((int(previous.r) + int((tag shr 4) and 0x03) - 2) and 0xff)
        previous.g = uint8((int(previous.g) + int((tag shr 2) and 0x03) - 2) and 0xff)
        previous.b = uint8((int(previous.b) + int(tag and 0x03) - 2) and 0xff)
        store(previous)
      of 0x80:
        let second = source.chunks[input]
        inc input
        let dg = int(tag and 0x3f) - 32
        previous.r = uint8((int(previous.r) + dg + int(second shr 4) - 8) and 0xff)
        previous.g = uint8((int(previous.g) + dg) and 0xff)
        previous.b = uint8((int(previous.b) + dg + int(second and 0x0f) - 8) and 0xff)
        store(previous)
      else:
        for unused in 0 .. int(tag and 0x3f):
          store(previous)
  if output != pixelCount or input != source.chunks.len:
    raise newException(ValueError, "invalid QOI decoded pixel count")
  var image = VextTrueColourImage(width: source.width, height: source.height,
    pixels: pixels)
  if hasTransparency: image.alpha = alpha
  VextRaster(kind: vrkTrueColourImage, trueColourImage: image)
