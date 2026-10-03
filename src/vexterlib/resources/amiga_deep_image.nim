## True-colour raster decoding for IFF FORM DEEP images.

import ../archetypes/raster
import ../containers/amiga_deep

const
  AmigaDeepImageTypeId* = "amiga.deep-image"
  AmigaDeepImageResourcePath* = "/image"
  MaximumAmigaDeepOutputPixels* = 100_000_000

proc componentIndex(components: openArray[AmigaDeepComponent],
    componentType: int): int =
  result = -1
  for index, component in components:
    if component.componentType == componentType:
      if result >= 0:
        raise newException(ValueError, "duplicate IFF DEEP colour component")
      result = index

proc componentBitOffset(components: openArray[AmigaDeepComponent],
    target: int): int =
  for index in 0 ..< target:
    result += components[index].bitDepth

proc readComponent(data: openArray[byte], pixelOffset, bitOffset,
    bitDepth: int): uint64 =
  if bitDepth > 32:
    raise newException(ValueError,
      "displayed IFF DEEP components may not exceed 32 bits")
  for bit in 0 ..< bitDepth:
    let absoluteBit = pixelOffset * 8 + bitOffset + bit
    result = (result shl 1) or
      uint64((data[absoluteBit shr 3] shr (7 - (absoluteBit and 7))) and 1)

