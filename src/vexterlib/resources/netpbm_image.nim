## Raster conversion for documented visual NetPBM and PAM images.

import std/strutils
import ../archetypes/raster
import ../containers/netpbm

const
  NetpbmImageTypeId* = "netpbm.image"
  NetpbmImageResourcePath* = "/image"

proc scaled(value: uint16, maximum: int): uint8 {.inline.} =
  uint8((uint32(value) * 255'u32 + uint32(maximum div 2)) div uint32(maximum))

proc decodeNetpbm*(source: NetpbmImageSource): VextRaster =
  let count = source.width * source.height
  if source.samples.len != count * source.depth:
    raise newException(ValueError, "NetPBM sample buffer has the wrong length")

  if source.variant in [npvPlainPbm, npvRawPbm]:
    var image = VextIndexedImage(width: source.width, height: source.height,
      palette: @[VextRgb(r: 255, g: 255, b: 255), VextRgb()],
      pixels: newSeq[uint8](count))
    for index, value in source.samples: image.pixels[index] = uint8(value)
    return VextRaster(kind: vrkIndexedImage, image: image)

  var colourChannels: int
  var alphaChannel = -1
  if source.variant in [npvPlainPgm, npvRawPgm]:
    colourChannels = 1
  elif source.variant in [npvPlainPpm, npvRawPpm]:
    colourChannels = 3
  else:
    case source.tupleType
    of "BLACKANDWHITE", "GRAYSCALE": colourChannels = 1
    of "RGB": colourChannels = 3
    of "BLACKANDWHITE_ALPHA", "GRAYSCALE_ALPHA":
      colourChannels = 1
      alphaChannel = 1
    of "RGB_ALPHA":
      colourChannels = 3
      alphaChannel = 3
    else:
      raise newException(ValueError,
        "unsupported PAM tuple type: " & source.tupleType)
    if source.tupleType.startsWith("BLACKANDWHITE") and source.maxValue != 1:
      raise newException(ValueError, "PAM BLACKANDWHITE maxval must be one")
    let requiredDepth = colourChannels + (if alphaChannel >= 0: 1 else: 0)
    if source.depth < requiredDepth:
      raise newException(ValueError, "PAM depth is inconsistent with tuple type")

  var image = VextTrueColourImage(width: source.width, height: source.height,
    pixels: newSeq[VextRgb](count))
  if alphaChannel >= 0: image.alpha = newSeq[uint8](count)
  for index in 0 ..< count:
    let sampleOffset = index * source.depth
    if source.variant == npvPam and source.tupleType.startsWith("BLACKANDWHITE"):
      let value = if source.samples[sampleOffset] == 0: 0'u8 else: 255'u8
      image.pixels[index] = VextRgb(r: value, g: value, b: value)
    elif colourChannels == 1:
      let value = scaled(source.samples[sampleOffset], source.maxValue)
      image.pixels[index] = VextRgb(r: value, g: value, b: value)
    else:
      image.pixels[index] = VextRgb(
        r: scaled(source.samples[sampleOffset], source.maxValue),
        g: scaled(source.samples[sampleOffset + 1], source.maxValue),
        b: scaled(source.samples[sampleOffset + 2], source.maxValue))
    if alphaChannel >= 0:
      image.alpha[index] = scaled(source.samples[sampleOffset + alphaChannel],
        source.maxValue)
  VextRaster(kind: vrkTrueColourImage, trueColourImage: image)
