## High-level inspection and export operations shared by every frontend.

import std/strutils
import ./artifacts
import ./archetypes/raster
import ./archetypes/audio
import ./transformations/colour_cycle
import ./detection
import ./handler_registry
import ./exporters/[gif, png, raw, wav]
import ./resource_tree
import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_dms, amiga_iff, amiga_ilbm, amiga_pbm, amiga_workbench_icon, amos_bank, amos_bank_set, amos_packed_picture, amos_program,
  amos_sprite_icon_bank, bmp, flic, gif_container, netpbm, pcx, png_container,
  qoi, tga, wav, zip_archive, zx_spectrum_snapshot, zx_spectrum_tap]
import ./containers/xpk_shri
import ./containers/powerpacker
import ./metadata
import ./resources/[amiga_anim_image, amiga_ilbm_image, amiga_pbm_image, amiga_workbench_icon_image, amos_listing, amos_packed_picture_image, amos_planar_image, bmp_image, flic_animation, gif_image, netpbm_image, png_image, zx_spectrum_basic,
  pcx_image, qoi_image, tga_image, zx_spectrum_screen]

type
  VextOperationCancelledError* = object of CatchableError

  VextProgressPhase* = enum
    vppDetecting
    vppInspecting
    vppDecoding
    vppTraversing
    vppComplete

  VextProgressEvent* = object
    phase*: VextProgressPhase
    path*: string
    completed*: int
    total*: int
    message*: string

  VextProgressCallback* = proc(event: VextProgressEvent): bool {.closure.}

  VextExportFormat* = object
    id*: string
    displayName*: string
    extensions*: seq[string]
    mediaTypes*: seq[string]
    isDefault*: bool

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
    colourCycleFrameLimit*: int
    allowLargeAnimation*: bool

  VextExportResult* = object
    resourcePath*: string
    outputFormat*: string
    artifacts*: VextArtifactSet

  VextExportAllRequest* = object
    resourcePatterns*: seq[string]
    outputFormat*: string
    colourCycleFrameLimit*: int
    allowLargeAnimation*: bool

  VextExportAllResult* = object
    exports*: seq[VextExportResult]

proc reportProgress(callback: VextProgressCallback,
    phase: VextProgressPhase, path, message: string,
    completed = 0, total = 0) =
  if callback != nil and not callback(VextProgressEvent(phase: phase,
      path: path, completed: completed, total: total, message: message)):
    raise newException(VextOperationCancelledError, "operation cancelled")

