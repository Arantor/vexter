## Minimal dependency-free indexed, RGB, and RGBA PNG/APNG exporter.

import ../archetypes/raster
import ../artifacts

const PngSignature = [137'u8, 80, 78, 71, 13, 10, 26, 10]

proc appendU32(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for _ in 0 ..< 8:
      let mask = 0'u32 - (result and 1'u32)
      result = (result shr 1) xor (0xedb88320'u32 and mask)
  result = result xor 0xffffffff'u32

proc addChunk(output: var seq[byte], kind: string, payload: openArray[byte]) =
  output.appendU32(uint32(payload.len))
  var checked = newSeqOfCap[byte](4 + payload.len)
  for character in kind:
    checked.add byte(character)
    output.add byte(character)
  for value in payload:
    checked.add value
    output.add value
  output.appendU32(crc32(checked))

proc adler32(data: openArray[byte]): uint32 =
  var a = 1'u32
  var b = 0'u32
  for value in data:
    a = (a + uint32(value)) mod 65521'u32
    b = (b + a) mod 65521'u32
  (b shl 16) or a

proc storedZlib(data: openArray[byte]): seq[byte] =
  # CMF/FLG for DEFLATE with a 32 KiB window and no compression preference.
  result = @[0x78'u8, 0x01'u8]
  var offset = 0
  while offset < data.len:
    let
      count = min(65535, data.len - offset)
      final = offset + count == data.len
      length = uint16(count)
      inverse = not length
    result.add(if final: 1'u8 else: 0'u8)
    result.add byte(length)
    result.add byte(length shr 8)
    result.add byte(inverse)
    result.add byte(inverse shr 8)
    for index in offset ..< offset + count:
      result.add data[index]
    offset += count
  result.appendU32(adler32(data))

proc exportPng*(image: VextIndexedImage,
    suggestedFilename = "image.png"): VextArtifactSet =
  if image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "PNG image dimensions must be positive")
  if image.palette.len == 0 or image.palette.len > 256:
    raise newException(ValueError, "PNG palette must contain 1 to 256 colours")
  if image.pixels.len != image.width * image.height:
    raise newException(ValueError, "PNG pixel buffer has the wrong length")
  let alpha = image.hasAlpha

  var encoded = @PngSignature
  var header: seq[byte]
  header.appendU32(uint32(image.width))
  header.appendU32(uint32(image.height))
  header.add 8 # bit depth
  header.add(if alpha: 6 else: 3) # RGBA when per-pixel alpha is required
  header.add 0 # compression
  header.add 0 # filter
  header.add 0 # no interlace
  encoded.addChunk("IHDR", header)

  if not alpha:
    var palette = newSeqOfCap[byte](image.palette.len * 3)
    for colour in image.palette:
      palette.add colour.r
      palette.add colour.g
      palette.add colour.b
    encoded.addChunk("PLTE", palette)

  var scanlines = newSeqOfCap[byte]((image.width + 1) * image.height)
  for y in 0 ..< image.height:
    scanlines.add 0 # filter type: None
    for x in 0 ..< image.width:
      let paletteIndex = image.pixels[y * image.width + x]
      if int(paletteIndex) >= image.palette.len:
        raise newException(ValueError, "PNG pixel references a missing colour")
      if alpha:
        let colour = image.palette[int(paletteIndex)]
        scanlines.add colour.r
        scanlines.add colour.g
        scanlines.add colour.b
        scanlines.add image.alpha[y * image.width + x]
      else:
        scanlines.add paletteIndex
  encoded.addChunk("IDAT", storedZlib(scanlines))
  encoded.addChunk("IEND", [])

  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "image/png",
    data: encoded)

proc exportPng*(image: VextTrueColourImage,
    suggestedFilename = "image.png"): VextArtifactSet =
  if image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "PNG image dimensions must be positive")
  if image.pixels.len != image.width * image.height:
    raise newException(ValueError, "PNG pixel buffer has the wrong length")
  let alpha = image.hasAlpha

  var encoded = @PngSignature
  var header: seq[byte]
  header.appendU32(uint32(image.width))
  header.appendU32(uint32(image.height))
  header.add 8 # bit depth
  header.add(if alpha: 6 else: 2) # true-colour RGB or RGBA
  header.add 0 # compression
  header.add 0 # filter
  header.add 0 # no interlace
  encoded.addChunk("IHDR", header)

  var scanlines = newSeqOfCap[byte]((image.width * 3 + 1) * image.height)
  for y in 0 ..< image.height:
    scanlines.add 0
    for x in 0 ..< image.width:
      let colour = image.pixels[y * image.width + x]
      scanlines.add colour.r
      scanlines.add colour.g
      scanlines.add colour.b
      if alpha: scanlines.add image.alpha[y * image.width + x]
  encoded.addChunk("IDAT", storedZlib(scanlines))
  encoded.addChunk("IEND", [])

  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "image/png",
    data: encoded)

