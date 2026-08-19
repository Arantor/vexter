## High-level inspection and export operations shared by every frontend.

import ./artifacts
import ./archetypes/raster
import ./archetypes/audio
import ./detection
import ./exporters/[gif, png, wav]
import ./resource_tree
import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_dms, amiga_iff, amiga_ilbm, amiga_workbench_icon, amos_bank, amos_bank_set, amos_packed_picture, amos_program,
  amos_sprite_icon_bank, bmp, gif_container, pcx, png_container,
  zip_archive, zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
import ./metadata
import ./resources/[amiga_anim_image, amiga_ilbm_image, amiga_workbench_icon_image, amos_listing, amos_packed_picture_image, amos_planar_image, bmp_image, gif_image, png_image, zx_spectrum_basic,
  pcx_image, zx_spectrum_screen]

type
  VextInspectionWarning* = object
    path*: string
    format*: string
    message*: string

  VextInspection* = object
    selectedFormat*: VextDetectionCandidate
    candidates*: seq[VextDetectionCandidate]
    resources*: VextResourceTree
    warnings*: seq[VextInspectionWarning]

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
  of AmigaWorkbenchIconTypeId:
    discard parseWorkbenchIcon(data)
  of AmigaAcbmTypeId:
    discard parseAmigaAcbm(data)
  of Amiga8svxTypeId:
    discard parseAmiga8svx(data)
  of Amiga16svTypeId:
    discard parseAmiga16sv(data)
  of AmigaAdfTypeId:
    discard parseAmigaAdf(data)
  of AmigaDmsTypeId:
    discard parseAmigaDms(data)
  of AmigaAnimTypeId:
    discard parseAmigaAnim(data)
  of AmigaIlbmTypeId:
    discard parseAmigaIlbm(data)
  of AmigaIffTypeId:
    discard parseAmigaIff(data)
  of BmpTypeId:
    discard parseBmp(data)
  of DibTypeId:
    discard parseDib(data)
  of PngTypeId:
    discard parsePng(data)
  of GifTypeId:
    discard parseGif(data)
  of PcxTypeId:
    discard parsePcx(data)
  of ZipArchiveTypeId:
    discard parseZipArchive(data)
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

proc inspectSourceDepth(filename: string, data: openArray[byte],
    inputFormat: string, depth: int, ignoreWarnings: bool,
    pcxChannelOrder: PcxChannelOrder): VextInspection

proc rebaseNode(node: VextResourceNode, prefix: string) =
  node.path = prefix & node.path
  for child in node.children:
    rebaseNode(child, prefix)

proc containedFileNode(path, filename, fallbackType: string,
    data: openArray[byte], metadata: seq[VextMetadataEntry], depth: int,
    ignoreWarnings: bool, pcxChannelOrder: PcxChannelOrder,
    warnings: var seq[VextInspectionWarning]): VextResourceNode =
  var retainedMetadata = metadata
  if depth >= 8:
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, metadata: retainedMetadata)
  let candidates = detectFormats(filename, data)
  if candidates.len == 0:
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, metadata: retainedMetadata)
  var nested: VextInspection
  try:
    nested = inspectSourceDepth(filename, data, "", depth + 1, ignoreWarnings,
      pcxChannelOrder)
  except ValueError as error:
    if ignoreWarnings:
      warnings.add VextInspectionWarning(
        path: path, format: candidates[0].typeId, message: error.msg)
      retainedMetadata.add stringMetadata("decode.format", candidates[0].typeId)
      retainedMetadata.add stringMetadata("decode.warning", error.msg)
      return VextResourceNode(path: path, typeId: fallbackType,
        kind: vrnkOpaque, data: @data, metadata: retainedMetadata)
    raise newException(ValueError,
      "while inspecting nested resource " & path & ": " & error.msg)
  for warning in nested.warnings:
    warnings.add VextInspectionWarning(path: path & warning.path,
      format: warning.format, message: warning.message)
  result = VextResourceNode(path: path, typeId: nested.selectedFormat.typeId,
    kind: vrnkGroup, data: @data, metadata: retainedMetadata)
  for root in nested.resources.roots:
    rebaseNode(root, path)
    result.children.add root

