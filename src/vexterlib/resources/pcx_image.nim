## Indexed and true-colour raster decoding for PCX image sources.

import ../archetypes/raster
import ../containers/pcx

const
  PcxImageTypeId* = "pcx.image"
  PcxImageResourcePath* = "/image"

type PcxChannelOrder* = enum
  pcoRgb
  pcoBgr

proc decodeRows(source: PcxImageSource): tuple[rows: seq[byte], used: int] =
  let rowSize = source.bytesPerLine * source.planes
  result.rows = newSeqOfCap[byte](rowSize * source.height)
  var offset = 0
  for y in 0 ..< source.height:
    let target = result.rows.len + rowSize
    while result.rows.len < target:
      if offset >= source.imageData.len:
        raise newException(ValueError, "truncated PCX image data")
      let control = source.imageData[offset]
      inc offset
      if source.encoding == 1 and (control and 0xc0) == 0xc0:
        let count = int(control and 0x3f)
        if count == 0 or offset >= source.imageData.len or
            count > target - result.rows.len:
          raise newException(ValueError, "invalid PCX RLE run")
        let value = source.imageData[offset]
        inc offset
        for unused in 0 ..< count:
          result.rows.add value
      else:
        result.rows.add control
  result.used = offset

proc paletteFromBytes(data: openArray[byte], count: int): seq[VextRgb] =
  for index in 0 ..< count:
    result.add VextRgb(r: data[index * 3], g: data[index * 3 + 1],
      b: data[index * 3 + 2])

proc decodePcx*(source: PcxImageSource,
    channelOrder = pcoRgb): VextRaster =
  let decoded = decodeRows(source)
  if source.bitsPerPixel == 8 and source.planes == 3:
    if decoded.used != source.imageData.len:
      raise newException(ValueError, "PCX image has trailing data")
    var image = VextTrueColourImage(width: source.width,
      height: source.height,
      pixels: newSeq[VextRgb](source.width * source.height))
    let rowSize = source.bytesPerLine * 3
    for y in 0 ..< source.height:
      let row = y * rowSize
      for x in 0 ..< source.width:
        let first = decoded.rows[row + x]
        let green = decoded.rows[row + source.bytesPerLine + x]
        let third = decoded.rows[row + source.bytesPerLine * 2 + x]
        image.pixels[y * source.width + x] =
          if channelOrder == pcoRgb: VextRgb(r: first, g: green, b: third)
          else: VextRgb(r: third, g: green, b: first)
    return VextRaster(kind: vrkTrueColourImage, trueColourImage: image)

  var palette: seq[VextRgb]
  if source.bitsPerPixel == 8 and source.planes == 1:
    if source.imageData.len - decoded.used != 769 or
        source.imageData[decoded.used] != 0x0c:
      raise newException(ValueError,
        "eight-bit indexed PCX requires a trailing 256-colour palette")
    palette = paletteFromBytes(source.imageData.toOpenArray(
      decoded.used + 1, source.imageData.high), 256)
  else:
    if decoded.used != source.imageData.len:
      raise newException(ValueError, "PCX image has trailing data")
    palette = paletteFromBytes(source.headerPalette,
      1 shl (source.bitsPerPixel * source.planes))

  var image = VextIndexedImage(width: source.width, height: source.height,
    palette: palette, pixels: newSeq[uint8](source.width * source.height))
  let rowSize = source.bytesPerLine * source.planes
  let mask = (1 shl source.bitsPerPixel) - 1
  for y in 0 ..< source.height:
    let row = y * rowSize
    for x in 0 ..< source.width:
      var index = 0
      for plane in 0 ..< source.planes:
        let bitOffset = x * source.bitsPerPixel
        let shift = 8 - source.bitsPerPixel - (bitOffset mod 8)
        let value = (int(decoded.rows[row + plane * source.bytesPerLine +
          bitOffset div 8]) shr shift) and mask
        index = index or (value shl (plane * source.bitsPerPixel))
      image.pixels[y * source.width + x] = uint8(index)
  VextRaster(kind: vrkIndexedImage, image: image)
