## OpenRaster baseline package parsing over an already expanded ZIP carrier.

import std/[parseutils, strutils, unicode, xmlparser, xmltree]
import ./png_container
import ./zip_archive

const
  OpenRasterTypeId* = "image.openraster"
  OpenRasterImageTypeId* = "openraster.image"
  OpenRasterThumbnailTypeId* = "openraster.thumbnail"
  OpenRasterStackTypeId* = "openraster.stack"
  OpenRasterLayerTypeId* = "openraster.layer"
  OpenRasterMimeType* = "image/openraster"

type
  OpenRasterElementKind* = enum
    orekStack
    orekLayer

  OpenRasterElement* = ref object
    kind*: OpenRasterElementKind
    name*: string
    opacity*: float
    visibility*: string
    compositeOp*: string
    x*, y*: int
    selected*: bool
    isolation*: string
    sourcePath*: string
    sourceData*: seq[byte]
    pngSource*: bool
    image*: PngImageSource
    children*: seq[OpenRasterElement]

  OpenRasterDocument* = object
    version*: string
    name*: string
    width*, height*: int
    xResolution*, yResolution*: int
    stack*: OpenRasterElement
    mergedImage*: PngImageSource
    thumbnail*: PngImageSource

proc entryNamed(archive: ZipArchive, name: string): ptr ZipEntry =
  for index in 0 .. archive.entries.high:
    if archive.entries[index].name == name and
        not archive.entries[index].isDirectory:
      return unsafeAddr archive.entries[index]

