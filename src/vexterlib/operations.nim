## High-level inspection and export operations shared by every frontend.

import ./artifacts
import ./archetypes/raster
import ./detection
import ./exporters/[gif, png]
import ./resource_tree
import ./containers/[amiga_anim, amiga_iff, amiga_ilbm, amos_bank, amos_bank_set, amos_packed_picture, amos_program,
  amos_sprite_icon_bank,
  zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
import ./metadata
import ./resources/[amiga_anim_image, amiga_ilbm_image, amos_listing, amos_packed_picture_image, amos_planar_image, zx_spectrum_basic,
  zx_spectrum_screen]

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
  of AmigaAnimTypeId:
    discard parseAmigaAnim(data)
  of AmigaIlbmTypeId:
    discard parseAmigaIlbm(data)
  of AmigaIffTypeId:
    discard parseAmigaIff(data)
  of AmosProgramTypeId:
    discard parseAmosProgram(data)
  of AmosBankSetTypeId:
    discard parseAmosBankSet(data)
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

proc amosGenericNode(path: string, bank: AmosBank): VextResourceNode =
  VextResourceNode(
    path: path,
    typeId: AmosBankResourceTypeId,
    kind: vrnkOpaque,
    metadata: @[
      integerMetadata("bank.number", bank.number),
      integerMetadata("bank.flags", bank.flags),
      stringMetadata("bank.type", bank.bankType),
      integerMetadata("data.length", bank.dataLength)
    ])

proc amosBankNode(path: string, bank: AmosBank): VextResourceNode =
  if bank.bankType != AmosPackedPictureBankType:
    return amosGenericNode(path, bank)
  let picture = parseAmosPackedPicture(bank.data)
  let pictureMetadata = @[
    integerMetadata("bank.number", bank.number),
    integerMetadata("bank.flags", bank.flags),
    stringMetadata("bank.type", bank.bankType),
    integerMetadata("position.x", picture.xOffsetBytes * 8),
    integerMetadata("position.y", picture.yOffset),
    integerMetadata("planes", picture.planes)
  ]
  if not picture.hasScreenHeader or picture.planes > 5:
    return VextResourceNode(
      path: path,
      typeId: AmosPackedPictureResourceTypeId,
      kind: vrnkOpaque,
      metadata: pictureMetadata)
  VextResourceNode(
    path: path,
    typeId: AmosPackedPictureResourceTypeId,
    kind: vrnkRaster,
    raster: VextRaster(kind: vrkIndexedImage,
      image: decodeAmosPackedPicture(picture)),
    metadata: pictureMetadata)

proc amosSpriteIconGroup(groupPath, resourceBase: string,
    bank: AmosSpriteIconBank): VextResourceNode =
  let resourceTypeId =
    if bank.kind == asibkSprite: AmosSpriteResourceTypeId
    else: AmosIconResourceTypeId
  result = VextResourceNode(
    path: groupPath,
    typeId: bank.amosSpriteIconBankTypeId,
    kind: vrnkGroup)
  for index, image in bank.images:
    result.children.add amosRasterNode(
      resourceBase & "/" & $index, resourceTypeId, image, bank.palette)

proc amosBankSetGroup(bankSet: AmosBankSet): VextResourceNode =
  result = VextResourceNode(
    path: "/banks", typeId: AmosBankSetTypeId, kind: vrnkGroup)
  for index, entry in bankSet.banks:
    let bankPath = "/banks/" & $index
    case entry.kind
    of absekGeneric:
      result.children.add amosBankNode(bankPath, entry.genericBank)
    of absekSprite, absekIcon:
      let resourceName =
        if entry.kind == absekSprite: "sprite" else: "icon"
      result.children.add amosSpriteIconGroup(bankPath,
        bankPath & "/" & resourceName, entry.spriteIconBank)

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
  of AmigaAnimTypeId:
    let anim = parseAmigaAnim(data)
    result.resources.roots.add VextResourceNode(
      path: AmigaAnimResourcePath,
      typeId: AmigaAnimTypeId,
      kind: vrnkRaster,
      raster: decodeAmigaAnim(anim),
      metadata: @[
        integerMetadata("frames", anim.frames.len + 1),
        integerMetadata("planes", anim.initial.image.header.planes),
        integerMetadata("camg", int(anim.initial.image.camg))
      ])
  of AmigaIlbmTypeId:
    let ilbm = parseAmigaIlbm(data)
    result.resources.roots.add VextResourceNode(
      path: AmigaIlbmImageResourcePath,
      typeId: AmigaIlbmImageTypeId,
      kind: vrnkRaster,
      raster: decodeAmigaIlbmRaster(ilbm.image),
      metadata: @[
        integerMetadata("planes", ilbm.image.header.planes),
        integerMetadata("position.x", ilbm.image.header.x),
        integerMetadata("position.y", ilbm.image.header.y),
        integerMetadata("aspect.x", ilbm.image.header.xAspect),
        integerMetadata("aspect.y", ilbm.image.header.yAspect),
        integerMetadata("camg", int(ilbm.image.camg))
      ])
  of AmigaIffTypeId:
    let form = parseAmigaIff(data)
    let group = VextResourceNode(
      path: "/chunks", typeId: AmigaIffTypeId, kind: vrnkGroup,
      metadata: @[stringMetadata("form.type", form.formType)])
    for index, chunk in form.chunks:
      group.children.add VextResourceNode(
        path: "/chunks/" & $index,
        typeId: "amiga.iff-chunk",
        kind: vrnkOpaque,
        metadata: @[
          stringMetadata("chunk.id", chunk.id),
          integerMetadata("data.length", chunk.data.len)
        ])
    result.resources.roots.add group
  of AmosProgramTypeId:
    let program = parseAmosProgram(data)
    result.resources.roots.add VextResourceNode(
      path: "/listing",
      typeId: AmosListingResourceTypeId,
      kind: vrnkText,
      text: decodeAmosListing(program.listingData),
      metadata: @[
        stringMetadata("amos.header", program.header),
        integerMetadata("data.length", program.listingLength)
      ])
    result.resources.roots.add amosBankSetGroup(program.bankSet)
  of AmosBankSetTypeId:
    let bankSet = parseAmosBankSet(data)
    result.resources.roots.add amosBankSetGroup(bankSet)
  of AmosBankTypeId:
    let bank = parseAmosBank(data)
    let path = if bank.bankType == AmosPackedPictureBankType:
      AmosPackedPictureResourcePath else: "/bank"
    result.resources.roots.add amosBankNode(path, bank)
  of AmosSpriteBankTypeId, AmosIconBankTypeId:
    let bank = parseAmosSpriteIconBank(data)
    let resourceName = if bank.kind == asibkSprite: "sprite" else: "icon"
    result.resources.roots.add amosSpriteIconGroup(
      "/" & resourceName, "/" & resourceName, bank)
  of ZxSpectrumScreenDumpTypeId:
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      extractZxSpectrumScreenDump(data))
  of ZxSpectrumSnapshotTypeId:
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      extractZxSpectrumSnapshotScreen(data))
    if data.len == ZxSpectrumSnapshot48Size:
      try:
        result.resources.roots.add VextResourceNode(
          path: ZxSpectrumBasicResourcePath,
          typeId: ZxSpectrumBasicTypeId,
          kind: vrnkText,
          text: extractZxSpectrumSnapshotBasic(data))
      except ValueError:
        discard
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
    let listings = parseZxSpectrumTapBasic(data)
    if listings.len == 1:
      result.resources.roots.add VextResourceNode(
        path: ZxSpectrumBasicResourcePath,
        typeId: ZxSpectrumBasicTypeId,
        kind: vrnkText,
        text: decodeZxSpectrumBasic(listings[0].data))
    elif listings.len > 1:
      let group = VextResourceNode(
        path: ZxSpectrumBasicResourcePath,
        kind: vrnkGroup)
      for index, listing in listings:
        group.children.add VextResourceNode(
          path: ZxSpectrumBasicResourcePath & "/" & $(index + 1),
          typeId: ZxSpectrumBasicTypeId,
          kind: vrnkText,
          text: decodeZxSpectrumBasic(listing.data))
      result.resources.roots.add group
  else:
    discard

