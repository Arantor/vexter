## Minimal dependency-free indexed animated GIF exporter.

import ../archetypes/raster
import ../artifacts

proc appendU16(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)

proc addString(data: var seq[byte], value: string) =
  for character in value:
    data.add byte(character)

proc tableSizeFor(colourCount: int): int =
  result = 2
  while result < colourCount:
    result *= 2
  if result > 256:
    raise newException(ValueError, "GIF palette has more than 256 colours")

proc colourTableSizeCode(tableSize: int): byte =
  var size = tableSize
  while size > 2:
    inc result
    size = size shr 1

proc literalLzw(pixels: openArray[byte], minimumCodeSize: int): seq[byte] =
  ## Uses frequent clear codes to keep the code width fixed. This is larger
  ## than dictionary compression but deliberately simple and fully valid.
  let
    clearCode = 1 shl minimumCodeSize
    endCode = clearCode + 1
    codeWidth = minimumCodeSize + 1
  var bitBuffer = 0'u32
  var bitCount = 0
  var output: seq[byte]

  proc emit(code: int) =
    bitBuffer = bitBuffer or (uint32(code) shl bitCount)
    bitCount += codeWidth
    while bitCount >= 8:
      output.add byte(bitBuffer and 0xff)
      bitBuffer = bitBuffer shr 8
      bitCount -= 8

  emit(clearCode)
  for pixel in pixels:
    emit(int(pixel))
    emit(clearCode)
  emit(endCode)
  if bitCount > 0:
    output.add byte(bitBuffer and 0xff)
  result = output

proc addSubBlocks(output: var seq[byte], data: openArray[byte]) =
  var offset = 0
  while offset < data.len:
    let count = min(255, data.len - offset)
    output.add byte(count)
    for index in offset ..< offset + count:
      output.add data[index]
    offset += count
  output.add 0

proc exportGif*(animation: VextIndexedAnimation,
    suggestedFilename = "animation.gif"): VextArtifactSet =
  if animation.frames.len == 0:
    raise newException(ValueError, "GIF animation must have at least one frame")
  let first = animation.frames[0].image
  if animation.width <= 0 or animation.height <= 0 or
      first.width != animation.width or first.height != animation.height:
    raise newException(ValueError, "GIF frame dimensions do not match animation")
  let tableSize = tableSizeFor(first.palette.len)
  let minimumCodeSize = max(2, int(colourTableSizeCode(tableSize)) + 1)

  var encoded: seq[byte]
  encoded.addString("GIF89a")
  encoded.appendU16(animation.width)
  encoded.appendU16(animation.height)
  encoded.add 0x80'u8 or (7'u8 shl 4) or colourTableSizeCode(tableSize)
  encoded.add 0 # background palette index
  encoded.add 0 # pixel aspect ratio
  for index in 0 ..< tableSize:
    let colour = if index < first.palette.len: first.palette[index]
                 else: VextRgb(r: 0, g: 0, b: 0)
    encoded.add colour.r
    encoded.add colour.g
    encoded.add colour.b

  if animation.frames.len > 1:
    # NETSCAPE2.0 loop extension: repeat forever.
    encoded.add 0x21
    encoded.add 0xff
    encoded.add 11
    encoded.addString("NETSCAPE2.0")
    encoded.add 3
    encoded.add 1
    encoded.appendU16(0)
    encoded.add 0

  for frame in animation.frames:
    let image = frame.image
    if image.hasAlpha:
      raise newException(ValueError,
        "GIF export of alpha images is not implemented")
    if image.width != animation.width or image.height != animation.height:
      raise newException(ValueError, "GIF frame dimensions do not match animation")
    if image.palette != first.palette:
      raise newException(ValueError, "GIF frames must share one palette")
    if image.pixels.len != image.width * image.height:
      raise newException(ValueError, "GIF pixel buffer has the wrong length")
    for pixel in image.pixels:
      if int(pixel) >= first.palette.len:
        raise newException(ValueError, "GIF pixel references a missing colour")

    encoded.add 0x21 # graphic control extension
    encoded.add 0xf9
    encoded.add 4
    encoded.add 0 # no transparency, no disposal required for full frames
    encoded.appendU16(max(1, (frame.durationMs + 5) div 10))
    encoded.add 0
    encoded.add 0

    encoded.add 0x2c # image descriptor
    encoded.appendU16(0)
    encoded.appendU16(0)
    encoded.appendU16(image.width)
    encoded.appendU16(image.height)
    encoded.add 0 # use global table, non-interlaced
    encoded.add byte(minimumCodeSize)
    encoded.addSubBlocks(literalLzw(image.pixels, minimumCodeSize))

  encoded.add 0x3b # trailer
  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "image/gif",
    data: encoded)
