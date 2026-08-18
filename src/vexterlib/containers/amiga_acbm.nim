## ACBM-specific structure parsed from a generic IFF FORM.

import std/[os, strutils]
import ./[amiga_iff, amiga_ilbm]
import ../resources/amiga_ilbm_image

const
  AmigaAcbmTypeId* = "amiga.acbm"
  AmigaAcbmFormType* = "ACBM"

type AmigaAcbm* = object
  image*: AmigaIlbmImageSource

proc parseAmigaAcbmForm*(form: AmigaIffForm): AmigaAcbm =
  let bitmap = parseAmigaBitmapForm(form, AmigaAcbmFormType, "ABIT",
    aplPlaneContiguous)
  result.image = bitmap.image

proc parseAmigaAcbm*(data: openArray[byte]): AmigaAcbm =
  parseAmigaAcbmForm(parseAmigaIff(data))

proc isAmigaAcbm*(data: openArray[byte]): bool =
  try:
    discard parseAmigaAcbm(data)
    true
  except ValueError:
    false

proc hasAmigaAcbmExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".acbm", ".iff"]
