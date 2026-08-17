## High-level inspection and export operations shared by every frontend.

import ./artifacts
import ./archetypes/raster
import ./detection
import ./exporters/[gif, png]
import ./resource_tree
import ./containers/[amos_bank, amos_sprite_icon_bank,
  zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
import ./metadata
import ./resources/[amos_planar_image, zx_spectrum_screen]

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
  of AmosBankTypeId:
    discard parseAmosBank(data)
  of AmosSpriteBankTypeId, AmosIconBankTypeId:
    let bank = parseAmosSpriteIconBank(data)
    if bank.amosSpriteIconBankTypeId != typeId:
      raise newException(ValueError,
        "AMOS bank identifier does not match the selected format")
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

proc amosRasterNode(path, typeId: string, source: AmosPlanarImage,
    palette: openArray[VextRgb]): VextResourceNode =
  VextResourceNode(
    path: path,
    typeId: typeId,
    kind: vrnkRaster,
    raster: VextRaster(kind: vrkIndexedImage,
      image: decodeAmosPlanarImage(source, palette)),
    metadata: @[
      integerMetadata("hotspot.x", source.hotspotX),
      integerMetadata("hotspot.y", source.hotspotY)
    ])

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
  of AmosBankTypeId:
    let bank = parseAmosBank(data)
    result.resources.roots.add VextResourceNode(
      path: "/bank",
      typeId: AmosBankResourceTypeId,
      kind: vrnkOpaque,
      metadata: @[
        integerMetadata("bank.number", bank.number),
        integerMetadata("bank.flags", bank.flags),
        stringMetadata("bank.type", bank.bankType),
        integerMetadata("data.length", bank.dataLength)
      ])
  of AmosSpriteBankTypeId, AmosIconBankTypeId:
    let bank = parseAmosSpriteIconBank(data)
    let
      resourceName = if bank.kind == asibkSprite: "sprite" else: "icon"
      resourceTypeId =
        if bank.kind == asibkSprite: AmosSpriteResourceTypeId
        else: AmosIconResourceTypeId
      group = VextResourceNode(path: "/" & resourceName, kind: vrnkGroup)
    for index, image in bank.images:
      group.children.add amosRasterNode(
        "/" & resourceName & "/" & $index, resourceTypeId,
        image, bank.palette)
    result.resources.roots.add group
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
      raise newException(ValueError, "container exposes no raster resources")
    if available.len > 1:
      raise newException(ValueError,
        "more than one raster resource is available; select one")
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