proc bytesText(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc integerAttribute(node: XmlNode, name: string, required = false): int =
  let value = node.attr(name)
  if value.len == 0:
    if required:
      raise newException(ValueError,
        "OpenRaster XML attribute is missing: " & name)
    return 0
  if value.parseInt(result) != value.len:
    raise newException(ValueError,
      "OpenRaster XML integer attribute is invalid: " & name)

proc opacityAttribute(node: XmlNode): float =
  let value = node.attr("opacity")
  if value.len == 0: return 1.0
  if value.parseFloat(result) != value.len or result < 0.0 or result > 1.0:
    raise newException(ValueError, "OpenRaster opacity is invalid")

proc commonElement(node: XmlNode, kind: OpenRasterElementKind):
    OpenRasterElement =
  result = OpenRasterElement(kind: kind, name: node.attr("name"),
    opacity: node.opacityAttribute, visibility: node.attr("visibility"),
    compositeOp: node.attr("composite-op"), x: node.integerAttribute("x"),
    y: node.integerAttribute("y"))
  if result.visibility.len == 0: result.visibility = "visible"
  if result.visibility notin ["visible", "hidden"]:
    raise newException(ValueError, "OpenRaster visibility is invalid")
  if result.compositeOp.len == 0: result.compositeOp = "svg:src-over"

proc safeRelativePath(path: string): bool =
  if path.len == 0 or path[0] == '/' or '\\' in path or ':' in path or
      '\0' in path:
    return false
  for segment in path.split('/'):
    if segment.len == 0 or segment in [".", ".."]: return false
  true

proc parseElement(node: XmlNode, archive: ZipArchive,
    depth = 0): OpenRasterElement =
  if depth >= 64:
    raise newException(ValueError,
      "OpenRaster layer stack exceeds the maximum nesting depth")
  case node.tag
  of "stack":
    result = commonElement(node, orekStack)
    result.isolation = node.attr("isolation")
    if result.isolation.len == 0: result.isolation = "isolate"
    if result.isolation notin ["isolate", "auto"]:
      raise newException(ValueError, "OpenRaster stack isolation is invalid")
    for child in node:
      if child.kind != xnElement: continue
      if child.tag notin ["stack", "layer"]:
        raise newException(ValueError,
          "unsupported OpenRaster stack element: " & child.tag)
      result.children.add parseElement(child, archive, depth + 1)
    if result.children.len == 0:
      raise newException(ValueError, "OpenRaster stack is empty")
  of "layer":
    result = commonElement(node, orekLayer)
    result.sourcePath = node.attr("src")
    if not safeRelativePath(result.sourcePath):
      raise newException(ValueError, "unsafe OpenRaster layer source path")
    if result.sourcePath in ["mimetype", "stack.xml", "mergedimage.png",
        "Thumbnails/thumbnail.png"]:
      raise newException(ValueError,
        "OpenRaster layer references a reserved package member")
    let entry = archive.entryNamed(result.sourcePath)
    if entry.isNil:
      raise newException(ValueError,
        "OpenRaster layer source is missing: " & result.sourcePath)
    result.sourceData = entry[].data
    if result.sourcePath.toLowerAscii.endsWith(".png"):
      result.image = parsePng(entry[].data)
      result.pngSource = true
    let selected = node.attr("selected")
    if selected.len > 0 and selected notin ["true", "false"]:
      raise newException(ValueError, "OpenRaster selected state is invalid")
    result.selected = selected == "true"
  else:
    raise newException(ValueError,
      "unsupported OpenRaster layer-stack element: " & node.tag)

proc hasOpenRasterMimeMarker*(archive: ZipArchive): bool =
  let marker = archive.entryNamed("mimetype")
  not marker.isNil and marker[].localHeaderOffset == 0 and
    marker[].compressionMethod == 0 and
    marker[].data.bytesText == OpenRasterMimeType

proc parseOpenRaster*(archive: ZipArchive): OpenRasterDocument =
  if not archive.hasOpenRasterMimeMarker:
    raise newException(ValueError, "invalid OpenRaster MIME marker")
  for entry in archive.entries:
    if validateUtf8(entry.name) != -1:
      raise newException(ValueError, "invalid OpenRaster member name")
    var nonAscii = false
    for character in entry.name:
      if ord(character) >= 0x80: nonAscii = true
    if nonAscii and not entry.utf8Name:
      raise newException(ValueError,
        "non-ASCII OpenRaster member name lacks the ZIP UTF-8 flag")

  let stackEntry = archive.entryNamed("stack.xml")
  let mergedEntry = archive.entryNamed("mergedimage.png")
  let thumbnailEntry = archive.entryNamed("Thumbnails/thumbnail.png")
  if stackEntry.isNil or mergedEntry.isNil or thumbnailEntry.isNil:
    raise newException(ValueError, "OpenRaster package is missing a required file")

  var root: XmlNode
  try:
    root = parseXml(stackEntry[].data.bytesText, {})
  except CatchableError as error:
    raise newException(ValueError, "invalid OpenRaster stack.xml: " & error.msg)
  if root.kind != xnElement or root.tag != "image":
    raise newException(ValueError, "OpenRaster XML root element is not image")
  result.version = root.attr("version")
  result.name = root.attr("name")
  result.width = root.integerAttribute("w", true)
  result.height = root.integerAttribute("h", true)
  result.xResolution = root.integerAttribute("xres")
  result.yResolution = root.integerAttribute("yres")
  if result.version.len == 0 or result.width <= 0 or result.height <= 0 or
      result.xResolution < 0 or result.yResolution < 0:
    raise newException(ValueError, "OpenRaster image metadata is invalid")

  var stacks = 0
  for child in root:
    if child.kind != xnElement: continue
    if child.tag != "stack":
      raise newException(ValueError,
        "unsupported OpenRaster image element: " & child.tag)
    inc stacks
    result.stack = parseElement(child, archive)
  if stacks != 1:
    raise newException(ValueError, "OpenRaster image must contain one root stack")

  result.mergedImage = parsePng(mergedEntry[].data)
  result.thumbnail = parsePng(thumbnailEntry[].data)
  if result.mergedImage.width != result.width or
      result.mergedImage.height != result.height:
    raise newException(ValueError,
      "OpenRaster merged image dimensions do not match the canvas")
  if result.mergedImage.bitDepth notin [8, 16]:
    raise newException(ValueError,
      "OpenRaster merged image must use 8 or 16 bits per channel")
  if result.thumbnail.width > 256 or result.thumbnail.height > 256 or
      result.thumbnail.width > result.width or
      result.thumbnail.height > result.height or
      result.thumbnail.bitDepth != 8 or result.thumbnail.interlaceMethod != 0:
    raise newException(ValueError, "OpenRaster thumbnail is invalid")
