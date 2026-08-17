## Minimal dependency-free indexed PNG exporter.

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

  var encoded = @PngSignature
  var header: seq[byte]
  header.appendU32(uint32(image.width))
  header.appendU32(uint32(image.height))
  header.add 8 # bit depth
  header.add 3 # indexed colour
  header.add 0 # compression
  header.add 0 # filter
  header.add 0 # no interlace
  encoded.addChunk("IHDR", header)

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
      scanlines.add paletteIndex
  encoded.addChunk("IDAT", storedZlib(scanlines))
  encoded.addChunk("IEND", [])

  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "image/png",
    data: encoded)
