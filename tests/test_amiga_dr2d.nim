import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

proc addDword(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc addFloat(data: var seq[byte], value: float32) =
  data.addDword(cast[uint32](value))

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.addDword(uint32(payload.len))
  result.add payload
  if (payload.len and 1) != 0: result.add 0

proc form(chunks: openArray[seq[byte]]): seq[byte] =
  var payload: seq[byte]
  for value in "DR2D": payload.add byte(value)
  for value in chunks: payload.add value
  for value in "FORM": result.add byte(value)
  result.addDword(uint32(payload.len))
  result.add payload

proc header(): seq[byte] =
  for value in [0'f32, 0'f32, 2'f32, 1'f32]: result.addFloat(value)

proc layer(): seq[byte] =
  result.addWord(7)
  for value in "Visible": result.add byte(value)
  while result.len < 18: result.add 0
  result.add 3 # active and displayed
  result.add 0

proc attributes(fillType = 1, dash = 1): seq[byte] =
  result.add byte(fillType)
  result.add 1 # miter join
  result.add byte(dash)
  result.add 0 # no arrow
  result.addWord(1) # red fill
  result.addWord(2) # blue edge
  result.addWord(7)
  result.addFloat(0.08)

proc polygon(points: openArray[(float32, float32)]): seq[byte] =
  result.addWord(points.len)
  for point in points:
    result.addFloat(point[0])
    result.addFloat(point[1])

proc basicDrawing(extra: openArray[seq[byte]] = []): seq[byte] =
  var dash: seq[byte]
  dash.addWord(1)
  dash.addWord(0) # Defined solid edge.
  var chunks = @[
    chunk("DRHD", header()),
    chunk("CMAP", @[255'u8, 255, 255, 220, 20, 20, 20, 30, 220]),
    chunk("DASH", dash),
    chunk("LAYR", layer()),
    chunk("ATTR", attributes()),
    chunk("CPLY", polygon(@[(0.25'f32, 0.2'f32), (1.75'f32, 0.2'f32),
      (1.75'f32, 0.8'f32), (0.25'f32, 0.8'f32)]))]
  chunks.add extra
  form(chunks)

suite "IFF DR2D vector drawings":
  test "detection produces a generic vector resource and PNG preview":
    let inspection = inspectSource("rectangle.dr2d", basicDrawing())
    check inspection.selectedFormat.typeId == AmigaDr2dTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.resources.roots.len == 1
    let resource = inspection.resources.roots[0]
    check resource.kind == vrnkVector
    check resource.path == AmigaDr2dResourcePath
    check resource.vector.layers.len == 1
    check resource.vector.elements.len == 1
    check resource.vector.elements[0].path.commands.len == 5
    check resource.defaultExportFormat == "png"

    let preview = renderVectorDrawing(resource.vector, 80)
    check preview.width == 80
    check preview.height == 40
    check preview.colourAt(40, 20).r > 180
    check preview.colourAt(40, 20).g < 80

    let exported = exportResource(inspection.resources,
      VextExportRequest(resourcePath: AmigaDr2dResourcePath,
        outputFormat: "png", suggestedName: "drawing"))
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].data[0 .. 7] ==
      @[137'u8, 80, 78, 71, 13, 10, 26, 10]

  test "cubic subpaths and text-on-path remain structured":
    var path: seq[byte]
    path.addWord(5)
    path.addDword(0xffffffff'u32)
    path.addDword(3) # MOVETO and cubic spline.
    for point in [(0.1'f32, 0.5'f32), (0.5'f32, 0.0'f32),
        (1.5'f32, 1.0'f32), (1.9'f32, 0.5'f32)]:
      path.addFloat(point[0])
      path.addFloat(point[1])
    var textPath: seq[byte]
    textPath.add 0 # left justified
    textPath.add 1 # font id
    textPath.addFloat(0.1)
    textPath.addFloat(0.2)
    textPath.addWord(3)
    textPath.addWord(2)
    for value in "abc": textPath.add byte(value)
    textPath.add 0 # even padding
    for point in [(0.0'f32, 0.5'f32), (2.0'f32, 0.5'f32)]:
      textPath.addFloat(point[0])
      textPath.addFloat(point[1])
    var font = @[1'u8, 0, 1, 0]
    for value in "Roman\0": font.add byte(value)
    let parsed = parseAmigaDr2d(form(@[
      chunk("DRHD", header()), chunk("CMAP", @[0'u8, 0, 0]),
      chunk("FONS", font), chunk("ATTR", attributes(0, 0)),
      chunk("OPLY", path), chunk("TPTH", textPath)]))
    check parsed.pathCount == 1
    check parsed.textCount == 1
    check parsed.drawing.elements[0].path.commands[1].kind == vvckCubic
    check parsed.drawing.elements[1].text.text == "abc"
    check parsed.drawing.elements[1].text.fontName == "Roman"
    check parsed.drawing.elements[1].text.alongPath.len == 2
    check parsed.drawing.vectorPreviewWarnings.len == 1

  test "malformed counts and missing headers are rejected":
    expect ValueError:
      discard parseAmigaDr2d(form(@[chunk("CMAP", @[0'u8, 0, 0])]))
    var badPolygon = polygon(@[(0'f32, 0'f32)])
    badPolygon[1] = 2
    expect ValueError:
      discard parseAmigaDr2d(form(@[
        chunk("DRHD", header()), chunk("CMAP", @[0'u8, 0, 0]),
        chunk("ATTR", attributes(0, 0)), chunk("OPLY", badPolygon)]))

