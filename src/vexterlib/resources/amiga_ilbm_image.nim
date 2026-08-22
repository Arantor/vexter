## Indexed raster decoding for Amiga IFF ILBM image data.

import ../archetypes/raster

const
  AmigaIlbmImageTypeId* = "amiga.ilbm-image"
  AmigaIlbmImageResourcePath* = "/image"
  AmigaIlbmCamgHam* = 0x0800'u32
  AmigaIlbmCamgEhb* = 0x0080'u32
  AmigaIlbmCamgMonitorMask* = 0xffff0000'u32
  AmigaIlbmCamgNtscMonitor* = 0x00010000'u32
  AmigaIlbmCamgPalMonitor* = 0x00020000'u32
  AmigaIlbmMaskNone* = 0
  AmigaIlbmMaskPlane* = 1
  AmigaIlbmMaskTransparentColour* = 2
  AmigaIlbmMaskLasso* = 3

type
  AmigaPlanarLayout* = enum
    aplRowInterleaved
    aplPlaneContiguous

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
    planarLayout*: AmigaPlanarLayout

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
  if header.masking notin AmigaIlbmMaskNone .. AmigaIlbmMaskLasso:
    raise newException(ValueError, "unsupported ILBM masking mode")

proc decodeAmigaIlbmPlanes*(source: AmigaIlbmImageSource): seq[byte] =
  let header = source.header
  let rowBytes = ((header.width + 15) div 16) * 2
  let planeSize = rowBytes * header.height
  let storedPlanes = header.planes +
    (if header.masking == AmigaIlbmMaskPlane: 1 else: 0)
  result = newSeq[byte](planeSize * storedPlanes)
  var bodyOffset = 0
  template decodePlaneRow(plane, y: int) =
      let row = decodeRow(source.body, bodyOffset, rowBytes,
        header.compression)
      for column, value in row:
        result[plane * planeSize + y * rowBytes + column] = value
  case source.planarLayout
  of aplRowInterleaved:
    for y in 0 ..< header.height:
      for plane in 0 ..< storedPlanes:
        decodePlaneRow(plane, y)
  of aplPlaneContiguous:
    for plane in 0 ..< storedPlanes:
      for y in 0 ..< header.height:
        decodePlaneRow(plane, y)
  let hasIncludedChunkPad = header.compression == 1 and
    bodyOffset + 1 == source.body.len and source.body.len mod 2 == 0 and
    source.body[bodyOffset] == 0
  if bodyOffset != source.body.len and not hasIncludedChunkPad:
    raise newException(ValueError, "ILBM BODY has trailing image data")

