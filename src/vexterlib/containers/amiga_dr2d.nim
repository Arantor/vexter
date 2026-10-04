## IFF FORM DR2D structured two-dimensional drawings.

import std/[math, os, sets, strutils, tables]
import ../archetypes/[raster, vector]
import ./amiga_iff

const
  AmigaDr2dTypeId* = "amiga.dr2d"
  AmigaDr2dResourceTypeId* = "amiga.dr2d-drawing"
  AmigaDr2dResourcePath* = "/drawing"

type
  Dr2dAttributes = object
    fillType, joinType, dashId, arrowId: int
    fillValue, edgeValue, layerId: int
    edgeWidth: float64

  AmigaDr2d* = object
    drawing*: VextVectorDrawing
    paletteEntries*, pathCount*, textCount*, imageCount*: int
    unsupportedPatternFills*, arrowReferences*: int

proc u16(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 2:
    raise newException(ValueError, "truncated DR2D word")
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc u32(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset > data.len - 4:
    raise newException(ValueError, "truncated DR2D longword")
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc ieee(data: openArray[byte], offset: int): float64 =
  let value = float64(cast[float32](u32(data, offset)))
  if value.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "DR2D coordinate is not finite")
  value

proc nulString(data: openArray[byte], offset, length: int): string =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "truncated DR2D string")
  for index in offset ..< offset + length:
    if data[index] == 0: break
    result.add char(data[index])

proc point(data: openArray[byte], offset: int): VextVectorPoint =
  VextVectorPoint(x: ieee(data, offset), y: ieee(data, offset + 4))

proc parsePath(data: openArray[byte], closed: bool,
    style: VextVectorPathStyle): VextVectorPath =
  if data.len < 2:
    raise newException(ValueError, "truncated DR2D polygon")
  let count = u16(data, 0)
  if count == 0 or data.len != 2 + count * 8:
    raise newException(ValueError, "DR2D polygon point count does not match its chunk")
  result.style = style
  var index = 0
  var started = false
  while index < count:
    let offset = 2 + index * 8
    if u32(data, offset) == 0xffffffff'u32:
      let flags = u32(data, offset + 4)
      if (flags and not 3'u32) != 0:
        raise newException(ValueError, "DR2D polygon uses unknown indicator flags")
      if (flags and 2) != 0:
        if closed and started:
          result.commands.add VextVectorCommand(kind: vvckClose)
        started = false
      if (flags and 1) != 0:
        if index > count - 5:
          raise newException(ValueError, "truncated DR2D cubic spline")
        let p1 = point(data, offset + 8)
        result.commands.add VextVectorCommand(
          kind: if started: vvckLine else: vvckMove, point: p1)
        result.commands.add VextVectorCommand(kind: vvckCubic,
          control1: point(data, offset + 16),
          control2: point(data, offset + 24),
          point: point(data, offset + 32))
        started = true
        index += 5
      else:
        inc index
    else:
      result.commands.add VextVectorCommand(
        kind: if started: vvckLine else: vvckMove,
        point: point(data, offset))
      started = true
      inc index
  if closed and started:
    result.commands.add VextVectorCommand(kind: vvckClose)
  if result.commands.len == 0:
    raise newException(ValueError, "DR2D polygon contains no drawable points")

proc hasAmigaDr2dExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".dr2d", ".dr2"]