proc adfEntryNode(entry: AmigaAdfEntry, parentPath: string,
    depth: int, ignoreWarnings: bool, pcxChannelOrder: PcxChannelOrder,
    warnings: var seq[VextInspectionWarning]): VextResourceNode =
  let path = parentPath & "/" & entry.name
  let commonMetadata = @[
    integerMetadata("adf.block", entry.sector),
    stringMetadata("adf.name", entry.name),
    stringMetadata("adf.comment", entry.comment)
  ]
  case entry.kind
  of aaekDirectory:
    result = VextResourceNode(
      path: path, typeId: AmigaAdfDirectoryTypeId, kind: vrnkGroup,
      metadata: commonMetadata)
    for child in entry.children:
      result.children.add adfEntryNode(child, path, depth, ignoreWarnings,
        pcxChannelOrder, warnings)
  of aaekLink:
    result = VextResourceNode(
      path: path, typeId: AmigaAdfLinkTypeId, kind: vrnkOpaque,
      metadata: commonMetadata)
  of aaekFile:
    var metadata = commonMetadata
    metadata.add integerMetadata("data.length", entry.size)
    result = containedFileNode(path, entry.name, AmigaAdfFileTypeId,
      entry.data, metadata, depth, ignoreWarnings, pcxChannelOrder, warnings)

proc childNamed(parent: VextResourceNode, path: string): VextResourceNode =
  for child in parent.children:
    if child.path == path:
      return child

proc addZipEntry(root: VextResourceNode, entry: ZipEntry, depth: int,
    ignoreWarnings: bool, pcxChannelOrder: PcxChannelOrder,
    warnings: var seq[VextInspectionWarning]) =
  var parent = root
  var path = root.path
  for index, segment in entry.segments:
    path.add "/" & segment
    let last = index == entry.segments.high
    var existing = childNamed(parent, path)
    if last and not entry.isDirectory:
      if not existing.isNil:
        raise newException(ValueError, "conflicting ZIP entry path: " & entry.name)
      let metadata = @[
        stringMetadata("zip.name", entry.name),
        integerMetadata("compression.method", entry.compressionMethod),
        integerMetadata("compressed.length", entry.compressedSize),
        integerMetadata("data.length", entry.uncompressedSize)]
      parent.children.add containedFileNode(path, segment, ZipFileTypeId,
        entry.data, metadata, depth, ignoreWarnings, pcxChannelOrder, warnings)
    else:
      if existing.isNil:
        existing = VextResourceNode(path: path, typeId: ZipDirectoryTypeId,
          kind: vrnkGroup)
        parent.children.add existing
      elif existing.kind != vrnkGroup or existing.typeId != ZipDirectoryTypeId:
        raise newException(ValueError, "conflicting ZIP entry path: " & entry.name)
      parent = existing