proc trueColourScanlines(image: VextTrueColourImage, alpha: bool): seq[byte] =
  if image.width <= 0 or image.height <= 0 or
      image.pixels.len != image.width * image.height:
    raise newException(ValueError, "APNG frame has invalid dimensions or pixels")
  result = newSeqOfCap[byte]((image.width * 3 + 1) * image.height)
  for y in 0 ..< image.height:
    result.add 0
    for x in 0 ..< image.width:
      let colour = image.pixels[y * image.width + x]
      result.add colour.r
      result.add colour.g
      result.add colour.b
      if alpha: result.add image.alphaAt(x, y)

proc exportApng*(animation: VextTrueColourAnimation,
    suggestedFilename = "animation.png"): VextArtifactSet =
  if animation.width <= 0 or animation.height <= 0 or
      animation.frames.len == 0:
    raise newException(ValueError, "APNG animation must contain frames")
  var encoded = @PngSignature
  var alpha = false
  for frame in animation.frames:
    if frame.image.hasAlpha: alpha = true
  var header: seq[byte]
  header.appendU32(uint32(animation.width))
  header.appendU32(uint32(animation.height))
  header.add 8
  header.add(if alpha: 6 else: 2) # RGB or RGBA
  header.add 0
  header.add 0
  header.add 0
  encoded.addChunk("IHDR", header)

  var animationControl: seq[byte]
  animationControl.appendU32(uint32(animation.frames.len))
  animationControl.appendU32(0) # loop forever
  encoded.addChunk("acTL", animationControl)

  var sequence = 0'u32
  for index, frame in animation.frames:
    if frame.image.width != animation.width or
        frame.image.height != animation.height:
      raise newException(ValueError, "APNG frame dimensions do not match")
    var frameControl: seq[byte]
    frameControl.appendU32(sequence)
    inc sequence
    frameControl.appendU32(uint32(animation.width))
    frameControl.appendU32(uint32(animation.height))
    frameControl.appendU32(0) # x offset
    frameControl.appendU32(0) # y offset
    let delay = min(65535, max(1, frame.durationMs))
    frameControl.add byte((delay shr 8) and 0xff)
    frameControl.add byte(delay and 0xff)
    frameControl.add 0x03 # denominator 1000
    frameControl.add 0xe8
    frameControl.add 0 # dispose none
    frameControl.add 0 # source blend
    encoded.addChunk("fcTL", frameControl)
    let compressed = storedZlib(trueColourScanlines(frame.image, alpha))
    if index == 0:
      encoded.addChunk("IDAT", compressed)
    else:
      var frameData: seq[byte]
      frameData.appendU32(sequence)
      inc sequence
      frameData.add compressed
      encoded.addChunk("fdAT", frameData)
  encoded.addChunk("IEND", [])
  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "image/apng",
    data: encoded)

proc toTrueColour(image: VextIndexedImage): VextTrueColourImage =
  if image.width <= 0 or image.height <= 0 or
      image.pixels.len != image.width * image.height:
    raise newException(ValueError, "indexed APNG frame has invalid dimensions or pixels")
  discard image.hasAlpha # validates a present alpha buffer
  result = VextTrueColourImage(width: image.width, height: image.height,
    pixels: newSeq[VextRgb](image.pixels.len), alpha: image.alpha)
  for index, paletteIndex in image.pixels:
    if int(paletteIndex) >= image.palette.len:
      raise newException(ValueError, "APNG pixel references a missing colour")
    result.pixels[index] = image.palette[int(paletteIndex)]

proc exportApng*(animation: VextIndexedAnimation,
    suggestedFilename = "animation.png"): VextArtifactSet =
  ## APNG has no global-palette restriction, so each indexed frame may use a
  ## different palette. Expanding through the generic true-colour pathway also
  ## preserves per-pixel alpha.
  var converted = VextTrueColourAnimation(width: animation.width,
    height: animation.height)
  for frame in animation.frames:
    converted.frames.add VextTrueColourAnimationFrame(
      image: toTrueColour(frame.image), durationMs: frame.durationMs)
  exportApng(converted, suggestedFilename)
