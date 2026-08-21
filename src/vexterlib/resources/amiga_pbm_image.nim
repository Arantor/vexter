## Indexed raster decoding for provisional IFF FORM PBM chunky images.

import ../archetypes/raster
import ./amiga_ilbm_image

const
  AmigaPbmImageTypeId* = "amiga.pbm-image"
  AmigaPbmImageResourcePath* = "/image"

type AmigaPbmImageSource* = object
  header*: AmigaIlbmHeader
  colourMap*: seq[byte]
  body*: seq[byte]

proc decodeRow(body: openArray[byte], offset: var int, rowBytes,
    compression: int): seq[byte] =
  result = newSeqOfCap[byte](rowBytes)
  if compression == 0:
    if rowBytes > body.len - offset:
      raise newException(ValueError, "truncated uncompressed IFF PBM BODY row")
    if rowBytes > 0: result.add body.toOpenArray(offset, offset + rowBytes - 1)
    offset += rowBytes
    return
  while result.len < rowBytes:
    if offset >= body.len:
      raise newException(ValueError, "truncated ByteRun1 IFF PBM BODY row")
    let control = int(cast[int8](body[offset]))
    inc offset
    if control >= 0:
      let count = control + 1
      if count > rowBytes - result.len or count > body.len - offset:
        raise newException(ValueError, "invalid IFF PBM ByteRun1 literal")
      result.add body.toOpenArray(offset, offset + count - 1)
      offset += count
    elif control >= -127:
      let count = 1 - control
      if count > rowBytes - result.len or offset >= body.len:
        raise newException(ValueError, "invalid IFF PBM ByteRun1 repeat")
      let value = body[offset]
      inc offset
      for unused in 0 ..< count: result.add value
    else:
      discard

proc decodeAmigaPbm*(source: AmigaPbmImageSource): VextRaster =
  let header = source.header
  if header.width <= 0 or header.height <= 0:
    raise newException(ValueError, "IFF PBM dimensions must be positive")
  let rowBytes = (header.width + 1) and not 1
  var pixels = newSeq[uint8](header.width * header.height)
  var offset = 0
  for y in 0 ..< header.height:
    let row = decodeRow(source.body, offset, rowBytes, header.compression)
    for x in 0 ..< header.width: pixels[y * header.width + x] = row[x]
  if offset != source.body.len:
    raise newException(ValueError, "IFF PBM BODY has trailing image data")

  var palette: seq[VextRgb]
  for colourOffset in countup(0, source.colourMap.len - 3, 3):
    palette.add VextRgb(r: source.colourMap[colourOffset],
      g: source.colourMap[colourOffset + 1],
      b: source.colourMap[colourOffset + 2])
  while palette.len < 256: palette.add VextRgb()
  if palette.len > 256: palette.setLen(256)

  var alpha: seq[uint8]
  if header.masking == AmigaIlbmMaskTransparentColour:
    alpha = newSeq[uint8](pixels.len)
    for index, value in pixels:
      alpha[index] = if int(value) == header.transparentColour: 0'u8 else: 255'u8
  VextRaster(kind: vrkIndexedImage, image: VextIndexedImage(
    width: header.width, height: header.height, palette: palette,
    pixels: pixels, alpha: alpha))
