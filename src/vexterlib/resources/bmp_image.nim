## Raster decoding for BMP and standalone DIB image sources.

import ../archetypes/raster
import ../containers/bmp

const
  BmpImageTypeId* = "windows.bitmap"
  BmpImageResourcePath* = "/image"

proc palette(source: BmpImageSource): seq[VextRgb] =
  let count = source.palette.len div source.paletteEntrySize
  for index in 0 ..< count:
    let offset = index * source.paletteEntrySize
    result.add VextRgb(r: source.palette[offset + 2],
      g: source.palette[offset + 1], b: source.palette[offset])

proc maskComponent(value, mask: uint32): uint8 =
  if mask == 0: return 0
  var shift = 0
  var shifted = mask
  while (shifted and 1) == 0:
    inc shift
    shifted = shifted shr 1
  if (shifted and (shifted + 1)) != 0:
    raise newException(ValueError, "BMP/DIB colour masks must be contiguous")
  let component = (value and mask) shr shift
  uint8((component * 255'u32 + shifted div 2) div shifted)

proc defaultMasks(source: BmpImageSource): tuple[r, g, b: uint32] =
  if source.compression == 3:
    (source.redMask, source.greenMask, source.blueMask)
  elif source.bitsPerPixel == 16:
    (0x7c00'u32, 0x03e0'u32, 0x001f'u32)
  else:
    (0x00ff0000'u32, 0x0000ff00'u32, 0x000000ff'u32)

proc decodeRle(source: BmpImageSource): seq[uint8] =
  result = newSeq[uint8](source.width * source.height)
  var x = 0
  var y = source.height - 1
  var offset = 0
  var ended = false
  template put(value: int) =
    if x < 0 or x >= source.width or y < 0 or y >= source.height:
      raise newException(ValueError, "BMP RLE writes outside the image")
    result[y * source.width + x] = uint8(value)
    inc x
  while offset < source.pixelData.len and not ended:
    if source.pixelData.len - offset < 2:
      raise newException(ValueError, "truncated BMP RLE command")
    let count = int(source.pixelData[offset])
    let value = int(source.pixelData[offset + 1])
    offset += 2
    if count > 0:
      for index in 0 ..< count:
        put(if source.bitsPerPixel == 8: value
          elif index mod 2 == 0: value shr 4 else: value and 0x0f)
    else:
      case value
      of 0:
        x = 0
        dec y
      of 1:
        ended = true
      of 2:
        if source.pixelData.len - offset < 2:
          raise newException(ValueError, "truncated BMP RLE delta")
        x += int(source.pixelData[offset])
        y -= int(source.pixelData[offset + 1])
        offset += 2
      else:
        let bytes = if source.bitsPerPixel == 8: value else: (value + 1) div 2
        if bytes > source.pixelData.len - offset:
          raise newException(ValueError, "truncated BMP RLE literal")
        for index in 0 ..< value:
          let packed = int(source.pixelData[offset +
            (if source.bitsPerPixel == 8: index else: index div 2)])
          put(if source.bitsPerPixel == 8: packed
            elif index mod 2 == 0: packed shr 4 else: packed and 0x0f)
        offset += bytes
        if bytes mod 2 != 0: inc offset
        if offset > source.pixelData.len:
          raise newException(ValueError, "truncated BMP RLE padding")
  if not ended:
    raise newException(ValueError, "BMP RLE stream has no end marker")

proc decodeBmp*(source: BmpImageSource): VextRaster =
  if source.bitsPerPixel <= 8:
    var image = VextIndexedImage(width: source.width, height: source.height,
      palette: palette(source))
    if source.compression in [1, 2]:
      image.pixels = decodeRle(source)
    else:
      image.pixels = newSeq[uint8](source.width * source.height)
      let rowBytes = ((source.width * source.bitsPerPixel + 31) div 32) * 4
      if rowBytes * source.height > source.pixelData.len:
        raise newException(ValueError, "truncated BMP/DIB pixel rows")
      for outputY in 0 ..< source.height:
        let storedY = if source.topDown: outputY else: source.height - 1 - outputY
        let row = storedY * rowBytes
        for x in 0 ..< source.width:
          let bit = x * source.bitsPerPixel
          let shift = 8 - source.bitsPerPixel - (bit mod 8)
          image.pixels[outputY * source.width + x] = uint8(
            (int(source.pixelData[row + bit div 8]) shr shift) and
              ((1 shl source.bitsPerPixel) - 1))
    return VextRaster(kind: vrkIndexedImage, image: image)

  let rowBytes = ((source.width * source.bitsPerPixel + 31) div 32) * 4
  if rowBytes * source.height > source.pixelData.len:
    raise newException(ValueError, "truncated BMP/DIB pixel rows")
  let masks = defaultMasks(source)
  if masks.r == 0 or masks.g == 0 or masks.b == 0 or
      (masks.r and masks.g) != 0 or (masks.r and masks.b) != 0 or
      (masks.g and masks.b) != 0:
    raise newException(ValueError, "invalid BMP/DIB colour masks")
  var image = VextTrueColourImage(width: source.width, height: source.height,
    pixels: newSeq[VextRgb](source.width * source.height))
  for outputY in 0 ..< source.height:
    let storedY = if source.topDown: outputY else: source.height - 1 - outputY
    let row = storedY * rowBytes
    for x in 0 ..< source.width:
      let offset = row + x * (source.bitsPerPixel div 8)
      var value = uint32(source.pixelData[offset]) or
        (uint32(source.pixelData[offset + 1]) shl 8)
      if source.bitsPerPixel >= 24:
        value = value or (uint32(source.pixelData[offset + 2]) shl 16)
      if source.bitsPerPixel == 32:
        value = value or (uint32(source.pixelData[offset + 3]) shl 24)
      image.pixels[outputY * source.width + x] = VextRgb(
        r: maskComponent(value, masks.r), g: maskComponent(value, masks.g),
        b: maskComponent(value, masks.b))
  VextRaster(kind: vrkTrueColourImage, trueColourImage: image)
