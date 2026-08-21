## Indexed, grayscale, and true-colour raster decoding for TGA images.

import ../archetypes/raster
import ../containers/tga

const
  TgaImageTypeId* = "tga.image"
  TgaImageResourcePath* = "/image"

proc expandColour(data: openArray[byte], offset, bits, attributeBits: int):
    VextRgba =
  case bits
  of 16:
    let value = int(data[offset]) or (int(data[offset + 1]) shl 8)
    result = VextRgba(r: uint8(((value shr 10) and 0x1f) shl 3),
      g: uint8(((value shr 5) and 0x1f) shl 3),
      b: uint8((value and 0x1f) shl 3), a: 255)
    if attributeBits == 1:
      result.a = if (value and 0x8000) != 0: 255 else: 0
  of 24:
    result = VextRgba(r: data[offset + 2], g: data[offset + 1],
      b: data[offset], a: 255)
  of 32:
    result = VextRgba(r: data[offset + 2], g: data[offset + 1],
      b: data[offset],
      a: if attributeBits == 8: data[offset + 3] else: 255)
  else:
    raise newException(ValueError, "unsupported TGA colour size")

proc decodeSamples(source: TgaImageSource): seq[byte] =
  let pixelBytes = source.pixelBits div 8
  let pixelCount = source.width * source.height
  result = newSeqOfCap[byte](pixelCount * pixelBytes)
  var offset = 0
  template addSample() =
    if pixelBytes > source.imageData.len - offset:
      raise newException(ValueError, "truncated TGA pixel value")
    result.add source.imageData.toOpenArray(offset, offset + pixelBytes - 1)
    offset += pixelBytes
  if source.imageType in [1, 2, 3]:
    result = source.imageData
    offset = source.imageData.len
  else:
    while result.len div pixelBytes < pixelCount:
      if offset >= source.imageData.len:
        raise newException(ValueError, "truncated TGA RLE packet")
      let header = source.imageData[offset]
      inc offset
      let count = int(header and 0x7f) + 1
      if count > pixelCount - result.len div pixelBytes:
        raise newException(ValueError, "TGA RLE packet exceeds the image dimensions")
      if (header and 0x80) != 0:
        if pixelBytes > source.imageData.len - offset:
          raise newException(ValueError, "truncated TGA pixel value")
        let sampleOffset = offset
        offset += pixelBytes
        for unused in 0 ..< count:
          result.add source.imageData.toOpenArray(sampleOffset,
            sampleOffset + pixelBytes - 1)
      else:
        for unused in 0 ..< count: addSample()
  if offset != source.imageData.len or result.len != pixelCount * pixelBytes:
    raise newException(ValueError, "invalid TGA decoded pixel count")

proc destinationIndex(source: TgaImageSource, sequentialIndex: int): int =
  let sourceY = sequentialIndex div source.width
  let x = sequentialIndex mod source.width
  let y = if source.topOrigin: sourceY else: source.height - 1 - sourceY
  y * source.width + x

proc decodeTga*(source: TgaImageSource): VextRaster =
  let samples = decodeSamples(source)
  let pixelCount = source.width * source.height

  if source.imageType in [1, 9]:
    let entryBytes = source.colourMapEntryBits div 8
    var palette = newSeq[VextRgb](source.colourMapLength)
    var paletteAlpha = newSeq[uint8](source.colourMapLength)
    var hasTransparency = false
    for index in 0 ..< source.colourMapLength:
      let colour = expandColour(source.colourMap, index * entryBytes,
        source.colourMapEntryBits,
        if source.colourMapEntryBits == 16: 1 else: source.colourMapEntryBits - 24)
      palette[index] = VextRgb(r: colour.r, g: colour.g, b: colour.b)
      paletteAlpha[index] = colour.a
      if colour.a != 255: hasTransparency = true
    var image = VextIndexedImage(width: source.width, height: source.height,
      palette: palette, pixels: newSeq[uint8](pixelCount))
    if hasTransparency: image.alpha = newSeq[uint8](pixelCount)
    let pixelBytes = source.pixelBits div 8
    for sequentialIndex in 0 ..< pixelCount:
      let sampleOffset = sequentialIndex * pixelBytes
      let storedIndex = int(samples[sampleOffset]) or
        (if pixelBytes == 2: int(samples[sampleOffset + 1]) shl 8 else: 0)
      let normalized = storedIndex - source.colourMapOrigin
      if normalized < 0 or normalized >= source.colourMapLength:
        raise newException(ValueError, "TGA pixel index is outside its colour map")
      let destination = destinationIndex(source, sequentialIndex)
      image.pixels[destination] = uint8(normalized)
      if hasTransparency: image.alpha[destination] = paletteAlpha[normalized]
    return VextRaster(kind: vrkIndexedImage, image: image)

  var image = VextTrueColourImage(width: source.width, height: source.height,
    pixels: newSeq[VextRgb](pixelCount))
  let hasAlpha = source.imageType in [2, 10] and source.attributeBits > 0
  if hasAlpha: image.alpha = newSeq[uint8](pixelCount)
  let pixelBytes = source.pixelBits div 8
  for sequentialIndex in 0 ..< pixelCount:
    let sampleOffset = sequentialIndex * pixelBytes
    let colour = if source.imageType in [3, 11]:
        VextRgba(r: samples[sampleOffset], g: samples[sampleOffset],
          b: samples[sampleOffset], a: 255)
      else: expandColour(samples, sampleOffset, source.pixelBits,
        source.attributeBits)
    let destination = destinationIndex(source, sequentialIndex)
    image.pixels[destination] = VextRgb(r: colour.r, g: colour.g, b: colour.b)
    if hasAlpha: image.alpha[destination] = colour.a
  VextRaster(kind: vrkTrueColourImage, trueColourImage: image)
