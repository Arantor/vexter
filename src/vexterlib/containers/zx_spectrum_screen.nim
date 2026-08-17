## Decoder for a raw 6,912-byte ZX Spectrum screen memory dump.

import ../archetypes/raster

const
  ZxSpectrumScreenTypeId* = "zx-spectrum.screen"
  ZxSpectrumScreenResourcePath* = "/screen"
  ZxSpectrumScreenSize* = 6912
  ZxSpectrumScreenWidth* = 256
  ZxSpectrumScreenHeight* = 192
  ZxSpectrumFlashFrameDurationMs* = 320

  ZxSpectrumPalette* = [
    VextRgb(r: 0,   g: 0,   b: 0),
    VextRgb(r: 0,   g: 0,   b: 205),
    VextRgb(r: 205, g: 0,   b: 0),
    VextRgb(r: 205, g: 0,   b: 205),
    VextRgb(r: 0,   g: 205, b: 0),
    VextRgb(r: 0,   g: 205, b: 205),
    VextRgb(r: 205, g: 205, b: 0),
    VextRgb(r: 205, g: 205, b: 205),
    VextRgb(r: 0,   g: 0,   b: 0),
    VextRgb(r: 0,   g: 0,   b: 255),
    VextRgb(r: 255, g: 0,   b: 0),
    VextRgb(r: 255, g: 0,   b: 255),
    VextRgb(r: 0,   g: 255, b: 0),
    VextRgb(r: 0,   g: 255, b: 255),
    VextRgb(r: 255, g: 255, b: 0),
    VextRgb(r: 255, g: 255, b: 255)
  ]

proc bitmapOffset(xByte, y: int): int {.inline.} =
  ((y and 0xc0) shl 5) or
    ((y and 0x07) shl 8) or
    ((y and 0x38) shl 2) or
    xByte

proc attributeOffset(xByte, y: int): int {.inline.} =
  6144 + (y shr 3) * 32 + xByte

proc decodeFrame(data: openArray[byte], flashPhase: bool): VextIndexedImage =
  result = VextIndexedImage(
    width: ZxSpectrumScreenWidth,
    height: ZxSpectrumScreenHeight,
    palette: @ZxSpectrumPalette,
    pixels: newSeq[uint8](ZxSpectrumScreenWidth * ZxSpectrumScreenHeight)
  )

  for y in 0 ..< ZxSpectrumScreenHeight:
    for xByte in 0 ..< 32:
      let
        bitmap = data[bitmapOffset(xByte, y)]
        attributes = data[attributeOffset(xByte, y)]
        bright = if (attributes and 0x40) != 0: 8'u8 else: 0'u8
        originalInk = (attributes and 0x07) + bright
        originalPaper = ((attributes shr 3) and 0x07) + bright
        flashes = (attributes and 0x80) != 0
        ink = if flashPhase and flashes: originalPaper else: originalInk
        paper = if flashPhase and flashes: originalInk else: originalPaper

      for bit in 0 ..< 8:
        let x = xByte * 8 + bit
        result.pixels[y * ZxSpectrumScreenWidth + x] =
          if (bitmap and (0x80'u8 shr bit)) != 0: ink else: paper

proc hasFlashAttributes*(data: openArray[byte]): bool =
  ## Reports syntactic FLASH presence in the 768-byte attribute area.
  if data.len != ZxSpectrumScreenSize:
    raise newException(ValueError,
      "ZX Spectrum screen must contain exactly 6912 bytes")
  for offset in 6144 ..< ZxSpectrumScreenSize:
    if (data[offset] and 0x80) != 0:
      return true

proc decodeZxSpectrumScreen*(data: openArray[byte]): VextRaster =
  ## Decodes a raw screen into an indexed image, or an indexed animation when
  ## any attribute has its FLASH bit set.
  if data.len != ZxSpectrumScreenSize:
    raise newException(ValueError,
      "ZX Spectrum screen must contain exactly 6912 bytes")

  let natural = decodeFrame(data, false)
  if not data.hasFlashAttributes:
    return VextRaster(kind: vrkIndexedImage, image: natural)

  result = VextRaster(
    kind: vrkIndexedAnimation,
    animation: VextIndexedAnimation(
      width: ZxSpectrumScreenWidth,
      height: ZxSpectrumScreenHeight,
      frames: @[
        VextIndexedAnimationFrame(
          image: natural,
          durationMs: ZxSpectrumFlashFrameDurationMs),
        VextIndexedAnimationFrame(
          image: decodeFrame(data, true),
          durationMs: ZxSpectrumFlashFrameDurationMs)
      ]
    )
  )
