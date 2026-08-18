## LZW decoding and full-canvas composition for GIF images and animations.

import ../archetypes/raster
import ../containers/gif_container

const
  GifImageTypeId* = "gif.image"
  GifImageResourcePath* = "/image"

proc decodeLzw(frame: GifFrameSource): seq[byte] =
  let clearCode = 1 shl frame.lzwMinimumCodeSize
  let endCode = clearCode + 1
  var dictionary: seq[seq[byte]]
  var codeSize: int
  proc reset() =
    dictionary.setLen(0)
    for value in 0 ..< clearCode: dictionary.add @[byte(value)]
    dictionary.add @[] # clear
    dictionary.add @[] # end
    codeSize = frame.lzwMinimumCodeSize + 1
  reset()
  var bitOffset = 0
  var previous: seq[byte]
  var ended = false
  while bitOffset + codeSize <= frame.compressedData.len * 8:
    var code = 0
    for bit in 0 ..< codeSize:
      let position = bitOffset + bit
      if (frame.compressedData[position div 8] and
          (1'u8 shl (position mod 8))) != 0:
        code = code or (1 shl bit)
    bitOffset += codeSize
    if code == clearCode:
      reset(); previous.setLen(0); continue
    if code == endCode:
      ended = true; break
    var entry: seq[byte]
    if code < dictionary.len and dictionary[code].len > 0:
      entry = dictionary[code]
    elif code == dictionary.len and previous.len > 0:
      entry.add previous
      entry.add previous[0]
    else:
      raise newException(ValueError, "invalid GIF LZW dictionary code")
    result.add entry
    if previous.len > 0 and dictionary.len < 4096:
      var added: seq[byte]
      added.add previous
      added.add entry[0]
      dictionary.add added
      if dictionary.len == (1 shl codeSize) and codeSize < 12: inc codeSize
    previous = entry
  if not ended or result.len != frame.width * frame.height:
    raise newException(ValueError, "GIF LZW data has the wrong decoded length")

proc deinterlace(frame: GifFrameSource, pixels: seq[byte]): seq[byte] =
  if not frame.interlaced: return pixels
  result = newSeq[byte](pixels.len)
  var sourceRow = 0
  for pass in [(0, 8), (4, 8), (2, 4), (1, 2)]:
    var y = pass[0]
    while y < frame.height:
      for x in 0 ..< frame.width:
        result[y * frame.width + x] = pixels[sourceRow * frame.width + x]
      inc sourceRow
      y += pass[1]

proc indexedCanvas(colours: seq[VextRgb], alpha: seq[uint8], width,
    height: int): VextIndexedImage =
  result = VextIndexedImage(width: width, height: height,
    pixels: newSeq[uint8](width * height))
  var outputAlpha = newSeq[uint8](width * height)
  var anyAlpha = false
  for index, colour in colours:
    var paletteIndex = -1
    for candidate, existing in result.palette:
      if existing == colour:
        paletteIndex = candidate; break
    if paletteIndex < 0:
      if result.palette.len >= 256:
        raise newException(ValueError,
          "composited GIF frame contains more than 256 colours")
      paletteIndex = result.palette.len
      result.palette.add colour
    result.pixels[index] = uint8(paletteIndex)
    outputAlpha[index] = alpha[index]
    if alpha[index] != 255: anyAlpha = true
  if anyAlpha: result.alpha = outputAlpha

proc decodeGif*(source: GifImageSource): VextRaster =
  var canvas = newSeq[VextRgb](source.width * source.height)
  var canvasAlpha = newSeq[uint8](source.width * source.height)
  var background = VextRgb()
  var backgroundAlpha = 0'u8
  if source.globalPalette.len > source.backgroundIndex * 3 + 2:
    let offset = source.backgroundIndex * 3
    background = VextRgb(r: source.globalPalette[offset],
      g: source.globalPalette[offset + 1], b: source.globalPalette[offset + 2])
    backgroundAlpha = 255
    for index in 0 ..< canvas.len:
      canvas[index] = background
      canvasAlpha[index] = 255
  var animation = VextIndexedAnimation(width: source.width, height: source.height)
  for frame in source.frames:
    let pixels = deinterlace(frame, decodeLzw(frame))
    var previousCanvas: seq[VextRgb]
    var previousAlpha: seq[uint8]
    if frame.disposal == 3:
      previousCanvas.add canvas; previousAlpha.add canvasAlpha
    for localY in 0 ..< frame.height:
      for localX in 0 ..< frame.width:
        let input = localY * frame.width + localX
        let paletteIndex = int(pixels[input])
        if paletteIndex >= frame.palette.len div 3:
          raise newException(ValueError, "GIF pixel references a missing colour")
        if paletteIndex == frame.transparentIndex: continue
        let paletteOffset = paletteIndex * 3
        let output = (frame.y + localY) * source.width + frame.x + localX
        canvas[output] = VextRgb(r: frame.palette[paletteOffset],
          g: frame.palette[paletteOffset + 1], b: frame.palette[paletteOffset + 2])
        canvasAlpha[output] = 255
    var outputCanvas: seq[VextRgb]
    var outputAlpha: seq[uint8]
    outputCanvas.add canvas; outputAlpha.add canvasAlpha
    animation.frames.add VextIndexedAnimationFrame(
      image: indexedCanvas(outputCanvas, outputAlpha, source.width, source.height),
      durationMs: frame.delayMs)
    case frame.disposal
    of 2:
      for localY in 0 ..< frame.height:
        for localX in 0 ..< frame.width:
          let output = (frame.y + localY) * source.width + frame.x + localX
          canvas[output] = background
          canvasAlpha[output] = backgroundAlpha
    of 3:
      canvas = previousCanvas; canvasAlpha = previousAlpha
    else: discard
  VextRaster(kind: vrkIndexedAnimation, animation: animation)
