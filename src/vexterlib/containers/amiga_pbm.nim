## Provisional parser for packed-pixel IFF FORM PBM images.

import std/[os, strutils]
import ./amiga_iff
import ./amiga_ilbm
import ../resources/[amiga_ilbm_image, amiga_pbm_image]

const
  AmigaPbmTypeId* = "amiga.pbm"
  AmigaPbmFormType* = "PBM "

type AmigaPbm* = object
  image*: AmigaPbmImageSource

proc parseAmigaPbm*(data: openArray[byte]): AmigaPbm =
  let form = parseAmigaIff(data)
  if form.formType != AmigaPbmFormType:
    raise newException(ValueError, "IFF FORM type is not PBM")
  var haveHeader, havePalette, haveBody: bool
  for chunk in form.chunks:
    case chunk.id
    of "BMHD":
      if haveHeader or haveBody:
        raise newException(ValueError, "IFF PBM must have one BMHD before BODY")
      result.image.header = parseAmigaBitmapHeader(chunk.data)
      haveHeader = true
    of "CMAP":
      if havePalette or haveBody or chunk.data.len mod 3 != 0 or
          chunk.data.len > 768:
        raise newException(ValueError, "invalid IFF PBM CMAP chunk")
      result.image.colourMap = chunk.data
      havePalette = true
    of "BODY":
      if not haveHeader or haveBody:
        raise newException(ValueError, "IFF PBM must have one BODY after BMHD")
      result.image.body = chunk.data
      haveBody = true
    else:
      discard
  if not haveHeader or not haveBody:
    raise newException(ValueError, "IFF PBM requires BMHD and BODY chunks")
  let header = result.image.header
  if header.width <= 0 or header.height <= 0:
    raise newException(ValueError, "IFF PBM dimensions must be positive")
  if header.planes != 8:
    raise newException(ValueError, "IFF PBM BMHD must describe eight-bit pixels")
  if header.compression notin [0, 1]:
    raise newException(ValueError, "unsupported IFF PBM compression")
  if header.masking notin [AmigaIlbmMaskNone,
      AmigaIlbmMaskTransparentColour]:
    raise newException(ValueError, "unsupported IFF PBM masking mode")
proc isAmigaPbm*(data: openArray[byte]): bool =
  try: discard parseAmigaPbm(data); true
  except ValueError: false

proc hasAmigaPbmExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".iff", ".lbm", ".pbm"]