proc codesFromPlanes(source: AmigaIlbmImageSource,
    planes: openArray[byte]): seq[uint8] =
  let
    header = source.header
    rowBytes = ((header.width + 15) div 16) * 2
    planeSize = rowBytes * header.height
  let storedPlanes = header.planes +
    (if header.masking == AmigaIlbmMaskPlane: 1 else: 0)
  if planes.len != planeSize * storedPlanes:
    raise newException(ValueError, "ILBM planar buffer has the wrong length")
  result = newSeq[uint8](header.width * header.height)
  for y in 0 ..< header.height:
    for plane in 0 ..< header.planes:
      for x in 0 ..< header.width:
        let value = planes[plane * planeSize + y * rowBytes + x div 8]
        if (value and (0x80'u8 shr (x mod 8))) != 0:
          result[y * header.width + x] =
            result[y * header.width + x] or uint8(1 shl plane)

proc alphaFromMasking(source: AmigaIlbmImageSource, planes: openArray[byte],
    codes: openArray[uint8]): seq[uint8] =
  let header = source.header
  case header.masking
  of AmigaIlbmMaskNone:
    discard
  of AmigaIlbmMaskPlane:
    let
      rowBytes = ((header.width + 15) div 16) * 2
      planeSize = rowBytes * header.height
      maskOffset = planeSize * header.planes
    result = newSeq[uint8](header.width * header.height)
    for y in 0 ..< header.height:
      for x in 0 ..< header.width:
        let value = planes[maskOffset + y * rowBytes + x div 8]
        result[y * header.width + x] =
          if (value and (0x80'u8 shr (x mod 8))) != 0: 255'u8 else: 0'u8
  of AmigaIlbmMaskTransparentColour:
    result = newSeq[uint8](header.width * header.height)
    for index, code in codes:
      result[index] =
        if int(code) == header.transparentColour: 0'u8 else: 255'u8
  of AmigaIlbmMaskLasso:
    # Lasso transparency is the transparent-colour region connected to the
    # bitmap boundary. Matching enclosed pixels remain opaque.
    result = newSeq[uint8](header.width * header.height)
    for index in 0 ..< result.len: result[index] = 255
    var
      queued = newSeq[bool](result.len)
      queue: seq[int]
      next = 0
    template enqueue(x, y: int) =
      block:
        let position = y * header.width + x
        if not queued[position] and
            int(codes[position]) == header.transparentColour:
          queued[position] = true
          queue.add position
    for x in 0 ..< header.width:
      enqueue(x, 0)
      if header.height > 1: enqueue(x, header.height - 1)
    for y in 1 ..< header.height - 1:
      enqueue(0, y)
      if header.width > 1: enqueue(header.width - 1, y)
    while next < queue.len:
      let
        position = queue[next]
        x = position mod header.width
        y = position div header.width
      inc next
      result[position] = 0
      if x > 0: enqueue(x - 1, y)
      if x + 1 < header.width: enqueue(x + 1, y)
      if y > 0: enqueue(x, y - 1)
      if y + 1 < header.height: enqueue(x, y + 1)
  else:
    raise newException(ValueError, "unsupported ILBM masking mode")

proc renderAmigaIlbmImage*(source: AmigaIlbmImageSource,
    planes: openArray[byte]): VextIndexedImage =
  let header = source.header
  validateDimensions(header)
  if (source.camg and AmigaIlbmCamgHam) != 0:
    raise newException(ValueError,
      "HAM and HAM8 ILBM images require a true-colour raster archetype")
  let ehb = (source.camg and AmigaIlbmCamgEhb) != 0
  if (ehb and header.planes != 6) or (not ehb and header.planes notin 1 .. 8):
    raise newException(ValueError,
      "indexed ILBM decoding supports one to eight planes or six-plane EHB")

  let codes = codesFromPlanes(source, planes)
  result = VextIndexedImage(
    width: header.width,
    height: header.height,
    palette: decodePalette(source),
    pixels: codes,
    alpha: alphaFromMasking(source, planes, codes))
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

proc decodeAmigaIlbmImage*(source: AmigaIlbmImageSource): VextIndexedImage =
  renderAmigaIlbmImage(source, decodeAmigaIlbmPlanes(source))


proc renderAmigaIlbmHam*(source: AmigaIlbmImageSource,
    planes: openArray[byte]): VextTrueColourImage =
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
    codes = codesFromPlanes(source, planes)
  var palette = decodePalette(source)
  while palette.len < (1 shl dataBits):
    palette.add VextRgb()
  result = VextTrueColourImage(
    width: header.width, height: header.height,
    pixels: newSeq[VextRgb](header.width * header.height),
    alpha: alphaFromMasking(source, planes, codes))

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

proc decodeAmigaIlbmHam*(source: AmigaIlbmImageSource): VextTrueColourImage =
  renderAmigaIlbmHam(source, decodeAmigaIlbmPlanes(source))

proc renderAmigaIlbmRaster*(source: AmigaIlbmImageSource,
    planes: openArray[byte]): VextRaster =
  if (source.camg and AmigaIlbmCamgHam) != 0:
    VextRaster(kind: vrkTrueColourImage,
      trueColourImage: renderAmigaIlbmHam(source, planes))
  else:
    VextRaster(kind: vrkIndexedImage,
      image: renderAmigaIlbmImage(source, planes))

proc decodeAmigaIlbmRaster*(source: AmigaIlbmImageSource): VextRaster =
  renderAmigaIlbmRaster(source, decodeAmigaIlbmPlanes(source))
