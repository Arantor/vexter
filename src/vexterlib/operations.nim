## High-level inspection and export operations shared by every frontend.

import ./artifacts
import ./archetypes/raster
import ./detection
import ./exporters/[gif, png]
import ./resource_tree
import ./containers/[zx_spectrum_screen_dump, zx_spectrum_snapshot,
  zx_spectrum_tap]
import ./resources/zx_spectrum_screen

type
  VextInspection* = object
    selectedFormat*: VextDetectionCandidate
    candidates*: seq[VextDetectionCandidate]
    resources*: VextResourceTree

  VextExportRequest* = object
    resourcePath*: string
    outputFormat*: string
    suggestedName*: string

  VextExportResult* = object
    resourcePath*: string
    outputFormat*: string
    artifacts*: VextArtifactSet

proc forcedCandidate(typeId: string, data: openArray[byte]):
    VextDetectionCandidate =
  case typeId
  of ZxSpectrumScreenDumpTypeId:
    if not isZxSpectrumScreenDump(data):
      raise newException(ValueError,
        "ZX Spectrum screen dump must contain exactly 6912 bytes")
  of ZxSpectrumSnapshotTypeId:
    if not isZxSpectrumSnapshotSize(data.len):
      raise newException(ValueError,
        "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
  of ZxSpectrumTapTypeId:
    if not isZxSpectrumTap(data):
      raise newException(ValueError, "invalid ZX Spectrum TAP container")
  else:
    raise newException(ValueError, "unsupported input format: " & typeId)
  VextDetectionCandidate(
    typeId: typeId,
    confidence: vdcProbable,
    evidence: @[VextDetectionEvidence(
      description: "format selected by the caller")])

proc rasterNode(path: string, data: openArray[byte]): VextResourceNode =
  VextResourceNode(
    path: path,
    typeId: ZxSpectrumScreenTypeId,
    kind: vrnkRaster,
    raster: decodeZxSpectrumScreen(data))

proc inspectSource*(filename: string, data: openArray[byte],
    inputFormat = ""): VextInspection =
  result.candidates = detectFormats(filename, data)
  if inputFormat.len > 0:
    result.selectedFormat = forcedCandidate(inputFormat, data)
  else:
    if result.candidates.len == 0:
      raise newException(ValueError, "input format was not recognized")
    result.selectedFormat = result.candidates[0]

  case result.selectedFormat.typeId
  of ZxSpectrumScreenDumpTypeId:
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      extractZxSpectrumScreenDump(data))
  of ZxSpectrumSnapshotTypeId:
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      extractZxSpectrumSnapshotScreen(data))
  of ZxSpectrumTapTypeId:
    let screens = parseZxSpectrumTapScreens(data)
    if screens.len == 1:
      result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
        screens[0].data)
    elif screens.len > 1:
      let group = VextResourceNode(
        path: ZxSpectrumScreenResourcePath,
        kind: vrnkGroup)
      for index, screen in screens:
        group.children.add rasterNode(
          ZxSpectrumScreenResourcePath & "/" & $(index + 1), screen.data)
      result.resources.roots.add group
  else:
    discard

proc exportResource*(tree: VextResourceTree,
    request: VextExportRequest): VextExportResult =
  let available = tree.rasterResources
  var resource: VextResourceNode
  if request.resourcePath.len > 0:
    resource = tree.findRasterResource(request.resourcePath)
    if resource.isNil:
      raise newException(ValueError,
        "resource was not found: " & request.resourcePath)
  else:
    if available.len == 0:
      raise newException(ValueError, "container exposes no screen resources")
    if available.len > 1:
      raise newException(ValueError,
        "more than one screen resource is available; select one")
    resource = available[0]

  result.resourcePath = resource.path
  result.outputFormat = request.outputFormat
  if result.outputFormat.len == 0:
    result.outputFormat =
      if resource.raster.kind == vrkIndexedAnimation: "gif" else: "png"
  result.artifacts = case result.outputFormat
    of "png": exportPng(resource.raster.naturalImage,
      request.suggestedName & ".png")
    of "gif": exportGif(resource.raster.asIndexedAnimation,
      request.suggestedName & ".gif")
    else:
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
