## ILBM-specific structure parsed from a generic IFF FORM.

import std/[os, strutils]
import ./amiga_iff
import ../archetypes/raster
import ../resources/amiga_ilbm_image

const
  AmigaIlbmTypeId* = "amiga.ilbm"
  AmigaIlbmFormType* = "ILBM"

type AmigaIlbm* = object
  image*: AmigaIlbmImageSource

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc signedWord(data: openArray[byte], offset: int): int {.inline.} =
  int(cast[int16](uint16(beWord(data, offset))))

proc beLong(data: openArray[byte]): uint32 {.inline.} =
  (uint32(data[0]) shl 24) or (uint32(data[1]) shl 16) or
    (uint32(data[2]) shl 8) or uint32(data[3])

proc signedLong(data: openArray[byte], offset: int): int64 {.inline.} =
  int64(cast[int32]((uint32(data[offset]) shl 24) or
    (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])))

proc parseColourCycle(chunk: AmigaIffChunk): VextColourCycleRange =
  case chunk.id
  of "CRNG":
    if chunk.data.len != 8:
      raise newException(ValueError, "ILBM CRNG chunk must contain 8 bytes")
    let
      rate = beWord(chunk.data, 2)
      flags = beWord(chunk.data, 4)
    if rate == 0 or (flags and 1) == 0:
      return
    result = VextColourCycleRange(
      low: int(chunk.data[6]), high: int(chunk.data[7]),
      direction: (if (flags and 2) != 0: -1 else: 1),
      stepDurationMs: max(1, (16_384_000 + rate * 30) div (rate * 60)))
  of "CCRT":
    if chunk.data.len != 14:
      raise newException(ValueError, "ILBM CCRT chunk must contain 14 bytes")
    let direction = signedWord(chunk.data, 0)
    if direction notin [-1, 1]:
      return
    let
      seconds = signedLong(chunk.data, 4)
      micros = signedLong(chunk.data, 8)
    if seconds < 0 or micros < 0 or micros >= 1_000_000:
      return
    if seconds == 0 and micros == 0:
      return
    result = VextColourCycleRange(
      low: int(chunk.data[2]), high: int(chunk.data[3]),
      direction: (if direction < 0: -1 else: 1),
      stepDurationMs: max(1, int(seconds * 1000 + (micros + 500) div 1000)))
  else:
    discard

proc parseAmigaBitmapHeader*(data: openArray[byte]): AmigaIlbmHeader =
  if data.len != 20:
    raise newException(ValueError, "ILBM BMHD chunk must contain 20 bytes")
  AmigaIlbmHeader(
    width: beWord(data, 0), height: beWord(data, 2),
    x: signedWord(data, 4), y: signedWord(data, 6),
    planes: int(data[8]), masking: int(data[9]),
    compression: int(data[10]), transparentColour: beWord(data, 12),
    xAspect: int(data[14]), yAspect: int(data[15]),
    pageWidth: signedWord(data, 16), pageHeight: signedWord(data, 18))

proc parseAmigaBitmapForm*(form: AmigaIffForm, expectedFormType,
    bitmapChunk: string, planarLayout: AmigaPlanarLayout): AmigaIlbm =
  if form.formType != expectedFormType:
    raise newException(ValueError,
      "IFF FORM type is not " & expectedFormType)
  var haveHeader, havePalette, haveBody: bool
  for chunk in form.chunks:
    case chunk.id
    of "BMHD":
      if haveHeader or haveBody:
        raise newException(ValueError,
          expectedFormType & " BMHD must precede " & bitmapChunk)
      result.image.header = parseAmigaBitmapHeader(chunk.data)
      haveHeader = true
    of "CMAP":
      if havePalette or haveBody:
        raise newException(ValueError,
          expectedFormType & " CMAP must precede " & bitmapChunk)
      if chunk.data.len mod 3 != 0:
        raise newException(ValueError,
          expectedFormType & " CMAP length must be divisible by three")
      result.image.colourMap = chunk.data
      havePalette = true
    of "CAMG":
      if haveBody:
        raise newException(ValueError,
          expectedFormType & " CAMG must precede " & bitmapChunk)
      if chunk.data.len != 4:
        raise newException(ValueError,
          expectedFormType & " CAMG chunk must contain four bytes")
      result.image.camg = beLong(chunk.data)
    of "CRNG", "CCRT":
      let cycle = parseColourCycle(chunk)
      if cycle.stepDurationMs > 0:
        result.image.colourCycles.add cycle
    else:
      if chunk.id != bitmapChunk:
        continue
      if not haveHeader:
        raise newException(ValueError,
          expectedFormType & " " & bitmapChunk & " must follow BMHD")
      if haveBody:
        raise newException(ValueError,
          expectedFormType & " may contain only one " & bitmapChunk & " chunk")
      result.image.body = chunk.data
      result.image.hasBitmap = true
      haveBody = true
  if not haveBody and (not havePalette or result.image.colourMap.len == 0):
    raise newException(ValueError,
      expectedFormType & " requires " & bitmapChunk & " or CMAP")
  if not haveBody:
    result.image.planarLayout = planarLayout
    return
  if not haveHeader:
    raise newException(ValueError,
      expectedFormType & " " & bitmapChunk & " requires BMHD")
  if result.image.header.planes < 1:
    raise newException(ValueError,
      expectedFormType & " must contain at least one bitplane")
  if result.image.header.masking notin
      AmigaIlbmMaskNone .. AmigaIlbmMaskLasso:
    raise newException(ValueError, "unsupported " & expectedFormType &
      " masking mode")
  if result.image.header.compression notin [0, 1]:
    raise newException(ValueError,
      "unsupported " & expectedFormType & " compression")
  result.image.planarLayout = planarLayout

proc parseAmigaIlbmForm*(form: AmigaIffForm): AmigaIlbm =
  parseAmigaBitmapForm(form, AmigaIlbmFormType, "BODY", aplRowInterleaved)

proc parseAmigaIlbm*(data: openArray[byte]): AmigaIlbm =
  parseAmigaIlbmForm(parseAmigaIff(data))

proc isAmigaIlbm*(data: openArray[byte]): bool =
  try:
    discard parseAmigaIlbm(data)
    true
  except ValueError:
    false

proc hasAmigaIlbmExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".iff", ".ilbm", ".lbm", ".lores"]
