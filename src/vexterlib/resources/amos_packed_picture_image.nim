## Raster rendering for decompressed AMOS Pac.Pic. images.

import ../archetypes/raster
import ../containers/amos_packed_picture

const
  AmosPackedPictureResourceTypeId* = "amos.packed-picture"
  AmosPackedPictureResourcePath* = "/picture"

proc expandNibble(value: uint16): uint8 {.inline.} =
  let nibble = uint8(value and 0xf)
  (nibble shl 4) or nibble

proc decodeAmosPackedPicture*(source: AmosPackedPicture): VextIndexedImage =
  if not source.hasScreenHeader:
    raise newException(ValueError,
      "AMOS packed picture has no screen palette")
  if source.planes > 5:
    raise newException(ValueError,
      "six-plane AMOS packed pictures are not yet supported")
  let requiredColours = 1 shl source.planes
  if source.colourCount < requiredColours or source.colourCount > 32 or
      source.paletteWords.len < requiredColours:
    raise newException(ValueError, "AMOS packed-picture palette is too small")

  result.width = source.widthBytes * 8
  result.height = source.lumps * source.lumpHeight
  result.pixels = newSeq[uint8](result.width * result.height)
  for index in 0 ..< source.colourCount:
    if index >= source.paletteWords.len: break
    let colour = source.paletteWords[index]
    result.palette.add VextRgb(
      r: expandNibble(colour shr 8),
      g: expandNibble(colour shr 4),
      b: expandNibble(colour))

  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      var colour = 0'u8
      for plane in 0 ..< source.planes:
        let value = source.planeData[(plane * result.height + y) *
          source.widthBytes + x div 8]
        if (value and (0x80'u8 shr (x mod 8))) != 0:
          colour = colour or uint8(1 shl plane)
      result.pixels[y * result.width + x] = colour