proc scaleComponent(value: uint64, depth: int): uint8 =
  let maximum = (1'u64 shl depth) - 1
  uint8((value * 255'u64 + maximum div 2) div maximum)

proc decodeBody(body: AmigaDeepBody, compression, pixelBytes: int): seq[byte] =
  if body.location.width > high(int) div body.location.height or
      body.location.width * body.location.height > high(int) div pixelBytes:
    raise newException(ValueError, "IFF DEEP body dimensions overflow")
  let
    rowBytes = body.location.width * pixelBytes
    imageBytes = rowBytes * body.location.height
  if compression == AmigaDeepCompressionNone:
    let paddedBytes = (imageBytes + 3) and not 3
    if body.data.len != paddedBytes:
      raise newException(ValueError,
        "uncompressed IFF DEEP DBOD length does not match its dimensions")
    result = body.data[0 ..< imageBytes]
    return
  if compression != AmigaDeepCompressionRunLength:
    raise newException(ValueError,
      "unsupported IFF DEEP compression method " & $compression)

  result = newSeqOfCap[byte](imageBytes)
  var offset = 0
  for unusedY in 0 ..< body.location.height:
    let rowEnd = result.len + rowBytes
    while result.len < rowEnd:
      if offset >= body.data.len:
        raise newException(ValueError, "truncated run-length IFF DEEP DBOD row")
      let control = int(cast[int8](body.data[offset]))
      inc offset
      if control >= 0:
        let
          pixelCount = control + 1
          byteCount = pixelCount * pixelBytes
        if byteCount > rowEnd - result.len or
            byteCount > body.data.len - offset:
          raise newException(ValueError,
            "invalid IFF DEEP run-length literal packet")
        result.add body.data.toOpenArray(offset, offset + byteCount - 1)
        offset += byteCount
      elif control >= -127:
        let pixelCount = 1 - control
        if pixelCount > (rowEnd - result.len) div pixelBytes or
            pixelBytes > body.data.len - offset:
          raise newException(ValueError,
            "invalid IFF DEEP run-length repeat packet")
        for unused in 0 ..< pixelCount:
          result.add body.data.toOpenArray(offset, offset + pixelBytes - 1)
        offset += pixelBytes
      else:
        discard
  if body.data.len != ((offset + 3) and not 3):
    raise newException(ValueError,
      "run-length IFF DEEP DBOD has trailing compressed data")

proc decodeFrame(source: AmigaDeep, frame: AmigaDeepFrame,
    redIndex, greenIndex, blueIndex, opacityIndex, pixelBytes: int):
    VextTrueColourImage =
  let pixelCount = source.global.displayWidth * source.global.displayHeight
  result = VextTrueColourImage(width: source.global.displayWidth,
    height: source.global.displayHeight, pixels: newSeq[VextRgb](pixelCount))
  if opacityIndex >= 0:
    result.alpha = newSeq[uint8](pixelCount)

  let
    redOffset = componentBitOffset(source.components, redIndex)
    greenOffset = componentBitOffset(source.components, greenIndex)
    blueOffset = componentBitOffset(source.components, blueIndex)
    opacityOffset = if opacityIndex >= 0:
      componentBitOffset(source.components, opacityIndex) else: 0
  for body in frame.bodies:
    let
      decoded = decodeBody(body, source.global.compression, pixelBytes)
    for bodyY in 0 ..< body.location.height:
      for bodyX in 0 ..< body.location.width:
        let
          sourceIndex = bodyY * body.location.width + bodyX
          sourceOffset = sourceIndex * pixelBytes
          targetIndex = (body.location.y + bodyY) * result.width +
            body.location.x + bodyX
        result.pixels[targetIndex] = VextRgb(
          r: scaleComponent(readComponent(decoded, sourceOffset, redOffset,
            source.components[redIndex].bitDepth),
            source.components[redIndex].bitDepth),
          g: scaleComponent(readComponent(decoded, sourceOffset, greenOffset,
            source.components[greenIndex].bitDepth),
            source.components[greenIndex].bitDepth),
          b: scaleComponent(readComponent(decoded, sourceOffset, blueOffset,
            source.components[blueIndex].bitDepth),
            source.components[blueIndex].bitDepth))
        if opacityIndex >= 0:
          result.alpha[targetIndex] = scaleComponent(readComponent(decoded,
            sourceOffset, opacityOffset,
            source.components[opacityIndex].bitDepth),
            source.components[opacityIndex].bitDepth)

proc decodeAmigaDeep*(source: AmigaDeep): VextRaster =
  if source.global.compression notin [AmigaDeepCompressionNone,
      AmigaDeepCompressionRunLength]:
    raise newException(ValueError,
      "unsupported IFF DEEP compression method " & $source.global.compression)
  let
    redIndex = componentIndex(source.components, AmigaDeepComponentRed)
    greenIndex = componentIndex(source.components, AmigaDeepComponentGreen)
    blueIndex = componentIndex(source.components, AmigaDeepComponentBlue)
    opacityIndex = componentIndex(source.components, AmigaDeepComponentOpacity)
  if redIndex < 0 or greenIndex < 0 or blueIndex < 0:
    raise newException(ValueError, "IFF DEEP raster requires RGB components")
  for index in [redIndex, greenIndex, blueIndex, opacityIndex]:
    if index >= 0 and source.components[index].bitDepth > 32:
      raise newException(ValueError,
        "displayed IFF DEEP components may not exceed 32 bits")
  if source.frames.len == 0 or
      source.global.displayWidth > MaximumAmigaDeepOutputPixels div
        source.global.displayHeight or
      source.global.displayWidth * source.global.displayHeight >
        MaximumAmigaDeepOutputPixels div source.frames.len:
    raise newException(ValueError, "IFF DEEP decoded frame set is too large")
  var pixelBits = 0
  for component in source.components: pixelBits += component.bitDepth
  let pixelBytes = (pixelBits + 7) div 8

  if source.frames.len == 1 and source.frames[0].durationMs == 0:
    return VextRaster(kind: vrkTrueColourImage,
      trueColourImage: decodeFrame(source, source.frames[0], redIndex,
        greenIndex, blueIndex, opacityIndex, pixelBytes))
  var animation = VextTrueColourAnimation(width: source.global.displayWidth,
    height: source.global.displayHeight)
  for frame in source.frames:
    animation.frames.add VextTrueColourAnimationFrame(
      image: decodeFrame(source, frame, redIndex, greenIndex, blueIndex,
        opacityIndex, pixelBytes), durationMs: frame.durationMs)
  VextRaster(kind: vrkTrueColourAnimation, trueColourAnimation: animation)
