## Format-neutral two-dimensional vector drawings.

import std/math
import ./raster

type
  VextVectorPoint* = object
    x*, y*: float64

  VextVectorBounds* = object
    left*, top*, right*, bottom*: float64

  VextVectorCommandKind* = enum
    vvckMove
    vvckLine
    vvckCubic
    vvckClose

  VextVectorCommand* = object
    kind*: VextVectorCommandKind
    point*: VextVectorPoint
    control1*, control2*: VextVectorPoint

  VextVectorLineJoin* = enum
    vvljNone
    vvljMiter
    vvljBevel
    vvljRound

  VextVectorPathStyle* = object
    hasFill*, hasStroke*: bool
    fill*, stroke*: VextRgba
    strokeWidth*: float64
    join*: VextVectorLineJoin
    dashPattern*: seq[float64]

  VextVectorPath* = object
    commands*: seq[VextVectorCommand]
    style*: VextVectorPathStyle

  VextVectorFontTrait* = enum
    vvftUnknown
    vvftNo
    vvftYes

  VextVectorFont* = object
    reference*, name*: string
    proportional*, serif*: VextVectorFontTrait

  VextVectorTextAlignment* = enum
    vvtaLeft
    vvtaRight
    vvtaCentre
    vvtaSpread

  VextVectorText* = object
    text*: string
    fontReference*: string
    fontName*: string
    alignment*: VextVectorTextAlignment
    base*: VextVectorPoint
    characterWidth*, characterHeight*, rotationDegrees*: float64
    alongPath*: seq[VextVectorCommand]

  VextVectorExternalImage* = object
    path*: string
    position*: VextVectorPoint
    width*, height*, rotationDegrees*: float64

  VextVectorElementKind* = enum
    vvekPath
    vvekText
    vvekExternalImage
    vvekGroup

  VextVectorElement* = object
    visible*: bool
    layerId*: int
    case kind*: VextVectorElementKind
    of vvekPath:
      path*: VextVectorPath
    of vvekText:
      text*: VextVectorText
    of vvekExternalImage:
      externalImage*: VextVectorExternalImage
    of vvekGroup:
      children*: seq[VextVectorElement]

  VextVectorLayer* = object
    id*: int
    name*: string
    visible*, editable*: bool

  VextVectorDrawing* = object
    bounds*: VextVectorBounds
    units*: string
    background*: VextRgba
    fonts*: seq[VextVectorFont]
    layers*: seq[VextVectorLayer]
    elements*: seq[VextVectorElement]

proc validate*(drawing: VextVectorDrawing) =
  proc finite(value: float64): bool =
    value.classify notin {fcNan, fcInf, fcNegInf}
  proc validatePoint(point: VextVectorPoint) =
    if not point.x.finite or not point.y.finite:
      raise newException(ValueError, "vector point must be finite")
  if not drawing.bounds.left.finite or not drawing.bounds.top.finite or
      not drawing.bounds.right.finite or not drawing.bounds.bottom.finite:
    raise newException(ValueError, "vector drawing bounds must be finite")
  if drawing.bounds.left == drawing.bounds.right or
      drawing.bounds.top == drawing.bounds.bottom:
    raise newException(ValueError, "vector drawing bounds must have non-zero dimensions")
  proc validateElement(element: VextVectorElement) =
    case element.kind
    of vvekPath:
      if element.path.commands.len == 0:
        raise newException(ValueError, "vector path contains no commands")
      if not element.path.style.strokeWidth.finite or
          element.path.style.strokeWidth < 0:
        raise newException(ValueError,
          "vector stroke width must be finite and non-negative")
      for length in element.path.style.dashPattern:
        if not length.finite or length <= 0:
          raise newException(ValueError,
            "vector dash lengths must be finite and positive")
      for command in element.path.commands:
        case command.kind
        of vvckMove, vvckLine: command.point.validatePoint
        of vvckCubic:
          command.control1.validatePoint
          command.control2.validatePoint
          command.point.validatePoint
        of vvckClose: discard
    of vvekText:
      element.text.base.validatePoint
      if not element.text.characterWidth.finite or
          not element.text.characterHeight.finite or
          not element.text.rotationDegrees.finite:
        raise newException(ValueError, "vector text metrics must be finite")
    of vvekExternalImage:
      element.externalImage.position.validatePoint
      if not element.externalImage.width.finite or
          not element.externalImage.height.finite or
          not element.externalImage.rotationDegrees.finite:
        raise newException(ValueError,
          "vector external-image geometry must be finite")
    of vvekGroup:
      for child in element.children: validateElement(child)
  for element in drawing.elements: validateElement(element)

proc vectorElementCounts*(drawing: VextVectorDrawing):
    tuple[paths, texts, images, groups: int] =
  var paths, texts, images, groups: int
  proc count(element: VextVectorElement) =
    case element.kind
    of vvekPath: inc paths
    of vvekText: inc texts
    of vvekExternalImage: inc images
    of vvekGroup:
      inc groups
      for child in element.children: count(child)
  for element in drawing.elements: count(element)
  (paths, texts, images, groups)
