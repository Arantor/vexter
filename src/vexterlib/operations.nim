## High-level inspection and export operations shared by every frontend.

import std/[os, strutils, tables]
import ./artifacts
import ./archetypes/raster
import ./archetypes/audio
import ./archetypes/palette
import ./archetypes/tracker
import ./transformations/colour_cycle
import ./transformations/palette_swatch
import ./detection
import ./handler_registry
import ./exporters/[bmfont, gif, gpl, html_report, metadata_json, png, raw, tracker_json, wav]
import ./resource_tree
import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_diskfont, amiga_dms, amiga_hunk_executable, amiga_iff, amiga_ilbm, amiga_lha_sfx, amiga_pbm, amiga_workbench_icon, amos_bank, amos_bank_set, amos_packed_picture, amos_program,
  amos_sprite_icon_bank, ansi_art, bmfont, bmp, creative_voice, doom_wad, flic, fzx, gif_container, iso9660, jpeg, netpbm, openraster, pcx, png_container,
  adobe_swatch_exchange, aseprite, gimp_palette, koala_painter, paint_net_palette, protracker_mod, qoi, tga, wav, windows_icon, zip_archive, lha_archive, zx_spectrum_snapshot, zx_spectrum_tap]
import ./containers/xpk_shri
import ./containers/powerpacker
import ./metadata
import ./resources/[amiga_anim_image, amiga_diskfont_font, amiga_ilbm_image, amiga_pbm_image, amiga_workbench_icon_image, amos_listing, amos_packed_picture_image, amos_planar_image, bmp_image, flic_animation, gif_image, netpbm_image, png_image, zx_spectrum_basic,
  ansi_art_image, bmfont_font, fzx_font, jpeg_image, koala_painter_image, pcx_image, protracker_replay, qoi_image, tga_image, windows_icon_image, zx_spectrum_screen]

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

  VextCompanionResolver* = proc(relativePath: string): seq[byte]
    {.closure.}

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

  VextDemandDecodeResult* = enum
    vddNotApplicable
    vddUnrecognized
    vddDecoded
    vddFailed

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
    warnings*: seq[string]

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
      result.add VextExportFormat(id: "palette-swatch",
        displayName: "Palette swatch PNG", extensions: @["png"],
        mediaTypes: @["image/png"])
      result.add VextExportFormat(id: "gpl", displayName: "GIMP palette (GPL)",
        extensions: @["gpl"], mediaTypes: @["application/x-gimp-palette"])
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
      result.add VextExportFormat(id: "palette-swatch",
        displayName: "Palette swatch PNG", extensions: @["png"],
        mediaTypes: @["image/png"])
      result.add VextExportFormat(id: "gpl", displayName: "GIMP palette (GPL)",
        extensions: @["gpl"], mediaTypes: @["application/x-gimp-palette"])
    of vrkTrueColourImage:
      result = @[VextExportFormat(id: "png", displayName: "PNG image",
        extensions: @["png"], mediaTypes: @["image/png"], isDefault: true)]
    of vrkTrueColourAnimation:
      result = @[VextExportFormat(id: "apng", displayName: "Animated PNG",
        extensions: @["png"], mediaTypes: @["image/apng"], isDefault: true)]
  of vrnkAudio:
    result = @[VextExportFormat(id: "wav", displayName: "WAVE audio",
      extensions: @["wav"], mediaTypes: @["audio/wav"], isDefault: true)]
  of vrnkFont:
    result = @[VextExportFormat(id: "bmfont",
      displayName: "BMFont text and PNG atlas",
      extensions: @["fnt"],
      mediaTypes: @["text/plain", "image/png"], isDefault: true)]
  of vrnkPalette:
    result = @[
      VextExportFormat(id: "palette-swatch",
        displayName: "Palette swatch PNG", extensions: @["png"],
        mediaTypes: @["image/png"], isDefault: true),
      VextExportFormat(id: "gpl", displayName: "GIMP palette (GPL)",
        extensions: @["gpl"], mediaTypes: @["application/x-gimp-palette"])]
  of vrnkTracker:
    result = @[VextExportFormat(id: "tracker-json",
      displayName: "Tracker JSON", extensions: @["json"],
      mediaTypes: @["application/json"], isDefault: true)]
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
  result.add VextExportFormat(id: "metadata-json",
    displayName: "Metadata JSON", extensions: @["json"],
    mediaTypes: @["application/json"])
  result.add VextExportFormat(id: "html-report",
    displayName: "Self-contained HTML report", extensions: @["html"],
    mediaTypes: @["text/html"])

proc defaultExportFormat*(resource: VextResourceNode): string =
  for format in resource.exportFormatsFor:
    if format.isDefault:
      return format.id

proc gplExportUsesAlpha*(resource: VextResourceNode): bool =
  ## True when GPL export selects Aseprite's RGBA extension.
  if not resource.isNil and resource.kind == vrnkPalette:
    resource.palette.usesGplRgbaExtension
  else:
    false

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

proc suffixedExportName(name: string, suffix: int): string =
  if suffix <= 1: return name
  let slash = name.rfind('/')
  if slash < 0: name & "-" & $suffix
  else: name[0 .. slash] & name[slash + 1 .. ^1] & "-" & $suffix

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
    pcxChannelOrder: PcxChannelOrder, ansiLetterSpacing: AnsiLetterSpacing,
    ansiAspect: AnsiPresentationAspect,
    companionResolver: VextCompanionResolver,
    backingSource: VextPayloadSource = nil): VextInspection

proc rebaseNode(node: VextResourceNode, prefix: string) =
  node.path = prefix & node.path
  for child in node.children:
    rebaseNode(child, prefix)

proc containedFileNode(path, filename, fallbackType: string,
    data: openArray[byte], metadata: seq[VextMetadataEntry], depth: int,
    ignoreWarnings: bool, pcxChannelOrder: PcxChannelOrder,
    warnings: var seq[VextInspectionWarning], isolateFailure = false):
    VextResourceNode =
  var retainedMetadata = metadata
  if depth >= 8:
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, rawDataAvailable: true,
      metadata: retainedMetadata)
  var candidates: seq[VextDetectionCandidate]
  try:
    candidates = detectFormats(filename, data)
  except CatchableError as error:
    if not isolateFailure: raise
    warnings.add VextInspectionWarning(path: path, format: fallbackType,
      message: error.msg)
    retainedMetadata.add stringMetadata("decode.warning", error.msg)
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, rawDataAvailable: true,
      failureFormat: "recognized contained format",
      failureMessage: error.msg, metadata: retainedMetadata)
  if candidates.len == 0:
    return VextResourceNode(path: path, typeId: fallbackType,
      kind: vrnkOpaque, data: @data, rawDataAvailable: true,
      metadata: retainedMetadata)
  var nested: VextInspection
  try:
    nested = inspectSourceDepth(filename, data, "", depth + 1, ignoreWarnings,
      pcxChannelOrder, alsAuto, apaAuto, nil)
  except CatchableError as error:
    if ignoreWarnings or isolateFailure:
      warnings.add VextInspectionWarning(
        path: path, format: candidates[0].typeId, message: error.msg)
      retainedMetadata.add stringMetadata("decode.format", candidates[0].typeId)
      retainedMetadata.add stringMetadata("decode.warning", error.msg)
      return VextResourceNode(path: path, typeId: fallbackType,
        kind: vrnkOpaque, data: @data, rawDataAvailable: true,
        failureFormat: candidates[0].typeId,
        failureMessage: error.msg, metadata: retainedMetadata)
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

proc iso9660Payload(entry: Iso9660Entry, layout: Iso9660Layout,
    source: VextPayloadSource): VextPayloadRef =
  result.source = source
  result.length = entry.dataLength
  if layout == ilCooked2048:
    if entry.dataLength > 0:
      result.spans = @[VextPayloadSpan(
        offset: entry.extentBlock * Iso9660LogicalBlockSize,
        length: entry.dataLength)]
    return
  result.spans = newSeqOfCap[VextPayloadSpan](
    (entry.dataLength + Iso9660LogicalBlockSize - 1) div
      Iso9660LogicalBlockSize)
  var logicalOffset = entry.extentBlock * Iso9660LogicalBlockSize
  var remaining = entry.dataLength
  while remaining > 0:
    let sector = logicalOffset div Iso9660LogicalBlockSize
    let within = logicalOffset mod Iso9660LogicalBlockSize
    let amount = min(remaining, Iso9660LogicalBlockSize - within)
    let physicalOffset = sector * 2352 + 16 + within
    result.spans.add VextPayloadSpan(offset: physicalOffset, length: amount)
    logicalOffset += amount
    remaining -= amount

proc zipPayload(entry: ZipEntry,
    source: VextPayloadSource): VextPayloadRef =
  let capturedEntry = entry
  result = VextPayloadRef(source: source, length: entry.uncompressedSize,
    materializer: proc(): seq[byte] =
      extractZipEntry(source.data, capturedEntry))

proc addZipEntry(root: VextResourceNode, entry: ZipEntry,
    source: VextPayloadSource,
    directories: var Table[string, VextResourceNode]) =
  var parent = root
  var path = root.path
  for index, segment in entry.segments:
    path.add "/" & segment
    let last = index == entry.segments.high
    var existing = directories.getOrDefault(path)
    if last and not entry.isDirectory:
      if not existing.isNil:
        raise newException(ValueError, "conflicting ZIP entry path: " & entry.name)
      let metadata = @[
        stringMetadata("zip.name", entry.name),
        integerMetadata("compression.method", entry.compressionMethod),
        integerMetadata("compressed.length", entry.compressedSize),
        integerMetadata("data.length", entry.uncompressedSize)]
      parent.children.add VextResourceNode(path: path, typeId: ZipFileTypeId,
        kind: vrnkOpaque, lazyPayload: zipPayload(entry, source),
        rawDataAvailable: true, metadata: metadata)
    else:
      if existing.isNil:
        existing = VextResourceNode(path: path, typeId: ZipDirectoryTypeId,
          kind: vrnkGroup)
        parent.children.add existing
        directories[path] = existing
      elif existing.kind != vrnkGroup or existing.typeId != ZipDirectoryTypeId:
        raise newException(ValueError, "conflicting ZIP entry path: " & entry.name)
      parent = existing

