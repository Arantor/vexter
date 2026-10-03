## Parser for IFF FORM DEEP direct-colour images.

import std/[os, strutils]
import ./amiga_iff

const
  AmigaDeepTypeId* = "amiga.deep"
  AmigaDeepFormType* = "DEEP"
  AmigaDeepCompressionNone* = 0
  AmigaDeepCompressionRunLength* = 1
  AmigaDeepCompressionTvdc* = 5
  AmigaDeepComponentRed* = 1
  AmigaDeepComponentGreen* = 2
  AmigaDeepComponentBlue* = 3
  AmigaDeepComponentAlpha* = 4
  AmigaDeepComponentYellow* = 5
  AmigaDeepComponentCyan* = 6
  AmigaDeepComponentMagenta* = 7
  AmigaDeepComponentBlack* = 8
  AmigaDeepComponentMask* = 9
  AmigaDeepComponentZBuffer* = 10
  AmigaDeepComponentOpacity* = 11
  AmigaDeepComponentLinearKey* = 12
  AmigaDeepComponentBinaryKey* = 13

type
  AmigaDeepGlobal* = object
    displayWidth*, displayHeight*: int
    compression*: int
    xAspect*, yAspect*: int

  AmigaDeepComponent* = object
    componentType*, bitDepth*: int

  AmigaDeepLocation* = object
    width*, height*, x*, y*: int

  AmigaDeepBody* = object
    location*: AmigaDeepLocation
    data*: seq[byte]

  AmigaDeepFrame* = object
    bodies*: seq[AmigaDeepBody]
    durationMs*: int

  AmigaDeep* = object
    global*: AmigaDeepGlobal
    components*: seq[AmigaDeepComponent]
    frames*: seq[AmigaDeepFrame]
    annotation*: string

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc signedWord(data: openArray[byte], offset: int): int {.inline.} =
  int(cast[int16](uint16(beWord(data, offset))))

proc beLong(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc signedLong(data: openArray[byte], offset: int): int64 {.inline.} =
  int64(cast[int32](beLong(data, offset)))

proc text(data: openArray[byte]): string =
  for value in data:
    if value == 0: break
    result.add char(value)

proc parseGlobal(data: openArray[byte]): AmigaDeepGlobal =
  if data.len != 8:
    raise newException(ValueError, "IFF DEEP DGBL chunk must contain 8 bytes")
  result = AmigaDeepGlobal(displayWidth: beWord(data, 0),
    displayHeight: beWord(data, 2), compression: beWord(data, 4),
    xAspect: int(data[6]), yAspect: int(data[7]))
  if result.displayWidth <= 0 or result.displayHeight <= 0:
    raise newException(ValueError, "IFF DEEP display dimensions must be positive")
  if result.compression notin AmigaDeepCompressionNone .. AmigaDeepCompressionTvdc:
    raise newException(ValueError, "unknown IFF DEEP compression method")

proc parseComponents(data: openArray[byte]): seq[AmigaDeepComponent] =
  if data.len < 4 or (data.len - 4) mod 4 != 0:
    raise newException(ValueError, "invalid IFF DEEP DPEL chunk length")
  let count = beLong(data, 0)
  if count == 0 or uint64(count) != uint64((data.len - 4) div 4):
    raise newException(ValueError, "IFF DEEP DPEL component count is invalid")
  var totalBits = 0
  for index in 0 ..< int(count):
    let component = AmigaDeepComponent(
      componentType: beWord(data, 4 + index * 4),
      bitDepth: beWord(data, 6 + index * 4))
    if component.bitDepth <= 0:
      raise newException(ValueError, "IFF DEEP component depth must be positive")
    if totalBits > 4096 - component.bitDepth:
      raise newException(ValueError, "IFF DEEP pixel description is too large")
    totalBits += component.bitDepth
    result.add component

proc parseLocation(data: openArray[byte]): AmigaDeepLocation =
  if data.len != 8:
    raise newException(ValueError, "IFF DEEP DLOC chunk must contain 8 bytes")
  result = AmigaDeepLocation(width: beWord(data, 0), height: beWord(data, 2),
    x: signedWord(data, 4), y: signedWord(data, 6))
  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "IFF DEEP body dimensions must be positive")

proc parseAmigaDeep*(data: openArray[byte]): AmigaDeep =
  let form = parseAmigaIff(data)
  if form.formType != AmigaDeepFormType:
    raise newException(ValueError, "IFF FORM type is not DEEP")
  if form.chunks.len == 0 or form.chunks[0].id != "DGBL":
    raise newException(ValueError, "IFF DEEP must begin with DGBL")

  var
    haveGlobal, haveComponents, haveChange: bool
    location: AmigaDeepLocation
    current: AmigaDeepFrame
  for chunk in form.chunks:
    case chunk.id
    of "DGBL":
      if haveGlobal:
        raise newException(ValueError,
          "multiple IFF DEEP DGBL chunks are not yet supported")
      result.global = parseGlobal(chunk.data)
      location = AmigaDeepLocation(width: result.global.displayWidth,
        height: result.global.displayHeight)
      haveGlobal = true
    of "DPEL":
      if not haveGlobal or haveComponents or current.bodies.len > 0:
        raise newException(ValueError,
          "IFF DEEP requires one DPEL before image data")
      result.components = parseComponents(chunk.data)
      haveComponents = true
    of "DLOC":
      if not haveComponents:
        raise newException(ValueError, "IFF DEEP DLOC must follow DPEL")
      location = parseLocation(chunk.data)
    of "DBOD":
      if not haveComponents:
        raise newException(ValueError, "IFF DEEP DBOD must follow DPEL")
      if location.x < 0 or location.y < 0 or
          location.x > result.global.displayWidth - location.width or
          location.y > result.global.displayHeight - location.height:
        raise newException(ValueError,
          "IFF DEEP body lies outside the display dimensions")
      current.bodies.add AmigaDeepBody(location: location, data: chunk.data)
    of "DCHG":
      if chunk.data.len != 4:
        raise newException(ValueError, "IFF DEEP DCHG chunk must contain 4 bytes")
      if current.bodies.len == 0:
        raise newException(ValueError, "IFF DEEP DCHG has no preceding image data")
      let duration = signedLong(chunk.data, 0)
      if duration <= 0:
        raise newException(ValueError,
          "IFF DEEP zero and negative frame rates are not yet supported")
      current.durationMs = int(duration)
      result.frames.add move(current)
      current = AmigaDeepFrame()
      haveChange = true
    of "ANNO":
      result.annotation = text(chunk.data)
    else:
      discard

  if not haveComponents:
    raise newException(ValueError, "IFF DEEP requires a DPEL chunk")
  if haveChange:
    if current.bodies.len > 0:
      raise newException(ValueError,
        "animated IFF DEEP image data must end with DCHG")
  else:
    if current.bodies.len == 0:
      raise newException(ValueError, "IFF DEEP requires a DBOD chunk")
    result.frames.add move(current)

proc isAmigaDeep*(data: openArray[byte]): bool =
  try:
    discard parseAmigaDeep(data)
    true
  except ValueError:
    false

proc hasAmigaDeepExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".deep", ".iff"]