proc exportFormatsFor*(resource: VextResourceNode): seq[VextExportFormat] =
  ## Describes every format accepted by `exportResource` for one resource.
  ## The order is suitable for presentation by frontends.
  if resource.isNil:
    return
  case resource.kind
  of vrnkRaster:
    case resource.raster.kind
    of vrkIndexedImage:
      result = @[
        VextExportFormat(id: "png", displayName: "PNG image",
          extensions: @["png"], mediaTypes: @["image/png"], isDefault: true),
        VextExportFormat(id: "gif", displayName: "GIF image",
          extensions: @["gif"], mediaTypes: @["image/gif"])]
      if resource.raster.image.colourCycles.len > 0:
        result.add VextExportFormat(id: "gif-cycled",
          displayName: "Animated GIF with colour cycling",
          extensions: @["gif"], mediaTypes: @["image/gif"])
        result.add VextExportFormat(id: "apng-cycled",
          displayName: "Animated PNG with colour cycling",
          extensions: @["png"], mediaTypes: @["image/apng"])
    of vrkIndexedAnimation:
      let gifDefault = resource.raster.animation.gifCompatible
      result = @[
        VextExportFormat(id: "png", displayName: "PNG first frame",
          extensions: @["png"], mediaTypes: @["image/png"]),
        VextExportFormat(id: "gif", displayName: "Animated GIF (original)",
          extensions: @["gif"], mediaTypes: @["image/gif"],
          isDefault: gifDefault),
        VextExportFormat(id: "apng", displayName: "Animated PNG (original)",
          extensions: @["png"], mediaTypes: @["image/apng"],
          isDefault: not gifDefault)]
      if resource.raster.animation.colourCycles.len > 0:
        result.add VextExportFormat(id: "gif-cycled",
          displayName: "Animated GIF with colour cycling",
          extensions: @["gif"], mediaTypes: @["image/gif"])
        result.add VextExportFormat(id: "apng-cycled",
          displayName: "Animated PNG with colour cycling",
          extensions: @["png"], mediaTypes: @["image/apng"])
    of vrkTrueColourImage:
      result = @[VextExportFormat(id: "png", displayName: "PNG image",
        extensions: @["png"], mediaTypes: @["image/png"], isDefault: true)]
    of vrkTrueColourAnimation:
      result = @[VextExportFormat(id: "apng", displayName: "Animated PNG",
        extensions: @["png"], mediaTypes: @["image/apng"], isDefault: true)]
  of vrnkAudio:
    result = @[VextExportFormat(id: "wav", displayName: "WAVE audio",
      extensions: @["wav"], mediaTypes: @["audio/wav"], isDefault: true)]
  of vrnkText:
    result = @[VextExportFormat(id: "txt", displayName: "Plain text",
      extensions: @["txt"], mediaTypes: @["text/plain"], isDefault: true)]
  of vrnkOpaque:
    if resource.rawDataAvailable:
      result = @[VextExportFormat(id: "bin", displayName: "Raw binary",
        extensions: @["bin"], mediaTypes: @["application/octet-stream"],
        isDefault: true)]
  of vrnkGroup:
    discard

proc defaultExportFormat*(resource: VextResourceNode): string =
  for format in resource.exportFormatsFor:
    if format.isDefault:
      return format.id

