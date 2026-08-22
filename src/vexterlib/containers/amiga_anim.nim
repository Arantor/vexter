## Structural parser for IFF FORM ANIM containers.

import std/[os, strutils]
import ./[amiga_iff, amiga_ilbm]

const
  AmigaAnimTypeId* = "amiga.anim"
  AmigaAnimFormType* = "ANIM"

type
  AmigaAnimHeader* = object
    operation*: int
    mask*: int
    width*, height*: int
    x*, y*: int
    absoluteTime*, relativeTime*: uint32
    interleave*: int
    bits*: uint32

  AmigaAnimDeltaFrame* = object
    header*: AmigaAnimHeader
    delta*: seq[byte]
    body*: seq[byte]
    colourMap*: seq[byte]
    hasColourMap*: bool
    camg*: uint32
    hasCamg*: bool

  AmigaAnim* = object
    initial*: AmigaIlbm
    initialHeader*: AmigaAnimHeader
    hasInitialHeader*: bool
    dpanVersion*, logicalFrameCount*, framesPerSecond*: int
    hasDpan*: bool
    frames*: seq[AmigaAnimDeltaFrame]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc beLong(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc signedWord(data: openArray[byte], offset: int): int {.inline.} =
  int(cast[int16](uint16(beWord(data, offset))))

proc parseAnimHeader(data: openArray[byte]): AmigaAnimHeader =
  if data.len != 40:
    raise newException(ValueError, "ANIM ANHD chunk must contain 40 bytes")
  result = AmigaAnimHeader(
    operation: int(data[0]), mask: int(data[1]),
    width: beWord(data, 2), height: beWord(data, 4),
    x: signedWord(data, 6), y: signedWord(data, 8),
    absoluteTime: beLong(data, 10), relativeTime: beLong(data, 14),
    interleave: int(data[18]), bits: beLong(data, 20))

proc findInitialHeader(form: AmigaIffForm,
    header: var AmigaAnimHeader, found: var bool) =
  for chunk in form.chunks:
    if chunk.id == "ANHD":
      header = parseAnimHeader(chunk.data)
      found = true

proc findDpan(form: AmigaIffForm, anim: var AmigaAnim) =
  for chunk in form.chunks:
    if chunk.id == "DPAN":
      if chunk.data.len != 8:
        raise newException(ValueError, "ANIM DPAN chunk must contain 8 bytes")
      anim.dpanVersion = beWord(chunk.data, 0)
      if anim.dpanVersion != 3:
        raise newException(ValueError, "unsupported ANIM DPAN version")
      anim.logicalFrameCount = beWord(chunk.data, 2)
      anim.framesPerSecond = int(chunk.data[4])
      if anim.logicalFrameCount <= 0 or anim.framesPerSecond <= 0:
        raise newException(ValueError, "ANIM DPAN playback values are invalid")
      anim.hasDpan = true

proc parseDeltaFrame(form: AmigaIffForm): AmigaAnimDeltaFrame =
  if form.formType != "ILBM":
    raise newException(ValueError, "ANIM frames must use FORM ILBM")
  var haveHeader, havePayload: bool
  for chunk in form.chunks:
    case chunk.id
    of "ANHD":
      result.header = parseAnimHeader(chunk.data)
      haveHeader = true
    of "DLTA":
      result.delta = chunk.data
      havePayload = true
    of "BODY":
      result.body = chunk.data
      havePayload = true
    of "CMAP":
      if chunk.data.len mod 3 != 0:
        raise newException(ValueError, "ANIM CMAP length is invalid")
      result.colourMap = chunk.data
      result.hasColourMap = true
    of "CAMG":
      if chunk.data.len != 4:
        raise newException(ValueError, "ANIM CAMG length is invalid")
      result.camg = beLong(chunk.data, 0)
      result.hasCamg = true
    else:
      discard
  if not haveHeader or not havePayload:
    raise newException(ValueError, "ANIM delta frame requires ANHD and data")
  if result.header.operation in [0, 1] and result.body.len == 0:
    raise newException(ValueError, "ANIM direct/XOR frame requires BODY")
  if result.header.operation notin [0, 1] and result.delta.len == 0:
    raise newException(ValueError, "ANIM delta method requires DLTA")

proc parseAmigaAnim*(data: openArray[byte]): AmigaAnim =
  let outer = parseAmigaIff(data)
  if outer.formType != AmigaAnimFormType:
    raise newException(ValueError, "IFF FORM type is not ANIM")
  var forms: seq[AmigaIffForm]
  for chunk in outer.chunks:
    if chunk.id == "FORM":
      forms.add parseAmigaIffFormPayload(chunk.data)
  if forms.len == 0:
    raise newException(ValueError, "ANIM contains no frame FORMs")
  result.initial = parseAmigaIlbmForm(forms[0])
  findInitialHeader(forms[0], result.initialHeader, result.hasInitialHeader)
  findDpan(forms[0], result)
  if result.hasInitialHeader and result.initialHeader.operation != 0:
    raise newException(ValueError,
      "DLTA-compressed first ANIM frames are not supported yet")
  for index in 1 ..< forms.len:
    result.frames.add parseDeltaFrame(forms[index])
  if result.hasDpan and result.logicalFrameCount > result.frames.len + 1:
    raise newException(ValueError, "ANIM DPAN frame count exceeds stored frames")

proc isAmigaAnim*(data: openArray[byte]): bool =
  try:
    discard parseAmigaAnim(data)
    true
  except ValueError:
    false

proc hasAmigaAnimExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".anim", ".anm"]
