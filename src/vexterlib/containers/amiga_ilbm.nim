## ILBM-specific structure parsed from a generic IFF FORM.

import std/[os, strutils]
import ./amiga_iff
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

proc parseHeader(data: openArray[byte]): AmigaIlbmHeader =
  if data.len != 20:
    raise newException(ValueError, "ILBM BMHD chunk must contain 20 bytes")
  AmigaIlbmHeader(
    width: beWord(data, 0), height: beWord(data, 2),
    x: signedWord(data, 4), y: signedWord(data, 6),
    planes: int(data[8]), masking: int(data[9]),
    compression: int(data[10]), transparentColour: beWord(data, 12),
    xAspect: int(data[14]), yAspect: int(data[15]),
    pageWidth: signedWord(data, 16), pageHeight: signedWord(data, 18))

proc parseAmigaIlbmForm*(form: AmigaIffForm): AmigaIlbm =
  if form.formType != AmigaIlbmFormType:
    raise newException(ValueError, "IFF FORM type is not ILBM")
  var haveHeader, haveBody: bool
  for chunk in form.chunks:
    case chunk.id
    of "BMHD":
      if haveBody:
        raise newException(ValueError, "ILBM BMHD must precede BODY")
      result.image.header = parseHeader(chunk.data)
      haveHeader = true
    of "CMAP":
      if haveBody:
        raise newException(ValueError, "ILBM CMAP must precede BODY")
      if chunk.data.len mod 3 != 0:
        raise newException(ValueError,
          "ILBM CMAP length must be divisible by three")
      result.image.colourMap = chunk.data
    of "CAMG":
      if haveBody:
        raise newException(ValueError, "ILBM CAMG must precede BODY")
      if chunk.data.len != 4:
        raise newException(ValueError, "ILBM CAMG chunk must contain four bytes")
      result.image.camg = beLong(chunk.data)
    of "BODY":
      if not haveHeader:
        raise newException(ValueError, "ILBM BODY must follow BMHD")
      if haveBody:
        raise newException(ValueError, "ILBM may contain only one BODY chunk")
      result.image.body = chunk.data
      haveBody = true
    else:
      discard
  if not haveHeader or not haveBody:
    raise newException(ValueError, "ILBM requires BMHD and BODY chunks")
  if result.image.header.planes < 1:
    raise newException(ValueError, "ILBM must contain at least one bitplane")
  if result.image.header.compression notin [0, 1]:
    raise newException(ValueError, "unsupported ILBM compression")

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