const WindowsDeviceNames = [
  "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5",
  "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4",
  "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]

proc normalizedExportSegment(segment: string): string =
  for value in segment:
    if ord(value) < 32 or value in {'<', '>', ':', '"', '/', '\\', '|', '?', '*'}:
      result.add '_'
    else:
      result.add value
  result = result.strip(chars = {' ', '.'}, trailing = true)
  if result.len == 0:
    result = "_"
  let stem = result.split('.', maxsplit = 1)[0].toLowerAscii
  if stem in WindowsDeviceNames:
    result = "_" & result

proc exportNameForPath(path: string): string =
  for segment in path.split('/'):
    if segment.len > 0:
      if result.len > 0:
        result.add '/'
      result.add normalizedExportSegment(segment)

proc validateResourcePattern(pattern: string): seq[string] =
  if pattern.len < 2 or pattern[0] != '/':
    raise newException(ValueError,
      "resource pattern must be an absolute resource path: " & pattern)
  result = pattern[1 .. ^1].split('/')
  for segment in result:
    if segment.len == 0 or segment in [".", ".."] or
        ('*' in segment and segment != "*"):
      raise newException(ValueError, "unsupported resource pattern: " & pattern)

proc resourcePatternMatches(path: string, pattern: seq[string]): bool =
  let segments = path[1 .. ^1].split('/')
  if segments.len != pattern.len:
    return false
  for index, segment in pattern:
    if segment != "*" and segment != segments[index]:
      return false
  true

proc uniqueArtifactName(name: string, used: var seq[string]): string =
  result = name
  var suffix = 2
  var collision = true
  while collision:
    collision = false
    for existing in used:
      if existing.toLowerAscii == result.toLowerAscii:
        collision = true
        break
    if not collision:
      break
    let slash = name.rfind('/')
    let dot = name.rfind('.')
    let extensionAt = if dot > slash: dot else: name.len
    result = name[0 ..< extensionAt] & "-" & $suffix & name[extensionAt .. ^1]
    inc suffix
  used.add result

proc forcedFormat(typeId: string, data: openArray[byte]): VextDetectedFormat =
  let handler = formatHandler(typeId)
  if handler.isNil:
    raise newException(ValueError, "unsupported input format: " & typeId)
  result.parsed = handler[].parse(data)
  result.candidate = VextDetectionCandidate(typeId: typeId,
    confidence: vdcProbable, evidence: @[VextDetectionEvidence(
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
    data: bank.data,
    rawDataAvailable: true,
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
      data: bank.data,
      rawDataAvailable: true,
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
      kind: vrnkOpaque, data: @data, rawDataAvailable: true,
      metadata: retainedMetadata)
  let candidates = detectFormats(filename, data)
  if candidates.len == 0:
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, rawDataAvailable: true,
      metadata: retainedMetadata)
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
        kind: vrnkOpaque, data: @data, rawDataAvailable: true,
        metadata: retainedMetadata)
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
  let detected = detectParsedFormats(filename, data)
  for item in detected:
    result.candidates.add item.candidate
  var selectedParsed: VextParsedContainer
  if inputFormat.len > 0:
    let forced = forcedFormat(inputFormat, data)
    result.selectedFormat = forced.candidate
    selectedParsed = forced.parsed
  else:
    if result.candidates.len == 0:
      raise newException(ValueError, "input format was not recognized")
    result.selectedFormat = result.candidates[0]
    selectedParsed = detected[0].parsed

  let selectedHandler = formatHandler(result.selectedFormat.typeId)
  if selectedHandler.isNil:
    raise newException(ValueError,
      "unsupported input format: " & result.selectedFormat.typeId)
  case selectedHandler.kind
  of vhkWorkbenchIcon:
    let parsed = parsedValue[VextParsedWorkbenchIcon](selectedParsed,
      vhkWorkbenchIcon)
    let icon = parsed.icon
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
    let glow = parsed.glow
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
  of vhkGif:
    let source = parsedValue[GifImageSource](selectedParsed, vhkGif)
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
  of vhkPng:
    let source = parsedValue[PngImageSource](selectedParsed, vhkPng)
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
  of vhkQoi:
    let source = parsedValue[QoiImageSource](selectedParsed, vhkQoi)
    result.resources.roots.add VextResourceNode(
      path: QoiImageResourcePath, typeId: QoiImageTypeId, kind: vrnkRaster,
      raster: decodeQoi(source), metadata: @[
        integerMetadata("channels", source.channels),
        integerMetadata("colour-space", source.colourSpace)])
  of vhkNetpbm:
    let source = parsedValue[NetpbmSource](selectedParsed, vhkNetpbm)
    let group = VextResourceNode(path: NetpbmImageResourcePath,
      typeId: NetpbmTypeId, kind: vrnkGroup,
      metadata: @[integerMetadata("images", source.images.len)])
    for index, imageSource in source.images:
      let path = if source.images.len == 1: NetpbmImageResourcePath
        else: NetpbmImageResourcePath & "/" & $(index + 1)
      let image = VextResourceNode(path: path, typeId: NetpbmImageTypeId,
        kind: vrnkRaster, raster: decodeNetpbm(imageSource), metadata: @[
          integerMetadata("variant", ord(imageSource.variant)),
          integerMetadata("depth", imageSource.depth),
          integerMetadata("maxval", imageSource.maxValue),
          stringMetadata("tuple-type", imageSource.tupleType)])
      if source.images.len == 1:
        result.resources.roots.add image
      else:
        group.children.add image
    if source.images.len > 1: result.resources.roots.add group
  of vhkBmp, vhkDib:
    let source = parsedValue[BmpImageSource](selectedParsed,
      selectedHandler.kind)
    result.resources.roots.add VextResourceNode(
      path: BmpImageResourcePath, typeId: BmpImageTypeId, kind: vrnkRaster,
      raster: decodeBmp(source), metadata: @[
        integerMetadata("bits-per-pixel", source.bitsPerPixel),
        integerMetadata("compression", source.compression),
        integerMetadata("colours-used", source.coloursUsed),
        integerMetadata("pixels-per-metre.x", source.xPixelsPerMetre),
        integerMetadata("pixels-per-metre.y", source.yPixelsPerMetre)])
  of vhkPcx:
    let source = parsedValue[PcxImageSource](selectedParsed, vhkPcx)
    result.resources.roots.add VextResourceNode(
      path: PcxImageResourcePath, typeId: PcxImageTypeId, kind: vrnkRaster,
      raster: decodePcx(source, pcxChannelOrder), metadata: @[
        integerMetadata("bits-per-pixel", source.bitsPerPixel),
        integerMetadata("planes", source.planes),
        integerMetadata("position.x", source.xMin),
        integerMetadata("position.y", source.yMin),
        integerMetadata("dpi.x", source.horizontalDpi),
        integerMetadata("dpi.y", source.verticalDpi)])
  of vhkWav:
    let source = parsedValue[WavSource](selectedParsed, vhkWav)
    var metadata = @[
      integerMetadata("channels", source.channelCount),
      integerMetadata("sample-rate", source.sampleRate),
      integerMetadata("bits-per-sample", source.bitsPerSample),
      integerMetadata("samples", source.sampleData.len div source.blockAlign),
      integerMetadata("duration-ms", (source.sampleData.len div
        source.blockAlign) * 1000 div source.sampleRate)
    ]
    for index, chunk in source.chunks:
      metadata.add stringMetadata("chunk." & $index & ".type", chunk.kind)
      metadata.add integerMetadata("chunk." & $index & ".size", chunk.data.len)
    result.resources.roots.add VextResourceNode(
      path: WavSoundResourcePath, typeId: WavSoundTypeId,
      kind: vrnkAudio, audioKind: varkSound, sound: decodeWav(source),
      metadata: metadata)
  of vhkZip:
    let archive = parsedValue[ZipArchive](selectedParsed, vhkZip)
    let root = VextResourceNode(path: "/archive", typeId: ZipArchiveTypeId,
      kind: vrnkGroup, metadata: @[
        integerMetadata("entries", archive.entries.len),
        stringMetadata("comment", archive.comment)])
    for entry in archive.entries:
      addZipEntry(root, entry, depth, ignoreWarnings, pcxChannelOrder,
        result.warnings)
    result.resources.roots.add root
  of vhkAmigaAdf:
    let volume = parsedValue[AmigaAdfVolume](selectedParsed, vhkAmigaAdf)
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
  of vhkAmigaDms:
    let archive = parsedValue[AmigaDmsArchive](selectedParsed, vhkAmigaDms)
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
          rawDataAvailable: true,
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
  of vhkXpk:
    let archive = parsedValue[XpkArchive](selectedParsed, vhkXpk)
    let unpacked = unpackXpk(archive)
    result.resources.roots.add containedFileNode("/content", filename,
      XpkTypeId, unpacked, @[
        stringMetadata("xpk.compression", archive.compression),
        integerMetadata("xpk.compressed-length", data.len),
        integerMetadata("xpk.uncompressed-length", archive.unpackedSize),
        integerMetadata("xpk.chunks", archive.chunks.len)
      ], depth, ignoreWarnings, pcxChannelOrder, result.warnings)
  of vhkPowerPacker:
    let archive = parsedValue[PowerPackerArchive](selectedParsed,
      vhkPowerPacker)
    let unpacked = unpackPowerPacker(archive)
    result.resources.roots.add containedFileNode("/content", filename,
      PowerPackerTypeId, unpacked, @[
        stringMetadata("powerpacker.version", archive.version),
        integerMetadata("powerpacker.compressed-length", data.len),
        integerMetadata("powerpacker.uncompressed-length", archive.unpackedSize)
      ], depth, ignoreWarnings, pcxChannelOrder, result.warnings)
  of vhkAmigaAnim:
    let
      anim = parsedValue[AmigaAnim](selectedParsed, vhkAmigaAnim)
      raster = decodeAmigaAnim(anim)
    var animMetadata = @[
      integerMetadata("frames", if anim.hasDpan: anim.logicalFrameCount
        else: anim.frames.len + 1),
      integerMetadata("stored-frames", anim.frames.len + 1),
      integerMetadata("colour-cycle-ranges", raster.colourCycleRanges.len),
      integerMetadata("planes", anim.initial.image.header.planes),
      integerMetadata("camg", int(anim.initial.image.camg))]
    if anim.hasDpan:
      animMetadata.add integerMetadata("dpan-version", anim.dpanVersion)
      animMetadata.add integerMetadata("frames-per-second",
        anim.framesPerSecond)
    result.resources.roots.add VextResourceNode(
      path: AmigaAnimResourcePath,
      typeId: AmigaAnimTypeId,
      kind: vrnkRaster,
      raster: raster,
      metadata: animMetadata)
  of vhkAmiga8svx:
    let source = parsedValue[Amiga8svx](selectedParsed, vhkAmiga8svx)
    let instrument = decodeAmiga8svx(source)
    result.resources.roots.add VextResourceNode(
      path: Amiga8svxResourcePath,
      typeId: Amiga8svxResourceTypeId,
      kind: vrnkAudio,
      audioKind: varkSampledInstrument,
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
  of vhkAmiga16sv:
    let source = parsedValue[Amiga16sv](selectedParsed, vhkAmiga16sv)
    let instrument = decodeAmiga16sv(source)
    result.resources.roots.add VextResourceNode(
      path: Amiga16svResourcePath,
      typeId: Amiga16svResourceTypeId,
      kind: vrnkAudio,
      audioKind: varkSampledInstrument,
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
  of vhkAmigaAcbm, vhkAmigaIlbm:
    let image = if selectedHandler.kind == vhkAmigaAcbm:
      parsedValue[AmigaAcbm](selectedParsed, vhkAmigaAcbm).image
    else:
      parsedValue[AmigaIlbm](selectedParsed, vhkAmigaIlbm).image
    let raster = decodeAmigaIlbmRaster(image)
    result.resources.roots.add VextResourceNode(
      path: AmigaIlbmImageResourcePath,
      typeId: AmigaIlbmImageTypeId,
      kind: vrnkRaster,
      raster: raster,
      metadata: @[
        integerMetadata("planes", image.header.planes),
        integerMetadata("masking", image.header.masking),
        integerMetadata("transparent-colour", image.header.transparentColour),
        integerMetadata("position.x", image.header.x),
        integerMetadata("position.y", image.header.y),
        integerMetadata("aspect.x", image.header.xAspect),
        integerMetadata("aspect.y", image.header.yAspect),
        integerMetadata("colour-cycle-ranges", raster.colourCycleRanges.len),
        integerMetadata("camg", int(image.camg))
      ])
  of vhkAmigaPbm:
    let image = parsedValue[AmigaPbm](selectedParsed, vhkAmigaPbm).image
    result.resources.roots.add VextResourceNode(
      path: AmigaPbmImageResourcePath, typeId: AmigaPbmImageTypeId,
      kind: vrnkRaster, raster: decodeAmigaPbm(image), metadata: @[
        integerMetadata("planes", image.header.planes),
        integerMetadata("masking", image.header.masking),
        integerMetadata("compression", image.header.compression),
        integerMetadata("transparent-colour", image.header.transparentColour),
        integerMetadata("position.x", image.header.x),
        integerMetadata("position.y", image.header.y),
        integerMetadata("aspect.x", image.header.xAspect),
        integerMetadata("aspect.y", image.header.yAspect)])
  of vhkAmigaIff:
    let form = parsedValue[AmigaIffForm](selectedParsed, vhkAmigaIff)
    let group = VextResourceNode(
      path: "/chunks", typeId: AmigaIffTypeId, kind: vrnkGroup,
      metadata: @[stringMetadata("form.type", form.formType)])
    for index, chunk in form.chunks:
      group.children.add VextResourceNode(
        path: "/chunks/" & $index,
        typeId: "amiga.iff-chunk",
        kind: vrnkOpaque,
        data: chunk.data,
        rawDataAvailable: true,
        metadata: @[
          stringMetadata("chunk.id", chunk.id),
          integerMetadata("data.length", chunk.data.len)
        ])
    result.resources.roots.add group
  of vhkTga:
    let image = parsedValue[TgaImageSource](selectedParsed, vhkTga)
    result.resources.roots.add VextResourceNode(
      path: TgaImageResourcePath, typeId: TgaImageTypeId,
      kind: vrnkRaster, raster: decodeTga(image), metadata: @[
        integerMetadata("image-type", image.imageType),
        integerMetadata("bits-per-pixel", image.pixelBits),
        integerMetadata("attribute-bits", image.attributeBits),
        integerMetadata("position.x", image.xOrigin),
        integerMetadata("position.y", image.yOrigin),
        integerMetadata("colour-map.origin", image.colourMapOrigin),
        integerMetadata("colour-map.length", image.colourMapLength),
        integerMetadata("colour-map.entry-bits", image.colourMapEntryBits),
        stringMetadata("origin", if image.topOrigin: "top-left" else: "bottom-left")])
  of vhkFlic:
    let animation = parsedValue[FlicSource](selectedParsed, vhkFlic)
    result.resources.roots.add VextResourceNode(
      path: FlicAnimationResourcePath, typeId: FlicAnimationTypeId,
      kind: vrnkRaster, raster: decodeFlic(animation), metadata: @[
        integerMetadata("file-type", animation.fileMagic),
        integerMetadata("frames", animation.frameCount),
        integerMetadata("depth", animation.depth),
        integerMetadata("speed", int(animation.speed)),
        integerMetadata("flags", animation.flags),
        integerMetadata("creator", int(animation.creator)),
        integerMetadata("aspect.x", animation.aspectX),
        integerMetadata("aspect.y", animation.aspectY),
        integerMetadata("extension-flags", animation.extensionFlags),
        integerMetadata("keyframe-frequency", animation.keyframeFrequency),
        integerMetadata("total-frames", animation.totalFrames),
        integerMetadata("cel.center.x", animation.celCenterX),
        integerMetadata("cel.center.y", animation.celCenterY),
        integerMetadata("cel.transparent-index", animation.transparentIndex)])
  of vhkAmosProgram:
    let program = parsedValue[AmosProgram](selectedParsed, vhkAmosProgram)
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
  of vhkAmosBankSet:
    let bankSet = parsedValue[AmosBankSet](selectedParsed, vhkAmosBankSet)
    result.resources.roots.add amosBankSetGroup(bankSet)
  of vhkAmosBank:
    let bank = parsedValue[AmosBank](selectedParsed, vhkAmosBank)
    let path = if bank.bankType == AmosPackedPictureBankType:
      AmosPackedPictureResourcePath else: "/bank"
    result.resources.roots.add amosBankNode(path, bank)
  of vhkAmosSpriteBank, vhkAmosIconBank:
    let bank = parsedValue[AmosSpriteIconBank](selectedParsed,
      selectedHandler.kind)
    let resourceName = if bank.kind == asibkSprite: "sprite" else: "icon"
    result.resources.roots.add amosSpriteIconGroup(
      "/" & resourceName, "/" & resourceName, bank)
  of vhkZxSpectrumScreen:
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      parsedValue[seq[byte]](selectedParsed, vhkZxSpectrumScreen))
  of vhkZxSpectrumSnapshot:
    let snapshotData = parsedValue[seq[byte]](selectedParsed,
      vhkZxSpectrumSnapshot)
    result.resources.roots.add rasterNode(ZxSpectrumScreenResourcePath,
      extractZxSpectrumSnapshotScreen(snapshotData))
    if snapshotData.len == ZxSpectrumSnapshot48Size:
      try:
        result.resources.roots.add VextResourceNode(
          path: ZxSpectrumBasicResourcePath,
          typeId: ZxSpectrumBasicTypeId,
          kind: vrnkText,
          text: extractZxSpectrumSnapshotBasic(snapshotData))
      except ValueError:
        discard
  of vhkZxSpectrumTap:
    let tap = parsedValue[VextParsedZxTap](selectedParsed, vhkZxSpectrumTap)
    let screens = tap.screens
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
    let listings = tap.listings
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
proc inspectSource*(filename: string, data: openArray[byte],
    inputFormat = "", ignoreWarnings = false,
    pcxChannelOrder = pcoRgb,
    progress: VextProgressCallback = nil): VextInspection =
  reportProgress(progress, vppDetecting, filename, "Detecting input format")
  reportProgress(progress, vppInspecting, filename, "Inspecting container")
  reportProgress(progress, vppDecoding, filename, "Decoding resources")
  result = inspectSourceDepth(filename, data, inputFormat, 0, ignoreWarnings,
    pcxChannelOrder)
  reportProgress(progress, vppTraversing, filename,
    "Resource tree complete", result.resources.leafResources.len,
    result.resources.leafResources.len)
  reportProgress(progress, vppComplete, filename, "Inspection complete", 1, 1)

proc exportResource*(tree: VextResourceTree,
    request: VextExportRequest): VextExportResult =
  var available: seq[VextResourceNode]
  for item in tree.leafResources:
    if item.kind in {vrnkRaster, vrnkText, vrnkAudio} or
        (item.kind == vrnkOpaque and item.rawDataAvailable):
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
    result.outputFormat = resource.defaultExportFormat
  var supported = false
  for format in resource.exportFormatsFor:
    if format.id == result.outputFormat:
      supported = true
      break
  if not supported:
    raise newException(ValueError,
      "unsupported output format: " & result.outputFormat)
  case resource.kind
  of vrnkOpaque:
    if not resource.rawDataAvailable:
      raise newException(ValueError, "resource is not exportable: " &
        resource.path)
    if result.outputFormat != "bin":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    result.artifacts = exportRaw(resource.data,
      request.suggestedName & ".bin")
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
    let frameLimit = if request.colourCycleFrameLimit > 0:
        request.colourCycleFrameLimit
      else: DefaultColourCycleFrameLimit
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
      of "gif-cycled", "apng-cycled":
        let cycled = expandColourCycles(resource.raster, frameLimit,
          request.allowLargeAnimation)
        if result.outputFormat == "gif-cycled":
          exportGif(cycled, request.suggestedName & ".gif")
        else:
          exportApng(cycled, request.suggestedName & ".png")
      else:
        raise newException(ValueError,
          "unsupported output format: " & result.outputFormat)
  of vrnkAudio:
    if result.outputFormat != "wav":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    result.artifacts = exportWav(resource.audioSound,
      request.suggestedName & ".wav")
  else:
    raise newException(ValueError, "resource is not exportable: " &
      resource.path)

proc exportAllResources*(tree: VextResourceTree,
    request: VextExportAllRequest): VextExportAllResult =
  var patterns: seq[seq[string]]
  for pattern in request.resourcePatterns:
    patterns.add validateResourcePattern(pattern)

  var selected: seq[VextResourceNode]
  for resource in tree.leafResources:
    if not (resource.kind in {vrnkRaster, vrnkText, vrnkAudio} or
        (resource.kind == vrnkOpaque and resource.rawDataAvailable)):
      continue
    if patterns.len == 0:
      selected.add resource
    else:
      for pattern in patterns:
        if resourcePatternMatches(resource.path, pattern):
          selected.add resource
          break

  if selected.len == 0:
    if patterns.len == 0:
      raise newException(ValueError, "container exposes no exportable resources")
    raise newException(ValueError, "no exportable resources matched")

  var usedNames: seq[string]
  for resource in selected:
    var exported = exportResource(tree, VextExportRequest(
      resourcePath: resource.path,
      outputFormat: request.outputFormat,
      suggestedName: exportNameForPath(resource.path),
      colourCycleFrameLimit: request.colourCycleFrameLimit,
      allowLargeAnimation: request.allowLargeAnimation))
    for artifact in exported.artifacts.artifacts.mitems:
      artifact.suggestedFilename = uniqueArtifactName(
        artifact.suggestedFilename, usedNames)
    result.exports.add exported