proc addIso9660Entry(root: VextResourceNode, entry: var Iso9660Entry,
    source: openArray[byte], backingSource: VextPayloadSource,
    image: ptr Iso9660Image, depth: int,
    ignoreWarnings: bool, pcxChannelOrder: PcxChannelOrder,
    warnings: var seq[VextInspectionWarning],
    directories: var Table[string, VextResourceNode],
    inspectionFiles, inspectionBytes: var int) =
  var parent = root
  var path = root.path
  for index, segment in entry.segments:
    path.add "/" & segment
    let last = index == entry.segments.high
    var existing = directories.getOrDefault(path)
    if last and not entry.isDirectory:
      if not existing.isNil:
        raise newException(ValueError,
          "conflicting ISO 9660 entry path: " & entry.name)
      let metadata = @[
        stringMetadata("iso9660.name", entry.name),
        integerMetadata("iso9660.extent-block", entry.extentBlock),
        integerMetadata("data.length", entry.dataLength),
        integerMetadata("iso9660.file-version", entry.fileVersion),
        integerMetadata("iso9660.hidden", int(entry.hidden)),
        integerMetadata("iso9660.associated", int(entry.associated)),
        integerMetadata("iso9660.system-use-bytes", entry.systemUseBytes),
        stringMetadata("iso9660.recording-time", entry.recordingTime)]
      var retainedMetadata = metadata
      let lazyPayload = iso9660Payload(entry, image[].layout, backingSource)
      let inspectContained = entry.dataLength <= Iso9660RecursiveInspectionLimit and
        inspectionFiles < 512 and
        inspectionBytes <= 128 * 1024 * 1024 - entry.dataLength
      if not inspectContained:
        parent.children.add VextResourceNode(path: path,
          typeId: Iso9660FileTypeId, kind: vrnkOpaque,
          lazyPayload: lazyPayload, rawDataAvailable: true,
          metadata: retainedMetadata)
        return
      inc inspectionFiles
      inspectionBytes += entry.dataLength
      entry.data = extractIso9660Entry(source, image[], entry)
      defer: entry.data.setLen(0)
      var candidates: seq[VextDetectionCandidate]
      try:
        candidates = detectFormats(segment, entry.data)
      except CatchableError as error:
        warnings.add VextInspectionWarning(path: path,
          format: Iso9660FileTypeId, message: error.msg)
        retainedMetadata.add stringMetadata("decode.warning", error.msg)
        parent.children.add VextResourceNode(path: path,
          typeId: Iso9660FileTypeId, kind: vrnkOpaque,
          lazyPayload: lazyPayload, rawDataAvailable: true,
          failureFormat: "recognized contained format",
          failureMessage: error.msg, metadata: retainedMetadata)
        return
      if candidates.len == 0 or depth >= 8:
        parent.children.add VextResourceNode(path: path,
          typeId: Iso9660FileTypeId, kind: vrnkOpaque,
          lazyPayload: lazyPayload, rawDataAvailable: true,
          metadata: retainedMetadata)
        return
      var nested: VextInspection
      try:
        nested = inspectSourceDepth(segment, entry.data, "", depth + 1,
          ignoreWarnings, pcxChannelOrder, alsAuto, apaAuto, nil)
      except CatchableError as error:
        warnings.add VextInspectionWarning(path: path,
          format: candidates[0].typeId, message: error.msg)
        retainedMetadata.add stringMetadata("decode.format", candidates[0].typeId)
        retainedMetadata.add stringMetadata("decode.warning", error.msg)
        parent.children.add VextResourceNode(path: path,
          typeId: Iso9660FileTypeId, kind: vrnkOpaque,
          lazyPayload: lazyPayload, rawDataAvailable: true,
          failureFormat: candidates[0].typeId,
          failureMessage: error.msg, metadata: retainedMetadata)
        return
      for warning in nested.warnings:
        warnings.add VextInspectionWarning(path: path & warning.path,
          format: warning.format, message: warning.message)
      let nestedNode = VextResourceNode(path: path,
        typeId: nested.selectedFormat.typeId, kind: vrnkGroup,
        metadata: retainedMetadata)
      for child in nested.resources.roots:
        rebaseNode(child, path)
        nestedNode.children.add child
      entry.data.setLen(0)
      parent.children.add nestedNode
    else:
      if existing.isNil:
        existing = VextResourceNode(path: path,
          typeId: Iso9660DirectoryTypeId, kind: vrnkGroup)
        parent.children.add existing
        directories[path] = existing
      elif existing.kind != vrnkGroup or
          existing.typeId != Iso9660DirectoryTypeId:
        raise newException(ValueError,
          "conflicting ISO 9660 entry path: " & entry.name)
      if last:
        existing.metadata = @[
          integerMetadata("iso9660.extent-block", entry.extentBlock),
          integerMetadata("data.length", entry.dataLength),
          integerMetadata("iso9660.hidden", int(entry.hidden)),
          integerMetadata("iso9660.system-use-bytes", entry.systemUseBytes),
          stringMetadata("iso9660.recording-time", entry.recordingTime)]
      parent = existing