proc inspectSourceDepth(filename: string, data: openArray[byte],
    inputFormat: string, depth: int, ignoreWarnings: bool,
    pcxChannelOrder: PcxChannelOrder): VextInspection =
  result.candidates = detectFormats(filename, data)
  if inputFormat.len > 0:
    result.selectedFormat = forcedCandidate(inputFormat, data)
  else:
    if result.candidates.len == 0:
      raise newException(ValueError, "input format was not recognized")
    result.selectedFormat = result.candidates[0]

  case result.selectedFormat.typeId
  of AmigaWorkbenchIconTypeId:
    let icon = parseWorkbenchIcon(data)
    var metadata = @[
      integerMetadata("workbench.version", icon.version),
      integerMetadata("workbench.type", icon.iconType),
      integerMetadata("position.x", icon.currentX),
      integerMetadata("position.y", icon.currentY),
      integerMetadata("stack-size", icon.stackSize),
      stringMetadata("default-tool", icon.defaultTool),
      stringMetadata("tool-window", icon.toolWindow),
      integerMetadata("tool-types", icon.toolTypes.len),
      integerMetadata("newicon.im1-records", icon.newIconToolTypes(1).len),
      integerMetadata("newicon.im2-records", icon.newIconToolTypes(2).len)]
    for index, value in icon.toolTypes:
      metadata.add stringMetadata("tool-type." & $index, value)
    let group = VextResourceNode(path: "/icon",
      typeId: AmigaWorkbenchIconTypeId, kind: vrnkGroup, metadata: metadata)
    if icon.hasNormalImage:
      group.children.add VextResourceNode(path: "/icon/unselected",
        typeId: AmigaWorkbenchClassicImageTypeId, kind: vrnkRaster,
        raster: VextRaster(kind: vrkIndexedImage,
          image: decodeWorkbenchIconImage(icon.normalImage)),
        defaultExportPriority: 10)
    if icon.hasSelectedImage:
      group.children.add VextResourceNode(path: "/icon/selected",
        typeId: AmigaWorkbenchClassicImageTypeId, kind: vrnkRaster,
        raster: VextRaster(kind: vrkIndexedImage,
          image: decodeWorkbenchIconImage(icon.selectedImage)))
    let newIconGroup = VextResourceNode(path: "/newicon",
      typeId: AmigaWorkbenchIconTypeId, kind: vrnkGroup)
    for state in 1 .. 2:
      if icon.newIconToolTypes(state).len > 0:
        let image = parseNewIcon(icon, state)
        newIconGroup.children.add VextResourceNode(
          path: if state == 1: "/newicon/unselected" else: "/newicon/selected",
          typeId: AmigaWorkbenchNewIconImageTypeId, kind: vrnkRaster,
          raster: VextRaster(kind: vrkIndexedImage,
            image: decodeWorkbenchEnhancedImage(image)),
          defaultExportPriority: if state == 1: 20 else: 0)
    if newIconGroup.children.len > 0: result.resources.roots.add newIconGroup
    let glow = parseGlowIcon(data)
    if glow.images.len > 0:
      let glowGroup = VextResourceNode(path: "/glowicon",
        typeId: AmigaWorkbenchIconTypeId, kind: vrnkGroup, metadata: @[
          integerMetadata("frameless", int(glow.frameless)),
          integerMetadata("aspect.x", glow.aspectX),
          integerMetadata("aspect.y", glow.aspectY)])
      for index, image in glow.images:
        glowGroup.children.add VextResourceNode(
          path: if index == 0: "/glowicon/unselected" else: "/glowicon/selected",
          typeId: AmigaWorkbenchGlowIconImageTypeId, kind: vrnkRaster,
          raster: VextRaster(kind: vrkIndexedImage,
            image: decodeWorkbenchEnhancedImage(image)),
          defaultExportPriority: if index == 0: 30 else: 0)
      result.resources.roots.add glowGroup
    result.resources.roots.add group
  of GifTypeId:
    let source = parseGif(data)
    var metadata = @[
      stringMetadata("gif.version", source.version),
      integerMetadata("frames", source.frames.len),
      integerMetadata("background-index", source.backgroundIndex),
      integerMetadata("pixel-aspect-ratio", source.pixelAspectRatio),
      integerMetadata("extensions", source.extensions.len)]
    for index, extension in source.extensions:
      metadata.add integerMetadata("extension." & $index & ".label",
        extension.label)
      metadata.add integerMetadata("extension." & $index & ".length",
        extension.dataLength)
    result.resources.roots.add VextResourceNode(path: GifImageResourcePath,
      typeId: GifImageTypeId, kind: vrnkRaster, raster: decodeGif(source),
      metadata: metadata)
  of PngTypeId:
    let source = parsePng(data)
    var metadata = @[
      integerMetadata("bit-depth", source.bitDepth),
      integerMetadata("colour-type", source.colourType),
      integerMetadata("interlace-method", source.interlaceMethod),
      integerMetadata("chunks", source.chunks.len)]
    for index, chunk in source.chunks:
      metadata.add stringMetadata("chunk." & $index & ".type", chunk.kind)
      metadata.add integerMetadata("chunk." & $index & ".length", chunk.data.len)
    result.resources.roots.add VextResourceNode(path: PngImageResourcePath,
      typeId: PngImageTypeId, kind: vrnkRaster, raster: decodePngOrApng(source),
      metadata: metadata)
  of BmpTypeId, DibTypeId:
    let source = if result.selectedFormat.typeId == BmpTypeId:
      parseBmp(data) else: parseDib(data)
    result.resources.roots.add VextResourceNode(
      path: BmpImageResourcePath, typeId: BmpImageTypeId, kind: vrnkRaster,
      raster: decodeBmp(source), metadata: @[
        integerMetadata("bits-per-pixel", source.bitsPerPixel),
        integerMetadata("compression", source.compression),
        integerMetadata("colours-used", source.coloursUsed),
        integerMetadata("pixels-per-metre.x", source.xPixelsPerMetre),
        integerMetadata("pixels-per-metre.y", source.yPixelsPerMetre)])
  of PcxTypeId:
    let source = parsePcx(data)
    result.resources.roots.add VextResourceNode(
      path: PcxImageResourcePath, typeId: PcxImageTypeId, kind: vrnkRaster,
      raster: decodePcx(source, pcxChannelOrder), metadata: @[
        integerMetadata("bits-per-pixel", source.bitsPerPixel),
        integerMetadata("planes", source.planes),
        integerMetadata("position.x", source.xMin),
        integerMetadata("position.y", source.yMin),
        integerMetadata("dpi.x", source.horizontalDpi),
        integerMetadata("dpi.y", source.verticalDpi)])
  of ZipArchiveTypeId:
    let archive = parseZipArchive(data)
    let root = VextResourceNode(path: "/archive", typeId: ZipArchiveTypeId,
      kind: vrnkGroup, metadata: @[
        integerMetadata("entries", archive.entries.len),
        stringMetadata("comment", archive.comment)])
    for entry in archive.entries:
      addZipEntry(root, entry, depth, ignoreWarnings, pcxChannelOrder,
        result.warnings)
    result.resources.roots.add root
  of AmigaAdfTypeId:
    let volume = parseAmigaAdf(data)
    let disk = VextResourceNode(
      path: "/disk", typeId: AmigaAdfTypeId, kind: vrnkGroup,
      metadata: @[
        stringMetadata("volume.name", volume.name),
        stringMetadata("filesystem", volume.filesystem),
        integerMetadata("filesystem.flags", volume.flags),
        integerMetadata("root.block", volume.rootBlock)
      ])
    for entry in volume.entries:
      disk.children.add adfEntryNode(entry, "/disk", depth, ignoreWarnings,
        pcxChannelOrder, result.warnings)
    result.resources.roots.add disk
  of AmigaDmsTypeId:
    let archive = parseAmigaDms(data)
    if not archive.canUnpackAmigaDms:
      let tracks = VextResourceNode(
        path: "/tracks", typeId: AmigaDmsTypeId, kind: vrnkGroup,
        metadata: @[
          integerMetadata("dms.info-flags", int(archive.infoFlags)),
          integerMetadata("dms.low-track", archive.lowTrack),
          integerMetadata("dms.high-track", archive.highTrack),
          integerMetadata("dms.tracks", archive.tracks.len),
          integerMetadata("dms.packed-length", int(archive.packedSize)),
          integerMetadata("dms.unpacked-length", int(archive.unpackedSize)),
          integerMetadata("dms.compression", ord(archive.compression))
        ])
      for track in archive.tracks:
        tracks.children.add VextResourceNode(
          path: "/tracks/" & $track.number,
          typeId: AmigaDmsTrackTypeId,
          kind: vrnkOpaque,
          data: track.data,
          metadata: @[
            integerMetadata("track.number", track.number),
            integerMetadata("compression", ord(track.compression)),
            integerMetadata("flags", track.flags),
            integerMetadata("packed.length", track.packedLength),
            integerMetadata("runtime-packed.length", track.runtimePackedLength),
            integerMetadata("unpacked.length", track.unpackedLength),
            integerMetadata("unpacked.crc", int(track.unpackedCrc)),
            integerMetadata("packed.crc", int(track.packedCrc)),
            integerMetadata("header.crc", int(track.headerCrc))
          ])
      result.resources.roots.add tracks
      return
    let diskData = unpackAmigaDms(archive)
    let volume = parseAmigaAdf(diskData)
    let disk = VextResourceNode(
      path: "/disk", typeId: AmigaDmsTypeId, kind: vrnkGroup,
      data: diskData,
      metadata: @[
        stringMetadata("volume.name", volume.name),
        stringMetadata("filesystem", volume.filesystem),
        integerMetadata("filesystem.flags", volume.flags),
        integerMetadata("root.block", volume.rootBlock),
        integerMetadata("dms.info-flags", int(archive.infoFlags)),
        integerMetadata("dms.low-track", archive.lowTrack),
        integerMetadata("dms.high-track", archive.highTrack),
        integerMetadata("dms.tracks", archive.tracks.len),
        integerMetadata("dms.compression", ord(archive.compression))
      ])
    for entry in volume.entries:
      disk.children.add adfEntryNode(entry, "/disk", depth, ignoreWarnings,
        pcxChannelOrder, result.warnings)
    result.resources.roots.add disk
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
  of Amiga8svxTypeId:
    let source = parseAmiga8svx(data)
    let instrument = decodeAmiga8svx(source)
    result.resources.roots.add VextResourceNode(
      path: Amiga8svxResourcePath,
      typeId: Amiga8svxResourceTypeId,
      kind: vrnkAudio,
      instrument: instrument,
      metadata: @[
        integerMetadata("channels", instrument.sound.buffer.channels.len),
        integerMetadata("bits-per-sample", instrument.sound.buffer.bitsPerSample),
        integerMetadata("samples", instrument.sound.buffer.sampleCount),
        integerMetadata("sample-rate", instrument.sound.sampleRate),
        integerMetadata("one-shot-samples", instrument.oneShotSamples),
        integerMetadata("repeat-samples", instrument.repeatSamples),
        integerMetadata("samples-per-high-cycle", instrument.samplesPerHighCycle),
        integerMetadata("octaves", source.octaves),
        integerMetadata("compression", ord(source.compression)),
        integerMetadata("volume", int(source.volumeRaw)),
        integerMetadata("channel-mask", source.channelMask),
        stringMetadata("name", source.name),
        stringMetadata("annotation", source.annotation)
      ])
  of Amiga16svTypeId:
    let source = parseAmiga16sv(data)
    let instrument = decodeAmiga16sv(source)
    result.resources.roots.add VextResourceNode(
      path: Amiga16svResourcePath,
      typeId: Amiga16svResourceTypeId,
      kind: vrnkAudio,
      instrument: instrument,
      metadata: @[
        integerMetadata("channels", instrument.sound.buffer.channels.len),
        integerMetadata("bits-per-sample", instrument.sound.buffer.bitsPerSample),
        integerMetadata("samples", instrument.sound.buffer.sampleCount),
        integerMetadata("sample-rate", instrument.sound.sampleRate),
        integerMetadata("one-shot-samples", instrument.oneShotSamples),
        integerMetadata("repeat-samples", instrument.repeatSamples),
        integerMetadata("samples-per-high-cycle", instrument.samplesPerHighCycle),
        integerMetadata("octaves", source.octaves),
        integerMetadata("compression", source.compression),
        integerMetadata("volume", int(source.volumeRaw)),
        integerMetadata("channel-mask", source.channelMask),
        stringMetadata("name", source.name),
        stringMetadata("annotation", source.annotation),
        stringMetadata("author", source.author),
        stringMetadata("copyright", source.copyright),
        stringMetadata("version", source.version)
      ])
  of AmigaAcbmTypeId, AmigaIlbmTypeId:
    let image = if result.selectedFormat.typeId == AmigaAcbmTypeId:
      parseAmigaAcbm(data).image
    else:
      parseAmigaIlbm(data).image
    result.resources.roots.add VextResourceNode(
      path: AmigaIlbmImageResourcePath,
      typeId: AmigaIlbmImageTypeId,
      kind: vrnkRaster,
      raster: decodeAmigaIlbmRaster(image),
      metadata: @[
        integerMetadata("planes", image.header.planes),
        integerMetadata("position.x", image.header.x),
        integerMetadata("position.y", image.header.y),
        integerMetadata("aspect.x", image.header.xAspect),
        integerMetadata("aspect.y", image.header.yAspect),
        integerMetadata("camg", int(image.camg))
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

proc inspectSource*(filename: string, data: openArray[byte],
    inputFormat = "", ignoreWarnings = false,
    pcxChannelOrder = pcoRgb): VextInspection =
  inspectSourceDepth(filename, data, inputFormat, 0, ignoreWarnings,
    pcxChannelOrder)

proc exportResource*(tree: VextResourceTree,
    request: VextExportRequest): VextExportResult =
  var available: seq[VextResourceNode]
  for item in tree.leafResources:
    if item.kind in {vrnkRaster, vrnkText, vrnkAudio}:
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
      raise newException(ValueError, "container exposes no exportable resources")
    if available.len > 1:
      var bestPriority = low(int)
      var bestCount = 0
      for item in available:
        if item.defaultExportPriority > bestPriority:
          bestPriority = item.defaultExportPriority
          resource = item
          bestCount = 1
        elif item.defaultExportPriority == bestPriority:
          bestCount += 1
      if bestCount > 1:
        raise newException(ValueError,
          "more than one exportable resource is available; select one")
    else:
      resource = available[0]

  result.resourcePath = resource.path
  result.outputFormat = request.outputFormat
  if result.outputFormat.len == 0:
    result.outputFormat = case resource.kind
      of vrnkText: "txt"
      of vrnkAudio: "wav"
      of vrnkRaster:
        case resource.raster.kind
        of vrkIndexedAnimation:
          if resource.raster.animation.gifCompatible: "gif" else: "apng"
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
        case resource.raster.kind
        of vrkIndexedImage, vrkIndexedAnimation:
          exportApng(resource.raster.asIndexedAnimation,
            request.suggestedName & ".png")
        of vrkTrueColourAnimation:
          exportApng(resource.raster.trueColourAnimation,
            request.suggestedName & ".png")
        of vrkTrueColourImage:
          raise newException(ValueError,
            "APNG export requires an indexed raster or true-colour animation")
      else:
        raise newException(ValueError,
          "unsupported output format: " & result.outputFormat)
  of vrnkAudio:
    if result.outputFormat != "wav":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    result.artifacts = exportWav(resource.instrument.sound,
      request.suggestedName & ".wav")
  else:
    raise newException(ValueError, "resource is not exportable: " &
      resource.path)