proc exportResource*(tree: VextResourceTree,
    request: VextExportRequest): VextExportResult =
  var available: seq[VextResourceNode]
  for item in tree.leafResources:
    if item.kind in {vrnkRaster, vrnkText}:
      available.add item
  var resource: VextResourceNode
  if request.resourcePath.len > 0:
    for item in available:
      if item.path == request.resourcePath:
        resource = item
        break
    if resource.isNil:
      for item in tree.leafResources:
        if item.path == request.resourcePath:
          raise newException(ValueError,
            "resource is not exportable: " & request.resourcePath)
      raise newException(ValueError, "resource was not found: " &
        request.resourcePath)
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
    result.outputFormat = case resource.kind
      of vrnkText: "txt"
      of vrnkRaster:
        case resource.raster.kind
        of vrkIndexedAnimation: "gif"
        of vrkTrueColourAnimation: "apng"
        else: "png"
      else: ""
  case resource.kind
  of vrnkText:
    if result.outputFormat != "txt":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    var bytes = newSeq[byte](resource.text.len)
    for index, value in resource.text:
      bytes[index] = byte(value)
    result.artifacts.artifacts.add VextArtifact(
      suggestedFilename: request.suggestedName & ".txt",
      mediaType: "text/plain; charset=utf-8",
      data: bytes)
  of vrnkRaster:
    result.artifacts = case result.outputFormat
      of "png":
        case resource.raster.kind
        of vrkTrueColourImage:
          exportPng(resource.raster.trueColourImage,
            request.suggestedName & ".png")
        of vrkTrueColourAnimation:
          raise newException(ValueError,
            "use APNG to export a true-colour animation")
        else:
          exportPng(resource.raster.naturalImage,
            request.suggestedName & ".png")
      of "gif":
        if resource.raster.kind in {vrkTrueColourImage,
            vrkTrueColourAnimation}:
          raise newException(ValueError,
            "GIF export requires indexed colour; quantization is not implemented")
        exportGif(resource.raster.asIndexedAnimation,
          request.suggestedName & ".gif")
      of "apng":
        if resource.raster.kind != vrkTrueColourAnimation:
          raise newException(ValueError,
            "APNG export requires a true-colour animation")
        exportApng(resource.raster.trueColourAnimation,
          request.suggestedName & ".png")
      else:
        raise newException(ValueError,
          "unsupported output format: " & result.outputFormat)
  else:
    raise newException(ValueError, "resource is not exportable: " &
      resource.path)