proc addLhaEntry(root: VextResourceNode, entry: LhaEntry, depth: int,
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
        raise newException(ValueError, "conflicting LHA entry path: " & entry.name)
      let metadata = @[
        stringMetadata("lha.name", entry.name),
        stringMetadata("compression.method", entry.compressionMethod),
        integerMetadata("compressed.length", entry.compressedSize),
        integerMetadata("data.length", entry.uncompressedSize)]
      parent.children.add containedFileNode(path, segment, LhaFileTypeId,
        entry.data, metadata, depth, ignoreWarnings, pcxChannelOrder, warnings)
    else:
      if existing.isNil:
        existing = VextResourceNode(path: path, typeId: LhaDirectoryTypeId,
          kind: vrnkGroup)
        parent.children.add existing
      elif existing.kind != vrnkGroup or existing.typeId != LhaDirectoryTypeId:
        raise newException(ValueError, "conflicting LHA entry path: " & entry.name)
      parent = existing

proc hunkExecutableNode(executable: AmigaHunkExecutable,
    rootPath: string): VextResourceNode =
  result = VextResourceNode(path: rootPath,
    typeId: AmigaHunkExecutableTypeId, kind: vrnkGroup, metadata: @[
      integerMetadata("hunks", executable.hunks.len),
      integerMetadata("executable.length", executable.executableLength)])
  for index, hunk in executable.hunks:
    let typeId = case hunk.kind
      of ahkCode: AmigaHunkCodeTypeId
      of ahkData: AmigaHunkDataTypeId
      of ahkBss: AmigaHunkBssTypeId
    result.children.add VextResourceNode(path: rootPath & "/hunks/" & $index,
      typeId: typeId, kind: vrnkOpaque, data: hunk.data,
      rawDataAvailable: hunk.kind != ahkBss, metadata: @[
        integerMetadata("memory.longwords", hunk.memoryLongwords),
        integerMetadata("data.length", hunk.data.len)])
  if executable.overlay.len > 0:
    result.children.add VextResourceNode(path: rootPath & "/overlay",
      typeId: AmigaHunkOverlayTypeId, kind: vrnkOpaque,
      data: executable.overlay, rawDataAvailable: true)

proc diskfontNode(source: AmigaDiskfontSource, path, fallbackName: string,
    extraMetadata: seq[VextMetadataEntry] = @[]): VextResourceNode =
  var font = decodeAmigaDiskfont(source)
  if font.name.len == 0: font.name = fallbackName
  var metadata = extraMetadata
  metadata.add @[
    stringMetadata("font.name", source.name),
    integerMetadata("font.revision", source.revision),
    integerMetadata("font.style", source.style),
    integerMetadata("font.flags", source.flags),
    integerMetadata("font.nominal-width", source.xSize),
    integerMetadata("font.height", source.ySize),
    integerMetadata("font.baseline", source.baseline),
    integerMetadata("font.bold-smear", source.boldSmear),
    integerMetadata("character.first", source.lowCharacter),
    integerMetadata("character.last", source.highCharacter),
    integerMetadata("glyphs", source.glyphs.len),
    integerMetadata("bitmap.modulo", source.modulo),
    integerMetadata("colour.depth", source.depth),
    integerMetadata("colour.flags", source.colourFlags),
    integerMetadata("colour.foreground", source.foregroundColour),
    integerMetadata("colour.low", source.lowColour),
    integerMetadata("colour.high", source.highColour),
    integerMetadata("colour.plane-pick", source.planePick),
    integerMetadata("colour.plane-on-off", source.planeOnOff),
    integerMetadata("colour.palette-size", source.palette.len)]
  VextResourceNode(path: path, typeId: AmigaDiskfontResourceTypeId,
    kind: vrnkFont, font: font, metadata: metadata)

proc safeCompanionPath(path: string): bool =
  if path.len == 0 or path[0] in {'/', '\\'} or ':' in path or '\0' in path:
    return false
  for segment in path.replace('\\', '/').split('/'):
    if segment.len == 0 or segment in [".", ".."]: return false
  true

proc trueColourPage(raster: VextRaster): VextTrueColourImage =
  case raster.kind
  of vrkTrueColourImage:
    result = raster.trueColourImage
  of vrkIndexedImage:
    result = VextTrueColourImage(width: raster.image.width,
      height: raster.image.height,
      pixels: newSeq[VextRgb](raster.image.width * raster.image.height),
      alpha: newSeq[uint8](raster.image.width * raster.image.height))
    for y in 0 ..< raster.image.height:
      for x in 0 ..< raster.image.width:
        let offset = y * raster.image.width + x
        let pixel = raster.image.rgbaAt(x, y)
        result.pixels[offset] = VextRgb(r: pixel.r, g: pixel.g, b: pixel.b)
        result.alpha[offset] = pixel.a
  else:
    raise newException(ValueError, "BMFont atlas must be a static PNG image")

proc openRasterElementNode(element: OpenRasterElement,
    path: string): VextResourceNode =
  var metadata = @[
    stringMetadata("name", element.name),
    stringMetadata("opacity", $element.opacity),
    stringMetadata("visibility", element.visibility),
    stringMetadata("composite-op", element.compositeOp),
    integerMetadata("offset.x", element.x),
    integerMetadata("offset.y", element.y)]
  case element.kind
  of orekStack:
    metadata.add stringMetadata("isolation", element.isolation)
    result = VextResourceNode(path: path, typeId: OpenRasterStackTypeId,
      kind: vrnkGroup, metadata: metadata)
    for index, child in element.children:
      result.children.add openRasterElementNode(child, path & "/" & $index)
  of orekLayer:
    metadata.add stringMetadata("source", element.sourcePath)
    metadata.add integerMetadata("selected", int(element.selected))
    if element.pngSource:
      metadata.add integerMetadata("image.width", element.image.width)
      metadata.add integerMetadata("image.height", element.image.height)
      result = VextResourceNode(path: path, typeId: OpenRasterLayerTypeId,
        kind: vrnkRaster, raster: decodePngOrApng(element.image),
        metadata: metadata)
    else:
      metadata.add stringMetadata("decode.status",
        "source encoding is retained but not decoded")
      result = VextResourceNode(path: path, typeId: OpenRasterLayerTypeId,
        kind: vrnkOpaque, data: element.sourceData, rawDataAvailable: true,
        metadata: metadata)

proc inspectSourceDepth(filename: string, data: openArray[byte],
    inputFormat: string, depth: int, ignoreWarnings: bool,
    pcxChannelOrder: PcxChannelOrder, ansiLetterSpacing: AnsiLetterSpacing,
    ansiAspect: AnsiPresentationAspect,
    companionResolver: VextCompanionResolver,
    backingSource: VextPayloadSource): VextInspection =
  let detected = detectParsedFormats(filename, data)
  for item in detected:
    result.candidates.add item.candidate
  var selectedParsed: VextParsedContainer
  if inputFormat.len > 0:
    let forced = forceFormat(filename, data, inputFormat)
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
  of vhkAnsiArt:
    let source = parsedValue[AnsiArtSource](selectedParsed, vhkAnsiArt)
    var metadata = @[
      integerMetadata("ansi.columns", if source.sauce.present and source.sauce.info1 > 0: int(source.sauce.info1) else: 80),
      integerMetadata("ansi.control-sequences", source.meaningfulSequences),
      integerMetadata("ansi.glyph-width", source.ansiGlyphWidth(ansiLetterSpacing)),
      stringMetadata("ansi.aspect", if source.ansiLegacyAspect(ansiAspect): "legacy" else: "square"),
      integerMetadata("sauce.present", int(source.sauce.present))]
    if source.sauce.present:
      metadata.add stringMetadata("sauce.title", source.sauce.title)
      metadata.add stringMetadata("sauce.author", source.sauce.author)
      metadata.add stringMetadata("sauce.group", source.sauce.group)
      metadata.add stringMetadata("sauce.date", source.sauce.date)
      metadata.add stringMetadata("sauce.font", source.sauce.fontName)
      metadata.add integerMetadata("sauce.flags", int(source.sauce.flags))
      metadata.add integerMetadata("sauce.declared-lines", int(source.sauce.info2))
      for index, line in source.sauce.commentLines:
        metadata.add stringMetadata("sauce.comment." & $index, line)
    result.resources.roots.add VextResourceNode(path: AnsiImageResourcePath,
      typeId: AnsiImageTypeId, kind: vrnkRaster,
      raster: VextRaster(kind: vrkIndexedImage,
        image: renderAnsiArt(source, ansiLetterSpacing, ansiAspect)),
      metadata: metadata)
  of vhkAmigaDiskfontIndex:
    let index = parsedValue[AmigaDiskfontIndex](selectedParsed,
      vhkAmigaDiskfontIndex)
    let group = VextResourceNode(path: "/font",
      typeId: AmigaDiskfontIndexTypeId, kind: vrnkGroup, metadata: @[
        stringMetadata("index.kind", if index.tagged: "tagged" else: "plain"),
        integerMetadata("index.entries", index.entries.len)])
    for entryIndex, entry in index.entries:
      let entryKey = "index.entry." & $entryIndex
      group.metadata.add stringMetadata(entryKey & ".filename", entry.filename)
      group.metadata.add integerMetadata(entryKey & ".height", entry.ySize)
      group.metadata.add integerMetadata(entryKey & ".style", entry.style)
      group.metadata.add integerMetadata(entryKey & ".flags", entry.flags)
      group.metadata.add integerMetadata(entryKey & ".tags", entry.tags.len)
      for tag in entry.tags:
        if tag.identifier == TaDeviceDpi:
          group.metadata.add integerMetadata(entryKey & ".dpi.x",
            int(tag.value shr 16))
          group.metadata.add integerMetadata(entryKey & ".dpi.y",
            int(tag.value and 0xffff))
      let warningPath = "/font/" & $entry.ySize
      if not safeCompanionPath(entry.filename):
        result.warnings.add VextInspectionWarning(path: warningPath,
          format: AmigaDiskfontTypeId,
          message: "unsafe companion path in diskfont index: " & entry.filename)
        continue
      if companionResolver == nil:
        continue
      let companion = companionResolver(entry.filename.replace('\\', '/'))
      if companion.len == 0:
        continue
      var source: AmigaDiskfontSource
      try:
        source = parseAmigaDiskfont(companion)
      except ValueError as error:
        result.warnings.add VextInspectionWarning(path: warningPath,
          format: AmigaDiskfontTypeId,
          message: "invalid companion " & entry.filename & ": " & error.msg)
        continue
      if source.ySize != entry.ySize or
          ((source.style xor entry.style) and FsfColorFont) != 0:
        result.warnings.add VextInspectionWarning(path: warningPath,
          format: AmigaDiskfontTypeId,
          message: "companion metrics do not match index entry: " & entry.filename)
        continue
      var metadata = @[
        stringMetadata("index.filename", entry.filename),
        integerMetadata("index.position", entryIndex),
        integerMetadata("index.tags", entry.tags.len)]
      for tagIndex, tag in entry.tags:
        metadata.add integerMetadata("index.tag." & $tagIndex & ".id",
          int(tag.identifier))
        metadata.add integerMetadata("index.tag." & $tagIndex & ".value",
          int(tag.value))
        if tag.identifier == TaDeviceDpi:
          metadata.add integerMetadata("dpi.x", int(tag.value shr 16))
          metadata.add integerMetadata("dpi.y", int(tag.value and 0xffff))
      var path = warningPath
      for child in group.children:
        if child.path == path:
          path.add "-" & $(entryIndex + 1)
          break
      group.children.add diskfontNode(source, path,
        entry.filename.splitFile.name, metadata)
    result.resources.roots.add group
  of vhkAmigaHunkExecutable:
    result.resources.roots.add hunkExecutableNode(
      parsedValue[AmigaHunkExecutable](selectedParsed,
        vhkAmigaHunkExecutable), "/executable")
  of vhkAmigaLhaSfx:
    let sfx = parsedValue[AmigaLhaSfx](selectedParsed, vhkAmigaLhaSfx)
    result.resources.roots.add hunkExecutableNode(sfx.executable, "/executable")
    let usage = VextResourceNode(path: "/sfx/usage",
      typeId: LhaArchiveTypeId, kind: vrnkGroup)
    for entry in sfx.usageArchive.entries:
      addLhaEntry(usage, entry, depth, ignoreWarnings, pcxChannelOrder,
        result.warnings)
    result.resources.roots.add usage
    let archive = VextResourceNode(path: "/archive",
      typeId: LhaArchiveTypeId, kind: vrnkGroup, metadata: @[
        integerMetadata("entries", sfx.archive.entries.len)])
    for entry in sfx.archive.entries:
      addLhaEntry(archive, entry, depth, ignoreWarnings, pcxChannelOrder,
        result.warnings)
    result.resources.roots.add archive
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
  of vhkAmigaDiskfont:
    let source = parsedValue[AmigaDiskfontSource](selectedParsed,
      vhkAmigaDiskfont)
    result.resources.roots.add diskfontNode(source, AmigaDiskfontResourcePath,
      filename.splitFile.name)
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
  of vhkFzx:
    let source = parsedValue[FzxFontSource](selectedParsed, vhkFzx)
    let font = decodeFzx(source, filename.splitFile.name)
    var kernedCharacters, blankCharacters, maximumWidth, maximumRows: int
    for glyph in source.glyphs:
      if glyph.kern > 0: inc kernedCharacters
      if glyph.rowCount == 0: inc blankCharacters
      maximumWidth = max(maximumWidth, glyph.width)
      maximumRows = max(maximumRows, glyph.rowCount)
    result.resources.roots.add VextResourceNode(path: FzxFontResourcePath,
      typeId: FzxFontResourceTypeId, kind: vrnkFont, font: font,
      metadata: @[
        integerMetadata("height", source.height),
        integerMetadata("tracking", source.tracking),
        integerMetadata("first-character", 32),
        integerMetadata("last-character", source.lastCharacter),
        integerMetadata("characters", source.glyphs.len),
        integerMetadata("characters.kerned", kernedCharacters),
        integerMetadata("characters.blank", blankCharacters),
        integerMetadata("glyph.maximum-width", maximumWidth),
        integerMetadata("glyph.maximum-stored-rows", maximumRows),
        integerMetadata("unicode-mappings", font.mappings.len),
        stringMetadata("mapping", "printable ASCII positions assumed; custom positions retained as glyph source indices")])
  of vhkBmFont:
    let source = parsedValue[BmFontSource](selectedParsed, vhkBmFont)
    block:
      if companionResolver == nil:
        raise newException(ValueError,
          "BMFont descriptor requires an atlas companion resolver")
      var pages = newSeq[VextTrueColourImage](source.declaredPages)
      for page in source.pages:
        if not safeCompanionPath(page.filename):
          raise newException(ValueError,
            "unsafe BMFont atlas path: " & page.filename)
        let pageData = companionResolver(page.filename.replace('\\', '/'))
        if pageData.len == 0:
          raise newException(ValueError,
            "BMFont atlas page was not found: " & page.filename)
        var png: PngImageSource
        try:
          png = parsePng(pageData)
        except ValueError as error:
          raise newException(ValueError,
            "invalid BMFont atlas page " & page.filename & ": " & error.msg)
        pages[page.id] = decodePngOrApng(png).trueColourPage
      let font = decodeBmFont(source, pages)
      if source.declaredCharacters != source.characters.len:
        result.warnings.add VextInspectionWarning(path: BmFontResourcePath,
          format: BmFontTypeId, message: "descriptor declares " &
            $source.declaredCharacters & " characters but contains " &
            $source.characters.len & " records")
      if source.declaredKernings != source.kernings.len:
        result.warnings.add VextInspectionWarning(path: BmFontResourcePath,
          format: BmFontTypeId, message: "descriptor declares " &
            $source.declaredKernings & " kernings but contains " &
            $source.kernings.len & " records")
      result.resources.roots.add VextResourceNode(path: BmFontResourcePath,
        typeId: BmFontResourceTypeId, kind: vrnkFont, font: font,
        metadata: @[
          stringMetadata("encoding",
            case source.encoding
            of bfeText: "text"
            of bfeXml: "xml"
            of bfeBinary: "binary"),
          stringMetadata("font.face", source.face),
          integerMetadata("font.size", source.size),
          integerMetadata("font.bold", source.bold),
          integerMetadata("font.italic", source.italic),
          stringMetadata("font.charset", source.charset),
          integerMetadata("font.unicode", source.unicode),
          integerMetadata("font.smooth", source.smooth),
          integerMetadata("font.antialias", source.antialias),
          integerMetadata("font.stretch-height", source.stretchHeight),
          integerMetadata("font.outline", source.outline),
          integerMetadata("font.padding.top", source.padding[0]),
          integerMetadata("font.padding.right", source.padding[1]),
          integerMetadata("font.padding.bottom", source.padding[2]),
          integerMetadata("font.padding.left", source.padding[3]),
          integerMetadata("font.spacing.horizontal", source.spacing[0]),
          integerMetadata("font.spacing.vertical", source.spacing[1]),
          integerMetadata("pages", source.pages.len),
          integerMetadata("characters", source.characters.len),
          integerMetadata("characters.declared", source.declaredCharacters),
          integerMetadata("kernings", source.kernings.len),
          integerMetadata("kernings.declared", source.declaredKernings),
          integerMetadata("font.declared-line-height", source.lineHeight),
          integerMetadata("font.declared-baseline", source.baseline),
          integerMetadata("atlas.packed", source.packed),
          integerMetadata("atlas.channel.alpha", source.alphaChannel),
          integerMetadata("atlas.channel.red", source.redChannel),
          integerMetadata("atlas.channel.green", source.greenChannel),
          integerMetadata("atlas.channel.blue", source.blueChannel),
          integerMetadata("atlas.width", source.scaleWidth),
          integerMetadata("atlas.height", source.scaleHeight)])
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
  of vhkJpeg:
    let source = parsedValue[JpegSource](selectedParsed, vhkJpeg)
    var metadata = @[
      integerMetadata("jpeg.precision", source.precision),
      integerMetadata("jpeg.frame-marker", source.frameMarker),
      integerMetadata("jpeg.components", source.components.len),
      integerMetadata("exif.present", int(source.hasExif)),
      integerMetadata("exif.valid", int(source.exifValid)),
      integerMetadata("exif.orientation", source.orientation),
      integerMetadata("jfif.present", int(source.hasJfif))]
    if source.exifError.len > 0:
      metadata.add stringMetadata("exif.error", source.exifError)
    for entry in source.exifMetadata:
      metadata.add stringMetadata(entry.key, entry.value)
    if source.hasJfif:
      metadata.add stringMetadata("jfif.version",
        $source.jfifMajor & "." & $source.jfifMinor)
      metadata.add integerMetadata("jfif.density-units", source.densityUnits)
      metadata.add integerMetadata("jfif.density.x", source.xDensity)
      metadata.add integerMetadata("jfif.density.y", source.yDensity)
    result.resources.roots.add VextResourceNode(path: JpegImageResourcePath,
      typeId: JpegImageTypeId, kind: vrnkRaster, raster: decodeJpeg(source),
      metadata: metadata)
  of vhkQoi:
    let source = parsedValue[QoiImageSource](selectedParsed, vhkQoi)
    result.resources.roots.add VextResourceNode(
      path: QoiImageResourcePath, typeId: QoiImageTypeId, kind: vrnkRaster,
      raster: decodeQoi(source), metadata: @[
        integerMetadata("channels", source.channels),
        integerMetadata("colour-space", source.colourSpace)])
  of vhkKoalaPainter:
    let source = parsedValue[KoalaPainterSource](selectedParsed,
      vhkKoalaPainter)
    result.resources.roots.add VextResourceNode(
      path: KoalaPainterImageResourcePath,
      typeId: KoalaPainterImageTypeId, kind: vrnkRaster,
      raster: decodeKoalaPainter(source), metadata: @[
        integerMetadata("load-address", source.loadAddress),
        integerMetadata("background-byte", int(source.backgroundByte)),
        integerMetadata("background-colour", int(source.backgroundColour)),
        integerMetadata("trailing-bytes", source.trailingByteCount)])
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
  of vhkWindowsIcon:
    let icon = parsedValue[WindowsIcon](selectedParsed, vhkWindowsIcon)
    let rootPath = if icon.kind == wikIcon: "/icon" else: "/cursor"
    let group = VextResourceNode(path: rootPath,
      typeId: icon.windowsIconTypeId, kind: vrnkGroup, metadata: @[
        stringMetadata("container.kind", if icon.kind == wikIcon: "icon" else: "cursor"),
        integerMetadata("images", icon.entries.len)])
    for index, entry in icon.entries:
      let path = rootPath & "/" & $index
      var metadata = @[
        integerMetadata("directory.width", entry.width),
        integerMetadata("directory.height", entry.height),
        integerMetadata("directory.colour-count", entry.colourCount),
        integerMetadata("data.offset", entry.dataOffset),
        integerMetadata("data.length", entry.dataLength),
        stringMetadata("encoding", case entry.encoding
          of wieDib: "dib"
          of wiePng: "png"
          of wieUnknown: "unknown")]
      if icon.kind == wikCursor:
        metadata.add integerMetadata("hotspot.x", entry.hotspotX)
        metadata.add integerMetadata("hotspot.y", entry.hotspotY)
      else:
        metadata.add integerMetadata("planes", entry.planes)
        metadata.add integerMetadata("bits-per-pixel", entry.bitsPerPixel)
      case entry.encoding
      of wieDib:
        metadata.add integerMetadata("image.width", entry.dib.width)
        metadata.add integerMetadata("image.height", entry.dib.height)
        metadata.add integerMetadata("image.bits-per-pixel", entry.dib.bitsPerPixel)
        metadata.add integerMetadata("image.compression", entry.dib.compression)
        metadata.add integerMetadata("mask.bits-per-pixel", 1)
        group.children.add VextResourceNode(path: path,
          typeId: WindowsIconImageTypeId, kind: vrnkRaster,
          raster: decodeWindowsIconEntry(entry), metadata: metadata,
          defaultExportPriority: entry.dib.width * entry.dib.height)
      of wiePng:
        metadata.add integerMetadata("image.width", entry.png.width)
        metadata.add integerMetadata("image.height", entry.png.height)
        metadata.add integerMetadata("image.bit-depth", entry.png.bitDepth)
        metadata.add integerMetadata("image.colour-type", entry.png.colourType)
        group.children.add VextResourceNode(path: path,
          typeId: WindowsIconImageTypeId, kind: vrnkRaster,
          raster: decodeWindowsIconEntry(entry), metadata: metadata,
          defaultExportPriority: entry.png.width * entry.png.height)
      of wieUnknown:
        group.children.add VextResourceNode(path: path,
          typeId: "windows.icon-image.unknown", kind: vrnkOpaque,
          data: entry.data, rawDataAvailable: true, metadata: metadata)
    result.resources.roots.add group
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
  of vhkCreativeVoice:
    let source = parsedValue[CreativeVoiceSource](selectedParsed,
      vhkCreativeVoice)
    var metadata = @[
      integerMetadata("version.major", (source.version shr 8) and 0xff),
      integerMetadata("version.minor", source.version and 0xff),
      integerMetadata("data.offset", source.dataOffset),
      integerMetadata("blocks", source.blocks.len),
      integerMetadata("channels", source.channelCount),
      integerMetadata("codec", source.codec),
      integerMetadata("sample-rate", source.sampleRate),
      integerMetadata("bits-per-sample", source.bitsPerSample),
      integerMetadata("samples", source.channels[0].len),
      integerMetadata("duration-ms",
        source.channels[0].len * 1000 div source.sampleRate)]
    if source.usesExtendedInfo:
      metadata.add integerMetadata("extended.time-constant",
        source.extendedTimeConstant)
      metadata.add integerMetadata("extended.pack-method", source.packMethod)
      metadata.add integerMetadata("extended.voice-mode", source.voiceMode)
    for index, voiceBlock in source.blocks:
      metadata.add integerMetadata("block." & $index & ".type",
        voiceBlock.blockType)
      metadata.add integerMetadata("block." & $index & ".size",
        voiceBlock.size)
    result.resources.roots.add VextResourceNode(
      path: CreativeVoiceSoundResourcePath,
      typeId: CreativeVoiceSoundTypeId, kind: vrnkAudio,
      audioKind: varkSound, sound: decodeCreativeVoice(source),
      metadata: metadata)
  of vhkPaintNetPalette:
    let source = parsedValue[PaintNetPalette](selectedParsed,
      vhkPaintNetPalette)
    var metadata = @[
      integerMetadata("colours", source.palette.colours.len)]
    if source.declaredColourCount >= 0:
      metadata.add integerMetadata("declared-colours",
        source.declaredColourCount)
    if source.name.len > 0:
      metadata.add stringMetadata("name", source.name)
    if source.description.len > 0:
      metadata.add stringMetadata("description", source.description)
    result.resources.roots.add VextResourceNode(
      path: PaintNetPaletteResourcePath, typeId: PaintNetPaletteTypeId,
      kind: vrnkPalette, palette: source.palette, metadata: metadata)
  of vhkGimpPalette:
    let source = parsedValue[GimpPalette](selectedParsed, vhkGimpPalette)
    var metadata = @[
      integerMetadata("colours", source.palette.colours.len),
      integerMetadata("version", source.version),
      integerMetadata("columns", source.columns)]
    if source.name.len > 0:
      metadata.add stringMetadata("name", source.name)
    if source.hasAlpha:
      metadata.add stringMetadata("variant", "aseprite-rgba")
      metadata.add stringMetadata("channels", "RGBA")
    result.resources.roots.add VextResourceNode(
      path: GimpPaletteResourcePath, typeId: GimpPaletteTypeId,
      kind: vrnkPalette, palette: source.palette, metadata: metadata)
  of vhkAseprite:
    let source = parsedValue[AsepriteSource](selectedParsed, vhkAseprite)
    var metadata = @[
      integerMetadata("width", source.width),
      integerMetadata("height", source.height),
      integerMetadata("frames", source.frames),
      integerMetadata("colour-depth", source.colourDepth),
      integerMetadata("chunks", source.chunkCount),
      integerMetadata("palette-chunks", source.paletteChunkCount),
      integerMetadata("transparent-index", source.transparentIndex),
      integerMetadata("declared-colours", source.declaredColours)]
    if source.palette.colours.len == 0:
      result.resources.roots.add VextResourceNode(path: "/sprite",
        typeId: AsepriteTypeId, kind: vrnkOpaque, metadata: metadata)
    else:
      metadata.add integerMetadata("colours", source.palette.colours.len)
      result.resources.roots.add VextResourceNode(
        path: AsepritePaletteResourcePath, typeId: AsepriteTypeId,
        kind: vrnkPalette, palette: source.palette, metadata: metadata)
  of vhkAdobeSwatchExchange:
    let source = parsedValue[AdobeSwatchExchange](selectedParsed,
      vhkAdobeSwatchExchange)
    var metadata = @[
      integerMetadata("version.major", source.versionMajor),
      integerMetadata("version.minor", source.versionMinor),
      integerMetadata("blocks", source.blockCount),
      integerMetadata("rgb-colours", source.rgbColourCount),
      integerMetadata("unsupported-colours", source.unsupportedColourCount)]
    if source.palette.colours.len == 0:
      result.resources.roots.add VextResourceNode(path: "/swatches",
        typeId: AdobeSwatchExchangeTypeId, kind: vrnkOpaque,
        metadata: metadata)
    else:
      metadata.add integerMetadata("colours", source.palette.colours.len)
      result.resources.roots.add VextResourceNode(
        path: AdobeSwatchExchangeResourcePath,
        typeId: AdobeSwatchExchangeTypeId, kind: vrnkPalette,
        palette: source.palette, metadata: metadata)
  of vhkProtrackerMod:
    let source = parsedValue[ProtrackerMod](selectedParsed, vhkProtrackerMod)
    let module = VextResourceNode(path: ProtrackerModResourcePath,
      typeId: ProtrackerModTypeId, kind: vrnkTracker,
      defaultExportPriority: 10,
      tracker: source.module,
      trackerSampleResourcePath: ProtrackerModResourcePath & "/samples",
      metadata: @[
        stringMetadata("title", source.module.title),
        stringMetadata("signature", source.signature),
        integerMetadata("sample-headers", source.sampleCount),
        integerMetadata("channels", source.module.channels.len),
        integerMetadata("patterns", source.module.patterns.len),
        integerMetadata("orders", source.module.orders.len),
        integerMetadata("instruments", source.module.instruments.len),
        integerMetadata("loop-analysis", ord(source.module.loopAnalysis.status))])
    let patterns = VextResourceNode(
      path: ProtrackerModResourcePath & "/patterns",
      typeId: "protracker.patterns", kind: vrnkGroup,
      metadata: @[integerMetadata("patterns", source.module.patterns.len)])
    for pattern in source.module.patterns:
      var patternModule = source.module
      patternModule.title = pattern.name
      patternModule.patterns = @[pattern]
      patternModule.orders = @[0]
      patternModule.hasRestartOrder = false
      patternModule.restartOrder = 0
      patternModule.loopAnalysis = VextTrackerLoopAnalysis(
        status: vtlsNotAnalysed)
      patterns.children.add VextResourceNode(
        path: ProtrackerModResourcePath & "/patterns/" &
          $pattern.sourceIndex,
        typeId: "protracker.pattern", kind: vrnkTracker,
        tracker: patternModule,
        trackerSampleResourcePath: ProtrackerModResourcePath & "/samples",
        metadata: @[
          integerMetadata("source-index", pattern.sourceIndex),
          integerMetadata("rows", pattern.rows.len),
          integerMetadata("channels", source.module.channels.len)])
    module.children.add patterns
    let samples = VextResourceNode(
      path: ProtrackerModResourcePath & "/samples",
      typeId: "protracker.samples", kind: vrnkGroup,
      metadata: @[integerMetadata("samples", source.module.instruments.len)])
    for index, instrument in source.module.instruments:
      samples.children.add VextResourceNode(
        path: ProtrackerModResourcePath & "/samples/" & $(index + 1),
        typeId: "protracker.sample", kind: vrnkAudio,
        audioKind: varkSampledInstrument, instrument: instrument.sample,
        metadata: @[
          stringMetadata("name", instrument.name),
          integerMetadata("source-index", instrument.sourceIndex),
          integerMetadata("reference-note", instrument.referenceNote),
          integerMetadata("fine-tune-eighth-semitones",
            int(instrument.fineTuneCents / 12.5)),
          integerMetadata("samples", instrument.sample.sound.buffer.sampleCount),
          integerMetadata("one-shot-samples", instrument.sample.oneShotSamples),
          integerMetadata("repeat-samples", instrument.sample.repeatSamples)])
    module.children.add samples
    let replayModule = source.module
    module.children.add VextResourceNode(
      path: ProtrackerModResourcePath & "/rendered-audio",
      typeId: "protracker.rendered-audio", kind: vrnkAudio,
      audioKind: varkSound,
      soundMaterializer: proc(): VextSound =
        renderProtracker(replayModule).sound,
      derivedAudioChannels: 2, derivedAudioBitsPerSample: 16,
      derivedAudioSampleRate: ProtrackerReplaySampleRate,
      derivedAudioMaximumSamples: ProtrackerReplaySampleRate *
        MaximumProtrackerReplaySeconds,
      metadata: @[
        integerMetadata("sample-rate", ProtrackerReplaySampleRate),
        integerMetadata("channels", 2),
        integerMetadata("bits-per-sample", 16),
        stringMetadata("rendering", "derived on demand"),
        integerMetadata("maximum-seconds", MaximumProtrackerReplaySeconds)])
    result.resources.roots.add module
  of vhkDoomWad:
    let wad = parsedValue[DoomWad](selectedParsed, vhkDoomWad)
    let root = VextResourceNode(path: "/wad", typeId: DoomWadTypeId,
      kind: vrnkGroup, metadata: @[
        stringMetadata("wad.kind", wad.kind.doomWadKindName),
        integerMetadata("wad.entries", wad.entries.len),
        integerMetadata("wad.directory-offset", wad.directoryOffset)])
    let lumps = VextResourceNode(path: "/wad/lumps", typeId: DoomWadTypeId,
      kind: vrnkGroup)
    root.children.add lumps

    let textures = VextResourceNode(path: "/wad/textures",
      typeId: DoomWadTextureDirectoryTypeId, kind: vrnkGroup)
    let sounds = VextResourceNode(path: "/wad/sounds",
      typeId: DoomWadSoundTypeId, kind: vrnkGroup)
    let sprites = VextResourceNode(path: "/wad/sprites",
      typeId: DoomWadPatchTypeId, kind: vrnkGroup)

    var patchNames: seq[string]
    var patchNamesEntry = -1
    var patchNamesError = ""
    for index, entry in wad.entries:
      if entry.name.toUpperAscii == "PNAMES": patchNamesEntry = index
    if patchNamesEntry >= 0:
      try:
        patchNames = parseDoomPatchNames(
          wad.entries[patchNamesEntry].entryBytes(data))
      except ValueError as error:
        patchNamesError = error.msg

    var paletteZero: seq[VextRgb]
    for entry in wad.entries:
      if entry.name == "PLAYPAL":
        try:
          let palettes = decodeDoomPalettes(entry.entryBytes(data))
          for colour in palettes[0].colours: paletteZero.add colour.rgb
          break
        except ValueError:
          discard

    var inFlats = false
    var inSprites = false
    const nonPictureNames = ["COLORMAP", "ENDOOM", "TEXTURE1", "TEXTURE2",
      "PNAMES", "GENMIDI", "DMXGUS", "THINGS", "LINEDEFS", "SIDEDEFS",
      "VERTEXES", "SEGS", "SSECTORS", "NODES", "SECTORS", "REJECT",
      "BLOCKMAP", "BEHAVIOR"]
    for index, entry in wad.entries:
      let safeName = entry.name.replace("/", "_").replace("\\", "_")
      let path = "/wad/lumps/" & $index & "-" & safeName
      let lumpData = entry.entryBytes(data)
      let upperName = entry.name.toUpperAscii
      let commonMetadata = @[
        integerMetadata("wad.index", index),
        stringMetadata("wad.name", entry.name),
        integerMetadata("wad.offset", entry.offset),
        integerMetadata("wad.size", entry.size)]
      if entry.name == "F_START":
        inFlats = true
      elif entry.name == "F_END":
        inFlats = false
      if upperName in ["S_START", "SS_START"]:
        inSprites = true
      elif upperName in ["S_END", "SS_END"]:
        inSprites = false

      if entry.name == "PLAYPAL":
        try:
          let palettes = decodeDoomPalettes(lumpData)
          let group = VextResourceNode(path: path,
            typeId: DoomWadPaletteTypeId, kind: vrnkGroup,
            metadata: commonMetadata)
          for paletteIndex, palette in palettes:
            group.children.add VextResourceNode(
              path: path & "/palette-" & $paletteIndex,
              typeId: DoomWadPaletteTypeId, kind: vrnkPalette,
              palette: palette, metadata: @[
                integerMetadata("wad.palette-index", paletteIndex)])
          lumps.children.add group
        except ValueError as error:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true, failureFormat: DoomWadPaletteTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          result.warnings.add VextInspectionWarning(path: path,
            format: DoomWadPaletteTypeId, message: error.msg)
      elif index == patchNamesEntry and patchNamesError.len > 0:
        lumps.children.add VextResourceNode(path: path,
          typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
          rawDataAvailable: true, failureFormat: DoomWadTextureDirectoryTypeId,
          failureMessage: patchNamesError, metadata: commonMetadata)
        result.warnings.add VextInspectionWarning(path: path,
          format: DoomWadTextureDirectoryTypeId, message: patchNamesError)
      elif upperName.startsWith("DS") and upperName.len > 2:
        let soundPath = "/wad/sounds/" & $index & "-" & safeName
        try:
          let sound = parseDoomSound(lumpData)
          let soundMetadata = commonMetadata & @[
            integerMetadata("sound.format", sound.format),
            integerMetadata("sound.sample-rate", sound.sampleRate),
            integerMetadata("sound.samples", sound.declaredSamples),
            integerMetadata("sound.reserved", sound.reserved),
            integerMetadata("sound.duration-ms",
              sound.declaredSamples * 1000 div sound.sampleRate)]
          let decoded = decodeDoomSound(sound)
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadSoundTypeId, kind: vrnkAudio,
            audioKind: varkSound, sound: decoded, metadata: soundMetadata)
          sounds.children.add VextResourceNode(path: soundPath,
            typeId: DoomWadSoundTypeId, kind: vrnkAudio,
            audioKind: varkSound, sound: decoded, metadata: soundMetadata)
        except ValueError as error:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true, failureFormat: DoomWadSoundTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          sounds.children.add VextResourceNode(path: soundPath,
            typeId: DoomWadSoundTypeId, kind: vrnkOpaque,
            failureFormat: DoomWadSoundTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          result.warnings.add VextInspectionWarning(path: path,
            format: DoomWadSoundTypeId, message: error.msg)
      elif entry.name in ["TEXTURE1", "TEXTURE2"]:
        try:
          let directory = parseDoomTextureDirectory(lumpData)
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true, metadata: commonMetadata & @[
              integerMetadata("wad.textures", directory.textures.len)])
          let directoryGroup = VextResourceNode(
            path: "/wad/textures/" & $index & "-" & entry.name,
            typeId: DoomWadTextureDirectoryTypeId, kind: vrnkGroup,
            metadata: commonMetadata)
          for textureIndex, texture in directory.textures:
            let texturePath = directoryGroup.path & "/" & $textureIndex &
              "-" & texture.name.replace("/", "_").replace("\\", "_")
            var metadata = @[
              stringMetadata("texture.directory", entry.name),
              integerMetadata("texture.index", textureIndex),
              stringMetadata("texture.name", texture.name),
              integerMetadata("texture.width", texture.width),
              integerMetadata("texture.height", texture.height),
              integerMetadata("texture.masked", int(texture.masked)),
              integerMetadata("texture.column-directory",
                int(texture.columnDirectory)),
              integerMetadata("texture.patches", texture.patches.len)]
            var resolved: seq[DoomPatch]
            var resolutionError = ""
            for placementIndex, placement in texture.patches:
              let key = "texture.patch." & $placementIndex
              metadata.add integerMetadata(key & ".origin-x", placement.originX)
              metadata.add integerMetadata(key & ".origin-y", placement.originY)
              metadata.add integerMetadata(key & ".pname-index",
                placement.patchIndex)
              metadata.add integerMetadata(key & ".step-direction",
                placement.stepDirection)
              metadata.add integerMetadata(key & ".colour-map",
                placement.colourMap)
              if placement.patchIndex < 0 or
                  placement.patchIndex >= patchNames.len:
                if resolutionError.len == 0:
                  resolutionError = "texture patch index " &
                    $placement.patchIndex & " is outside PNAMES"
                continue
              let patchName = patchNames[placement.patchIndex]
              metadata.add stringMetadata(key & ".name", patchName)
              var lumpIndex = -1
              for candidateIndex in countdown(wad.entries.high, 0):
                if wad.entries[candidateIndex].name.toUpperAscii ==
                    patchName.toUpperAscii:
                  lumpIndex = candidateIndex
                  break
              if lumpIndex < 0:
                if resolutionError.len == 0:
                  resolutionError = "texture patch lump is missing: " & patchName
                continue
              metadata.add integerMetadata(key & ".lump-index", lumpIndex)
              try:
                resolved.add parseDoomPatch(wad.entries[lumpIndex].entryBytes(data))
              except ValueError as error:
                if resolutionError.len == 0:
                  resolutionError = "invalid texture patch " & patchName &
                    ": " & error.msg
            if paletteZero.len != DoomPaletteColours and resolutionError.len == 0:
              resolutionError = "texture cannot render without a valid PLAYPAL"
            if resolved.len != texture.patches.len and resolutionError.len == 0:
              resolutionError = "one or more texture patches could not be resolved"
            if resolutionError.len > 0:
              directoryGroup.children.add VextResourceNode(path: texturePath,
                typeId: DoomWadTextureTypeId, kind: vrnkOpaque,
                failureFormat: DoomWadTextureTypeId,
                failureMessage: resolutionError, metadata: metadata)
              result.warnings.add VextInspectionWarning(path: texturePath,
                format: DoomWadTextureTypeId, message: resolutionError)
            else:
              directoryGroup.children.add VextResourceNode(path: texturePath,
                typeId: DoomWadTextureTypeId, kind: vrnkRaster,
                raster: VextRaster(kind: vrkIndexedImage,
                  image: composeDoomTexture(texture, resolved, paletteZero)),
                metadata: metadata)
          textures.children.add directoryGroup
        except ValueError as error:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true,
            failureFormat: DoomWadTextureDirectoryTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          result.warnings.add VextInspectionWarning(path: path,
            format: DoomWadTextureDirectoryTypeId, message: error.msg)
      elif inFlats and entry.name != "F_START" and entry.name != "F_END" and
          paletteZero.len == DoomPaletteColours:
        try:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadFlatTypeId, kind: vrnkRaster,
            raster: VextRaster(kind: vrkIndexedImage,
              image: decodeDoomFlat(lumpData, paletteZero)),
            metadata: commonMetadata)
        except ValueError as error:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true, failureFormat: DoomWadFlatTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          result.warnings.add VextInspectionWarning(path: path,
            format: DoomWadFlatTypeId, message: error.msg)
      elif inSprites and upperName notin ["S_START", "SS_START",
          "S_END", "SS_END"]:
        let spritePath = "/wad/sprites/" & $index & "-" & safeName
        try:
          if paletteZero.len != DoomPaletteColours:
            raise newException(ValueError,
              "sprite cannot render without a valid PLAYPAL")
          let patch = parseDoomPatch(lumpData)
          let spriteMetadata = commonMetadata & @[
            integerMetadata("position.left-offset", patch.leftOffset),
            integerMetadata("position.top-offset", patch.topOffset)]
          let decoded = decodeDoomPatch(patch, paletteZero)
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadPatchTypeId, kind: vrnkRaster,
            raster: VextRaster(kind: vrkIndexedImage, image: decoded),
            metadata: spriteMetadata)
          sprites.children.add VextResourceNode(path: spritePath,
            typeId: DoomWadPatchTypeId, kind: vrnkRaster,
            raster: VextRaster(kind: vrkIndexedImage, image: decoded),
            metadata: spriteMetadata)
        except ValueError as error:
          lumps.children.add VextResourceNode(path: path,
            typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
            rawDataAvailable: true, failureFormat: DoomWadPatchTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          sprites.children.add VextResourceNode(path: spritePath,
            typeId: DoomWadPatchTypeId, kind: vrnkOpaque,
            failureFormat: DoomWadPatchTypeId,
            failureMessage: error.msg, metadata: commonMetadata)
          result.warnings.add VextInspectionWarning(path: path,
            format: DoomWadPatchTypeId, message: error.msg)
      elif paletteZero.len == DoomPaletteColours and entry.size > 0 and
          entry.name notin nonPictureNames and
          not entry.name.startsWith("DS") and not entry.name.startsWith("DP") and
          not entry.name.startsWith("D_") and
          not entry.name.startsWith("DEMO") and isDoomPatch(lumpData):
        let patch = parseDoomPatch(lumpData)
        lumps.children.add VextResourceNode(path: path,
          typeId: DoomWadPatchTypeId, kind: vrnkRaster,
          raster: VextRaster(kind: vrkIndexedImage,
            image: decodeDoomPatch(patch, paletteZero)),
          metadata: commonMetadata & @[
            integerMetadata("position.left-offset", patch.leftOffset),
            integerMetadata("position.top-offset", patch.topOffset)])
      else:
        lumps.children.add VextResourceNode(path: path,
          typeId: DoomWadLumpTypeId, kind: vrnkOpaque, data: lumpData,
          rawDataAvailable: true, metadata: commonMetadata)
    if textures.children.len > 0:
      root.children.add textures
    if sounds.children.len > 0:
      root.children.add sounds
    if sprites.children.len > 0:
      root.children.add sprites

    let maps = VextResourceNode(path: "/wad/maps",
      typeId: DoomWadAutomapTypeId, kind: vrnkGroup)
    for markerIndex, marker in wad.entries:
      if marker.size != 0 or not marker.name.isDoomMapMarker: continue
      var mapLumps = initTable[string, int]()
      var scan = markerIndex + 1
      while scan < wad.entries.len and wad.entries[scan].name.isDoomMapLumpName:
        mapLumps[wad.entries[scan].name.toUpperAscii] = scan
        inc scan
      let mapPath = "/wad/maps/" & $markerIndex & "-" &
        marker.name.replace("/", "_").replace("\\", "_")
      var metadata = @[
        stringMetadata("map.name", marker.name),
        integerMetadata("map.marker-index", markerIndex),
        integerMetadata("map.lumps", mapLumps.len)]
      const mapRecordSizes = [
        (name: "THINGS", size: 10), (name: "LINEDEFS", size: 14),
        (name: "SIDEDEFS", size: 30), (name: "VERTEXES", size: 4),
        (name: "SEGS", size: 12), (name: "SSECTORS", size: 4),
        (name: "NODES", size: 28), (name: "SECTORS", size: 26)]
      for item in mapRecordSizes:
        if mapLumps.hasKey(item.name):
          let entry = wad.entries[mapLumps[item.name]]
          let key = "map.lump." & item.name.toLowerAscii
          metadata.add integerMetadata(key & ".index", mapLumps[item.name])
          metadata.add integerMetadata(key & ".bytes", entry.size)
          if entry.size mod item.size == 0:
            metadata.add integerMetadata(key & ".records", entry.size div item.size)
      for name in ["REJECT", "BLOCKMAP"]:
        if mapLumps.hasKey(name):
          let entry = wad.entries[mapLumps[name]]
          let key = "map.lump." & name.toLowerAscii
          metadata.add integerMetadata(key & ".index", mapLumps[name])
          metadata.add integerMetadata(key & ".bytes", entry.size)

      let mapGroup = VextResourceNode(path: mapPath,
        typeId: DoomWadAutomapTypeId, kind: vrnkGroup, metadata: metadata)
      let previewPath = mapPath & "/automap"
      try:
        if not mapLumps.hasKey("VERTEXES") or
            not mapLumps.hasKey("LINEDEFS"):
          raise newException(ValueError,
            "automap requires VERTEXES and LINEDEFS lumps")
        var source = DoomAutomapSource()
        source.vertices = parseDoomMapVertices(
          wad.entries[mapLumps["VERTEXES"]].entryBytes(data))
        source.lines = parseDoomMapLines(
          wad.entries[mapLumps["LINEDEFS"]].entryBytes(data),
          source.vertices.len)
        if source.vertices.len == 0:
          raise newException(ValueError,
            "automap requires at least one vertex")
        if source.lines.len == 0:
          raise newException(ValueError,
            "automap requires at least one linedef")
        if mapLumps.hasKey("SIDEDEFS") and mapLumps.hasKey("SECTORS"):
          source.sides = parseDoomMapSides(
            wad.entries[mapLumps["SIDEDEFS"]].entryBytes(data))
          source.sectors = parseDoomMapSectors(
            wad.entries[mapLumps["SECTORS"]].entryBytes(data))
          source.validateDoomMapReferences()
        var minX = source.vertices[0].x
        var maxX = minX
        var minY = source.vertices[0].y
        var maxY = minY
        for vertex in source.vertices:
          minX = min(minX, vertex.x)
          maxX = max(maxX, vertex.x)
          minY = min(minY, vertex.y)
          maxY = max(maxY, vertex.y)
        metadata.add integerMetadata("map.bounds.minimum-x", minX)
        metadata.add integerMetadata("map.bounds.maximum-x", maxX)
        metadata.add integerMetadata("map.bounds.minimum-y", minY)
        metadata.add integerMetadata("map.bounds.maximum-y", maxY)
        var hiddenLines = 0
        for line in source.lines:
          if (line.flags and (1 shl 7)) != 0: inc hiddenLines
        metadata.add integerMetadata("map.hidden-linedefs", hiddenLines)
        mapGroup.metadata = metadata
        mapGroup.children.add VextResourceNode(path: previewPath,
          typeId: DoomWadAutomapTypeId, kind: vrnkRaster,
          raster: VextRaster(kind: vrkTrueColourImage,
            trueColourImage: renderDoomAutomap(source)), metadata: metadata)
      except ValueError as error:
        mapGroup.children.add VextResourceNode(path: previewPath,
          typeId: DoomWadAutomapTypeId, kind: vrnkOpaque,
          failureFormat: DoomWadAutomapTypeId,
          failureMessage: error.msg, metadata: metadata)
        result.warnings.add VextInspectionWarning(path: previewPath,
          format: DoomWadAutomapTypeId, message: error.msg)
      maps.children.add mapGroup
    if maps.children.len > 0:
      root.children.add maps
    result.resources.roots.add root
  of vhkZip:
    let archive = parsedValue[ZipArchive](selectedParsed, vhkZip)
    let zipSource = if backingSource.isNil:
        VextPayloadSource(data: @data)
      else:
        backingSource
    let root = VextResourceNode(path: "/archive", typeId: ZipArchiveTypeId,
      kind: vrnkGroup, metadata: @[
        integerMetadata("entries", archive.entries.len),
        stringMetadata("comment", archive.comment)])
    var directories = {root.path: root}.toTable
    for entry in archive.entries:
      addZipEntry(root, entry, zipSource, directories)
    result.resources.roots.add root
  of vhkIso9660:
    let image = parsedValueRef[Iso9660Image](selectedParsed, vhkIso9660)
    let isoSource = if backingSource.isNil:
        VextPayloadSource(data: @data)
      else:
        backingSource
    var metadata = @[
      stringMetadata("layout", image[].layout.iso9660LayoutName),
      stringMetadata("volume.identifier", image[].volumeIdentifier),
      stringMetadata("system.identifier", image[].systemIdentifier),
      stringMetadata("volume-set.identifier", image[].volumeSetIdentifier),
      stringMetadata("publisher.identifier", image[].publisherIdentifier),
      stringMetadata("preparer.identifier", image[].preparerIdentifier),
      stringMetadata("application.identifier", image[].applicationIdentifier),
      stringMetadata("volume.created", image[].creationTime),
      stringMetadata("volume.modified", image[].modificationTime),
      integerMetadata("logical-block-size", image[].logicalBlockSize),
      integerMetadata("volume.blocks", image[].volumeBlocks),
      integerMetadata("entries", image[].entries.len),
      integerMetadata("descriptors.primary", image[].primaryDescriptorCount),
      integerMetadata("descriptors.supplementary",
        image[].supplementaryDescriptorCount),
      integerMetadata("descriptors.boot", image[].bootDescriptorCount),
      integerMetadata("descriptors.partition", image[].partitionDescriptorCount)]
    let root = VextResourceNode(path: "/disc", typeId: Iso9660TypeId,
      kind: vrnkGroup, metadata: metadata)
    var directories = {root.path: root}.toTable
    var inspectionFiles, inspectionBytes: int
    # Large filesystems are presented structurally first. Eagerly decoding even
    # a bounded prefix can expand compressed images and archives far beyond the
    # source size; demand-driven nested decoding is the next layer above these
    # lazy payload references.
    if image[].entries.len > 512:
      inspectionFiles = 512
    for entry in image[].entries.mitems:
      addIso9660Entry(root, entry, data, isoSource, image, depth,
        ignoreWarnings, pcxChannelOrder,
        result.warnings, directories, inspectionFiles, inspectionBytes)
    result.resources.roots.add root
  of vhkOpenRaster:
    let document = parsedValue[OpenRasterDocument](selectedParsed,
      vhkOpenRaster)
    result.resources.roots.add VextResourceNode(path: "/image",
      typeId: OpenRasterImageTypeId, kind: vrnkRaster,
      raster: decodePngOrApng(document.mergedImage),
      defaultExportPriority: 100, metadata: @[
        stringMetadata("role", "canonical merged image"),
        integerMetadata("canvas.width", document.width),
        integerMetadata("canvas.height", document.height)])
    result.resources.roots.add VextResourceNode(path: "/thumbnail",
      typeId: OpenRasterThumbnailTypeId, kind: vrnkRaster,
      raster: decodePngOrApng(document.thumbnail), metadata: @[
        stringMetadata("role", "document thumbnail")])
    let layers = openRasterElementNode(document.stack, "/layers")
    layers.metadata.add @[
      stringMetadata("openraster.version", document.version),
      stringMetadata("document.name", document.name),
      integerMetadata("canvas.width", document.width),
      integerMetadata("canvas.height", document.height),
      integerMetadata("resolution.x", document.xResolution),
      integerMetadata("resolution.y", document.yResolution)]
    result.resources.roots.add layers
  of vhkLha:
    let archive = parsedValue[LhaArchive](selectedParsed, vhkLha)
    let root = VextResourceNode(path: "/archive", typeId: LhaArchiveTypeId,
      kind: vrnkGroup, metadata: @[
        integerMetadata("entries", archive.entries.len)])
    for entry in archive.entries:
      addLhaEntry(root, entry, depth, ignoreWarnings, pcxChannelOrder,
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
    if not image.hasBitmap:
      let rgbColours = decodeAmigaIlbmPalette(image)
      var colours: seq[VextRgba]
      for colour in rgbColours: colours.add colour.rgba
      var cycles: seq[VextColourCycleRange]
      for cycle in image.colourCycles:
        if cycle.low >= 0 and cycle.high < colours.len and
            cycle.low < cycle.high and cycle.direction in [-1, 1] and
            cycle.stepDurationMs > 0 and cycles.len < 6:
          cycles.add cycle
      result.resources.roots.add VextResourceNode(
        path: "/palette", typeId: "amiga.iff-palette",
        kind: vrnkPalette,
        palette: VextPalette(colours: colours, colourCycles: cycles),
        metadata: @[
          integerMetadata("colours", image.colourMap.len div 3),
          integerMetadata("colour-cycle-ranges", cycles.len),
          integerMetadata("camg", int(image.camg))])
      return
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
    ansiLetterSpacing = alsAuto,
    ansiAspect = apaAuto,
    progress: VextProgressCallback = nil,
    companionResolver: VextCompanionResolver = nil): VextInspection =
  reportProgress(progress, vppDetecting, filename, "Detecting input format")
  reportProgress(progress, vppInspecting, filename, "Inspecting container")
  reportProgress(progress, vppDecoding, filename, "Decoding resources")
  result = inspectSourceDepth(filename, data, inputFormat, 0, ignoreWarnings,
    pcxChannelOrder, ansiLetterSpacing, ansiAspect, companionResolver, nil)
  reportProgress(progress, vppTraversing, filename,
    "Resource tree complete", result.resources.leafResources.len,
    result.resources.leafResources.len)
  reportProgress(progress, vppComplete, filename, "Inspection complete", 1, 1)

proc inspectOwnedSource*(filename: string, ownedData: sink seq[byte],
    inputFormat = "", ignoreWarnings = false,
    pcxChannelOrder = pcoRgb,
    ansiLetterSpacing = alsAuto,
    ansiAspect = apaAuto,
    progress: VextProgressCallback = nil,
    companionResolver: VextCompanionResolver = nil): VextInspection =
  ## Ownership-preserving inspection for frontends loading large containers.
  ## Lazy resources keep this one shared source alive without copying it.
  let source = VextPayloadSource(data: move(ownedData))
  reportProgress(progress, vppDetecting, filename, "Detecting input format")
  reportProgress(progress, vppInspecting, filename, "Inspecting container")
  reportProgress(progress, vppDecoding, filename, "Decoding resources")
  result = inspectSourceDepth(filename, source.data, inputFormat, 0,
    ignoreWarnings, pcxChannelOrder, ansiLetterSpacing, ansiAspect,
    companionResolver, source)
  let leaves = result.resources.leafResources.len
  reportProgress(progress, vppTraversing, filename,
    "Resource tree complete", leaves, leaves)
  reportProgress(progress, vppComplete, filename, "Inspection complete", 1, 1)

proc decodeResourceOnDemand*(node: VextResourceNode,
    ignoreWarnings = true, pcxChannelOrder = pcoRgb): VextDemandDecodeResult =
  ## Probes and decodes one lazy opaque resource. This mutates the stable node
  ## in place so frontends can retain their existing selection binding.
  if node.isNil or node.kind != vrnkOpaque or
      node.lazyPayload.source.isNil or node.nestedInspectionAttempted:
    return vddNotApplicable
  node.nestedInspectionAttempted = true
  let filename = node.path.split('/')[^1]
  var data: seq[byte]
  try:
    data = node.resourceBytes
  except CatchableError as error:
    node.failureFormat = node.typeId
    node.failureMessage = error.msg
    node.metadata.add stringMetadata("decode.warning", error.msg)
    return vddFailed
  var candidates: seq[VextDetectionCandidate]
  try:
    candidates = detectFormats(filename, data)
  except CatchableError as error:
    node.failureFormat = "recognized contained format"
    node.failureMessage = error.msg
    node.metadata.add stringMetadata("decode.warning", error.msg)
    return vddFailed
  if candidates.len == 0:
    node.metadata.add stringMetadata("decode.status", "format not recognized")
    return vddUnrecognized
  try:
    let nested = inspectSourceDepth(filename, data, "", 1, ignoreWarnings,
      pcxChannelOrder, alsAuto, apaAuto, nil)
    node.typeId = nested.selectedFormat.typeId
    node.kind = vrnkGroup
    node.metadata.add stringMetadata("decode.format", node.typeId)
    node.metadata.add stringMetadata("decode.status", "decoded on demand")
    for root in nested.resources.roots:
      rebaseNode(root, node.path)
      node.children.add root
    result = vddDecoded
  except CatchableError as error:
    node.failureFormat = candidates[0].typeId
    node.failureMessage = error.msg
    node.metadata.add stringMetadata("decode.format", candidates[0].typeId)
    node.metadata.add stringMetadata("decode.warning", error.msg)
    result = vddFailed

proc exportResource*(tree: VextResourceTree,
    request: VextExportRequest): VextExportResult =
  var available: seq[VextResourceNode]
  if request.outputFormat in ["metadata-json", "html-report"]:
    available = tree.allResources
  else:
    for item in tree.leafResources:
      if item.kind in {vrnkRaster, vrnkText, vrnkAudio, vrnkFont, vrnkPalette,
          vrnkTracker} or
          (item.kind == vrnkOpaque and item.rawDataAvailable):
        available.add item
  var resource: VextResourceNode
  if request.resourcePath.len > 0:
    for item in available:
      if item.path == request.resourcePath:
        resource = item
        break
    if resource.isNil:
      for item in tree.allResources:
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
  if result.outputFormat == "metadata-json":
    result.artifacts = exportMetadataJson(resource,
      request.suggestedName & ".json")
    return
  if result.outputFormat == "html-report":
    result.artifacts = exportHtmlReport(resource,
      request.suggestedName & ".html")
    return
  if result.outputFormat in ["palette-swatch", "gpl"]:
    let palette = case resource.kind
      of vrnkPalette: resource.palette
      of vrnkRaster:
        case resource.raster.kind
        of vrkIndexedImage: paletteOf(resource.raster.image)
        of vrkIndexedAnimation: paletteOf(resource.raster.animation)
        else: raise newException(ValueError,
          "palette export requires indexed colour")
      else: raise newException(ValueError,
        "palette export requires a palette or indexed raster")
    if result.outputFormat == "palette-swatch":
      result.artifacts = exportPng(renderPaletteSwatch(palette),
        request.suggestedName & ".png")
    else:
      result.artifacts = exportGpl(palette, request.suggestedName,
        request.suggestedName & ".gpl")
      if palette.colourCycles.len > 0:
        result.warnings.add "GPL cannot preserve colour-cycle ranges."
    return
  case resource.kind
  of vrnkOpaque:
    if not resource.rawDataAvailable:
      raise newException(ValueError, "resource is not exportable: " &
        resource.path)
    if result.outputFormat != "bin":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    result.artifacts = exportRaw(resource.resourceBytes,
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
  of vrnkFont:
    if result.outputFormat != "bmfont":
      raise newException(ValueError,
        "unsupported output format: " & result.outputFormat)
    result.warnings = bmFontLossWarnings(resource.font)
    result.artifacts = exportBmFont(resource.font, request.suggestedName)
  of vrnkPalette:
    raise newException(ValueError, "unsupported output format: " &
      result.outputFormat)
  of vrnkTracker:
    if result.outputFormat != "tracker-json":
      raise newException(ValueError, "unsupported output format: " &
        result.outputFormat)
    result.artifacts = exportTrackerJson(resource.tracker, resource.path,
      request.suggestedName & ".json", resource.trackerSampleResourcePath)
  else:
    raise newException(ValueError, "resource is not exportable: " &
      resource.path)

proc exportAllResources*(tree: VextResourceTree,
    request: VextExportAllRequest): VextExportAllResult =
  var patterns: seq[seq[string]]
  for pattern in request.resourcePatterns:
    patterns.add validateResourcePattern(pattern)

  var selected: seq[VextResourceNode]
  let candidates = if request.outputFormat in ["metadata-json", "html-report"]:
      tree.allResources else: tree.leafResources
  for resource in candidates:
    if request.outputFormat notin ["metadata-json", "html-report"] and
        not (resource.kind in {vrnkRaster, vrnkText, vrnkAudio, vrnkFont,
          vrnkPalette, vrnkTracker} or
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
    let baseName = exportNameForPath(resource.path)
    var suffix = 1
    var exported: VextExportResult
    while true:
      exported = exportResource(tree, VextExportRequest(
        resourcePath: resource.path,
        outputFormat: request.outputFormat,
        suggestedName: suffixedExportName(baseName, suffix),
        colourCycleFrameLimit: request.colourCycleFrameLimit,
        allowLargeAnimation: request.allowLargeAnimation))
      var collision = false
      for artifact in exported.artifacts.artifacts:
        for used in usedNames:
          if artifact.suggestedFilename.toLowerAscii == used.toLowerAscii:
            collision = true
      if not collision: break
      inc suffix
    for artifact in exported.artifacts.artifacts:
      usedNames.add artifact.suggestedFilename
    result.exports.add exported