proc parseAmigaDr2d*(data: openArray[byte]): AmigaDr2d =
  let form = parseAmigaIff(data)
  if form.formType != "DR2D":
    raise newException(ValueError, "IFF FORM is not a DR2D drawing")

  var
    headerSeen = false
    palette: seq[VextRgba]
    dashes = initTable[int, seq[float64]]()
    fonts = initTable[int, VextVectorFont]()
    layerVisibility = initTable[int, bool]()
    arrowIds, fillIds = initHashSet[int]()
    pathCount, textCount, imageCount, arrowReferences: int

  for chunk in form.chunks:
    case chunk.id
    of "DRHD":
      if headerSeen or chunk.data.len != 16:
        raise newException(ValueError, "DR2D requires one 16-byte DRHD chunk")
      headerSeen = true
      result.drawing.bounds = VextVectorBounds(left: ieee(chunk.data, 0),
        top: ieee(chunk.data, 4), right: ieee(chunk.data, 8),
        bottom: ieee(chunk.data, 12))
    of "CMAP":
      if chunk.data.len mod 3 != 0:
        raise newException(ValueError, "DR2D CMAP length is not a multiple of three")
      var offset = 0
      while offset < chunk.data.len:
        palette.add VextRgba(r: chunk.data[offset], g: chunk.data[offset + 1],
          b: chunk.data[offset + 2], a: 255)
        offset += 3
    of "DASH":
      if chunk.data.len < 4:
        raise newException(ValueError, "truncated DR2D DASH chunk")
      let id = u16(chunk.data, 0)
      let count = u16(chunk.data, 2)
      if id == 0 or (count and 1) != 0 or chunk.data.len != 4 + count * 4:
        raise newException(ValueError, "invalid DR2D DASH definition")
      if dashes.hasKey(id):
        raise newException(ValueError, "duplicate DR2D DASH identifier")
      var pattern: seq[float64]
      for index in 0 ..< count:
        let value = ieee(chunk.data, 4 + index * 4)
        if value <= 0:
          raise newException(ValueError, "DR2D dash lengths must be positive")
        pattern.add value
      dashes[id] = pattern
    of "FONS":
      if chunk.data.len < 4 or chunk.data[1] != 0:
        raise newException(ValueError, "invalid DR2D FONS chunk")
      if chunk.data[2] > 2 or chunk.data[3] > 2:
        raise newException(ValueError, "invalid DR2D FONS traits")
      if fonts.hasKey(int(chunk.data[0])):
        raise newException(ValueError, "duplicate DR2D FONS identifier")
      let font = VextVectorFont(reference: $int(chunk.data[0]),
        name: nulString(chunk.data, 4, chunk.data.len - 4),
        proportional: VextVectorFontTrait(chunk.data[2]),
        serif: VextVectorFontTrait(chunk.data[3]))
      fonts[int(chunk.data[0])] = font
      result.drawing.fonts.add font
    of "AROW":
      if chunk.data.len < 14 or chunk.data[1] != 0 or
          (chunk.data[0] and not 3'u8) != 0:
        raise newException(ValueError, "invalid DR2D AROW chunk")
      let
        id = u16(chunk.data, 2)
        count = u16(chunk.data, 4)
      if id == 0 or count == 0 or chunk.data.len != 6 + count * 8 or
          id in arrowIds:
        raise newException(ValueError, "invalid DR2D AROW definition")
      var polygon = newSeq[byte](2 + count * 8)
      polygon[0] = byte(count shr 8)
      polygon[1] = byte(count)
      for index in 0 ..< count * 8: polygon[2 + index] = chunk.data[6 + index]
      discard parsePath(polygon, true, VextVectorPathStyle())
      arrowIds.incl id
    of "LAYR":
      if chunk.data.len != 20 or chunk.data[19] != 0:
        raise newException(ValueError, "invalid DR2D LAYR chunk")
      let id = u16(chunk.data, 0)
      if layerVisibility.hasKey(id):
        raise newException(ValueError, "duplicate DR2D LAYR identifier")
      let visible = (chunk.data[18] and 2) != 0
      layerVisibility[id] = visible
      result.drawing.layers.add VextVectorLayer(id: id,
        name: nulString(chunk.data, 2, 16), visible: visible,
        editable: (chunk.data[18] and 1) != 0)
    of "PPRF":
      if chunk.data.len > 0 and chunk.data[^1] != 0:
        raise newException(ValueError, "DR2D PPRF strings are not terminated")
      var offset = 0
      while offset < chunk.data.len:
        var finish = offset
        while finish < chunk.data.len and chunk.data[finish] != 0: inc finish
        let preference = nulString(chunk.data, offset, finish - offset)
        if preference.startsWith("Units="):
          result.drawing.units = preference[6 .. ^1]
        offset = finish + 1
    else: discard
    if chunk.id == "FORM":
      let nested = parseAmigaIffFormPayload(chunk.data)
      if nested.formType == "DR2D" and nested.chunks.len > 0 and
          nested.chunks[0].id == "FILL":
        if nested.chunks[0].data.len != 2:
          raise newException(ValueError, "invalid DR2D FILL definition")
        let id = u16(nested.chunks[0].data, 0)
        if id == 0 or id in fillIds:
          raise newException(ValueError, "duplicate or zero DR2D FILL identifier")
        fillIds.incl id
  if not headerSeen:
    raise newException(ValueError, "DR2D drawing is missing its required DRHD chunk")
  if result.drawing.units.len == 0: result.drawing.units = "Inch"
  result.drawing.background = VextRgba(r: 255, g: 255, b: 255, a: 255)
  result.paletteEntries = palette.len

  proc colour(index: int): VextRgba =
    if index < 0 or index >= palette.len:
      raise newException(ValueError, "DR2D colour index is outside its CMAP")
    palette[index]

  proc style(attributes: Dr2dAttributes, allowFill: bool): VextVectorPathStyle =
    result.join = VextVectorLineJoin(attributes.joinType)
    result.strokeWidth = attributes.edgeWidth
    if attributes.dashId != 0:
      if not dashes.hasKey(attributes.dashId):
        raise newException(ValueError, "DR2D object references an undefined DASH")
      result.hasStroke = attributes.edgeWidth > 0
      if result.hasStroke:
        result.stroke = colour(attributes.edgeValue)
        for value in dashes[attributes.dashId]:
          result.dashPattern.add value * attributes.edgeWidth
    if allowFill:
      case attributes.fillType
      of 0: discard
      of 1:
        result.hasFill = true
        result.fill = colour(attributes.fillValue)
      of 2:
        if attributes.fillValue notin fillIds:
          raise newException(ValueError,
            "DR2D object references an undefined FILL pattern")
      else: raise newException(ValueError, "unsupported DR2D fill type")

  proc parseObjects(chunks: openArray[AmigaIffChunk], initial: Dr2dAttributes,
      layerOverride = -1): seq[VextVectorElement] =
    var attributes = initial
    for chunk in chunks:
      case chunk.id
      of "ATTR":
        if chunk.data.len != 14:
          raise newException(ValueError, "DR2D ATTR chunk must contain 14 bytes")
        attributes = Dr2dAttributes(fillType: int(chunk.data[0]),
          joinType: int(chunk.data[1]), dashId: int(chunk.data[2]),
          arrowId: int(chunk.data[3]), fillValue: u16(chunk.data, 4),
          edgeValue: u16(chunk.data, 6), layerId: u16(chunk.data, 8),
          edgeWidth: ieee(chunk.data, 10))
        if attributes.fillType notin 0 .. 2 or
            attributes.joinType notin 0 .. 3 or attributes.edgeWidth < 0:
          raise newException(ValueError, "invalid DR2D object attributes")
        if attributes.arrowId != 0 and attributes.arrowId notin arrowIds:
          raise newException(ValueError,
            "DR2D object references an undefined AROW definition")
      of "CPLY", "OPLY":
        let layer = if layerOverride >= 0: layerOverride else: attributes.layerId
        let pathStyle = style(attributes, chunk.id == "CPLY")
        result.add VextVectorElement(kind: vvekPath, layerId: layer,
          visible: layerVisibility.getOrDefault(layer, true),
          path: parsePath(chunk.data, chunk.id == "CPLY", pathStyle))
        inc pathCount
        if chunk.id == "OPLY" and attributes.arrowId != 0: inc arrowReferences
      of "STXT":
        if chunk.data.len < 24 or chunk.data[0] != 0:
          raise newException(ValueError, "truncated DR2D STXT chunk")
        let count = u16(chunk.data, 22)
        if chunk.data.len != 24 + count:
          raise newException(ValueError, "DR2D STXT character count does not match its chunk")
        let fontId = int(chunk.data[1])
        let font = fonts.getOrDefault(fontId)
        let layer = if layerOverride >= 0: layerOverride else: attributes.layerId
        result.add VextVectorElement(kind: vvekText, layerId: layer,
          visible: layerVisibility.getOrDefault(layer, true),
          text: VextVectorText(text: nulString(chunk.data, 24, count),
            fontReference: $fontId, fontName: font.name,
            characterWidth: ieee(chunk.data, 2),
            characterHeight: ieee(chunk.data, 6),
            base: VextVectorPoint(x: ieee(chunk.data, 10), y: ieee(chunk.data, 14)),
            rotationDegrees: ieee(chunk.data, 18)))
        inc textCount
      of "TPTH":
        if chunk.data.len < 14 or chunk.data[0] > 3 or ieee(chunk.data, 2) < 0:
          raise newException(ValueError, "invalid DR2D TPTH chunk")
        let
          characterCount = u16(chunk.data, 10)
          pointCount = u16(chunk.data, 12)
          paddedCharacters = characterCount + (characterCount and 1)
          pathOffset = 14 + paddedCharacters
        if pointCount == 0 or chunk.data.len != pathOffset + pointCount * 8:
          raise newException(ValueError,
            "DR2D TPTH character or point count does not match its chunk")
        var pathData = newSeq[byte](2 + pointCount * 8)
        pathData[0] = byte(pointCount shr 8)
        pathData[1] = byte(pointCount and 0xff)
        for index in 0 ..< pointCount * 8:
          pathData[2 + index] = chunk.data[pathOffset + index]
        let parsedPath = parsePath(pathData, false, VextVectorPathStyle())
        let fontId = int(chunk.data[1])
        let font = fonts.getOrDefault(fontId)
        let layer = if layerOverride >= 0: layerOverride else: attributes.layerId
        result.add VextVectorElement(kind: vvekText, layerId: layer,
          visible: layerVisibility.getOrDefault(layer, true),
          text: VextVectorText(
            text: nulString(chunk.data, 14, characterCount),
            fontReference: $fontId, fontName: font.name,
            alignment: VextVectorTextAlignment(chunk.data[0]),
            characterWidth: ieee(chunk.data, 2),
            characterHeight: ieee(chunk.data, 6),
            alongPath: parsedPath.commands))
        inc textCount
      of "VBM ":
        if chunk.data.len < 22:
          raise newException(ValueError, "truncated DR2D VBM chunk")
        let length = u16(chunk.data, 20)
        if length == 0 or chunk.data.len != 22 + length or chunk.data[^1] != 0:
          raise newException(ValueError, "DR2D VBM path length does not match its chunk")
        let layer = if layerOverride >= 0: layerOverride else: attributes.layerId
        result.add VextVectorElement(kind: vvekExternalImage, layerId: layer,
          visible: layerVisibility.getOrDefault(layer, true),
          externalImage: VextVectorExternalImage(
            position: VextVectorPoint(x: ieee(chunk.data, 0), y: ieee(chunk.data, 4)),
            width: ieee(chunk.data, 8), height: ieee(chunk.data, 12),
            rotationDegrees: ieee(chunk.data, 16),
            path: nulString(chunk.data, 22, length)))
        inc imageCount
      of "FORM":
        let nested = parseAmigaIffFormPayload(chunk.data)
        if nested.formType != "DR2D" or nested.chunks.len == 0 or
            nested.chunks[0].id notin ["GRUP", "FILL"]:
          raise newException(ValueError, "invalid nested DR2D FORM")
        if nested.chunks[0].id == "GRUP":
          if nested.chunks[0].data.len != 2:
            raise newException(ValueError, "invalid DR2D GRUP chunk")
          let layer = if layerOverride >= 0: layerOverride else: attributes.layerId
          var children: seq[VextVectorElement]
          if nested.chunks.len > 1:
            children = parseObjects(nested.chunks.toOpenArray(1,
              nested.chunks.high), attributes, layer)
          if children.len != u16(nested.chunks[0].data, 0):
            raise newException(ValueError, "DR2D GRUP object count does not match its contents")
          result.add VextVectorElement(kind: vvekGroup, layerId: layer,
            visible: layerVisibility.getOrDefault(layer, true), children: children)
        else:
          if nested.chunks[0].data.len != 2:
            raise newException(ValueError, "invalid DR2D FILL definition")
      else: discard

  result.drawing.elements = parseObjects(form.chunks, Dr2dAttributes())
  result.pathCount = pathCount
  result.textCount = textCount
  result.imageCount = imageCount
  result.unsupportedPatternFills = fillIds.len
  result.arrowReferences = arrowReferences
  result.drawing.validate()

proc isAmigaDr2d*(data: openArray[byte]): bool =
  try:
    discard parseAmigaDr2d(data)
    true
  except ValueError:
    false
