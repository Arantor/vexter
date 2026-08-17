## Indexed raster decoding for Amiga IFF ILBM image data.

import ../archetypes/raster

const
  AmigaIlbmImageTypeId* = "amiga.ilbm-image"
  AmigaIlbmImageResourcePath* = "/image"
  AmigaIlbmCamgHam* = 0x0800'u32
  AmigaIlbmCamgEhb* = 0x0080'u32

type
  AmigaIlbmHeader* = object
    width*, height*: int
    x*, y*: int
    planes*: int
    masking*: int
    compression*: int
    transparentColour*: int
    xAspect*, yAspect*: int
    pageWidth*, pageHeight*: int

  AmigaIlbmImageSource* = object
    header*: AmigaIlbmHeader
    colourMap*: seq[byte]
    body*: seq[byte]
    camg*: uint32

proc decodeRow(body: openArray[byte], offset: var int, rowBytes,
    compression: int): seq[byte] =
  result = newSeqOfCap[byte](rowBytes)
  if compression == 0:
    if rowBytes > body.len - offset:
      raise newException(ValueError, "truncated uncompressed ILBM BODY row")
    result.add body.toOpenArray(offset, offset + rowBytes - 1)
    offset += rowBytes
    return
  if compression != 1:
    raise newException(ValueError, "unsupported ILBM compression")

  while result.len < rowBytes:
    if offset >= body.len:
      raise newException(ValueError, "truncated ByteRun1 ILBM BODY row")
    let control = int(cast[int8](body[offset]))
    inc offset
    if control >= 0:
      let count = control + 1
      if count > rowBytes - result.len or count > body.len - offset:
        raise newException(ValueError, "invalid ByteRun1 literal run")
      result.add body.toOpenArray(offset, offset + count - 1)
      offset += count
    elif control >= -127:
      let count = 1 - control
      if count > rowBytes - result.len or offset >= body.len:
        raise newException(ValueError, "invalid ByteRun1 repeated run")
      let value = body[offset]
      inc offset
      for unused in 0 ..< count:
        result.add value
    else:
      discard # -128 is a no-op.

proc decodePalette(source: AmigaIlbmImageSource): seq[VextRgb] =
  if source.colourMap.len mod 3 != 0:
    raise newException(ValueError, "ILBM CMAP length must be divisible by three")
  var legacyFourBit = source.colourMap.len > 0
  for component in source.colourMap:
    if (component and 0x0f'u8) != 0:
      legacyFourBit = false
      break
  for offset in countup(0, source.colourMap.len - 3, 3):
    template expanded(value: byte): uint8 =
      (if legacyFourBit: value or (value shr 4) else: value)
    result.add VextRgb(
      r: expanded(source.colourMap[offset]),
      g: expanded(source.colourMap[offset + 1]),
      b: expanded(source.colourMap[offset + 2]))

proc validateDimensions(header: AmigaIlbmHeader) =
  if header.width <= 0 or header.height <= 0:
    raise newException(ValueError, "ILBM dimensions must be positive")
  if header.masking != 0:
    raise newException(ValueError,
      "masked ILBM images require an alpha-capable raster archetype")

proc decodeCodes(source: AmigaIlbmImageSource): seq[uint8] =
  let header = source.header
  result = newSeq[uint8](header.width * header.height)
  let rowBytes = ((header.width + 15) div 16) * 2
  var bodyOffset = 0
  for y in 0 ..< header.height:
    for plane in 0 ..< header.planes:
      let row = decodeRow(source.body, bodyOffset, rowBytes,
        header.compression)
      for x in 0 ..< header.width:
        if (row[x div 8] and (0x80'u8 shr (x mod 8))) != 0:
          result[y * header.width + x] =
            result[y * header.width + x] or uint8(1 shl plane)
  if bodyOffset != source.body.len:
    raise newException(ValueError, "ILBM BODY has trailing image data")

proc decodeAmigaIlbmImage*(source: AmigaIlbmImageSource): VextIndexedImage =
  let header = source.header
  validateDimensions(header)
  if (source.camg and AmigaIlbmCamgHam) != 0:
    raise newException(ValueError,
      "HAM and HAM8 ILBM images require a true-colour raster archetype")
  let ehb = (source.camg and AmigaIlbmCamgEhb) != 0
  if (ehb and header.planes != 6) or (not ehb and header.planes notin 1 .. 5):
    raise newException(ValueError,
      "indexed ILBM decoding supports one to five planes or six-plane EHB")

  result = VextIndexedImage(
    width: header.width,
    height: header.height,
    palette: decodePalette(source),
    pixels: decodeCodes(source))
  let requiredColours = if ehb: 32 else: 1 shl header.planes
  while result.palette.len < requiredColours:
    result.palette.add VextRgb()
  if ehb:
    result.palette.setLen(32)
    for index in 0 ..< 32:
      let colour = result.palette[index]
      result.palette.add VextRgb(
        r: colour.r shr 1, g: colour.g shr 1, b: colour.b shr 1)
  elif result.palette.len > requiredColours:
    result.palette.setLen(requiredColours)


proc decodeAmigaIlbmHam*(source: AmigaIlbmImageSource): VextTrueColourImage =
  let header = source.header
  validateDimensions(header)
  if (source.camg and AmigaIlbmCamgHam) == 0:
    raise newException(ValueError, "ILBM does not select HAM mode")
  if header.planes notin [5, 6, 7, 8]:
    raise newException(ValueError, "HAM ILBM requires five to eight planes")

  let
    dataBits = header.planes - (if header.planes mod 2 == 0: 2 else: 1)
    dataMask = (1 shl dataBits) - 1
    maximum = dataMask
    codes = decodeCodes(source)
  var palette = decodePalette(source)
  while palette.len < (1 shl dataBits):
    palette.add VextRgb()
  result = VextTrueColourImage(
    width: header.width, height: header.height,
    pixels: newSeq[VextRgb](header.width * header.height))

  for y in 0 ..< header.height:
    var held = VextRgb()
    for x in 0 ..< header.width:
      let
        code = int(codes[y * header.width + x])
        value = code and dataMask
        mode = code shr dataBits
        expanded = uint8((value * 255) div maximum)
      case mode
      of 0: held = palette[value]
      of 1: held.b = expanded
      of 2: held.r = expanded
      of 3: held.g = expanded
      else:
        raise newException(ValueError, "invalid HAM modifier code")
      result.pixels[y * header.width + x] = held

proc decodeAmigaIlbmRaster*(source: AmigaIlbmImageSource): VextRaster =
  if (source.camg and AmigaIlbmCamgHam) != 0:
    VextRaster(kind: vrkTrueColourImage,
      trueColourImage: decodeAmigaIlbmHam(source))
  else:
    VextRaster(kind: vrkIndexedImage,
      image: decodeAmigaIlbmImage(source))
