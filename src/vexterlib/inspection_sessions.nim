## Incremental inspection sessions over random-access source collections.

import std/[hashes, sets, strutils, tables]
import ./byte_sources
import ./archetypes/raster
import ./archetypes/audio
import ./detection
import ./format_detection_types
import ./metadata
import ./operations
import ./resource_tree
import ./containers/[amiga_adf, amiga_dms, appimage, electron_asar, iso9660, lha_archive, openraster,
  powerpacker, xpk_shri, zip_archive]
import ./resources/[ansi_art_image, pcx_image]

type
  VextResourceId* = distinct uint64

  VextResourceCapability* = enum
    vrcEnumerateChildren
    vrcMaterializePayload
    vrcProbeNested
    vrcDecodeRepresentation
    ## The resource is a container root whose hierarchy can be extracted.
    vrcExtractTree

  VextValidationLevel* = enum
    vvlStructural
    vvlManifest
    vvlPayload
    vvlRepresentation

  VextResourceDescriptor* = object
    id*: VextResourceId
    path*: string
    typeId*: string
    kind*: VextResourceNodeKind
    capabilities*: set[VextResourceCapability]
    validatedThrough*: VextValidationLevel
    estimatedBytes*: int
    metadata*: seq[VextMetadataEntry]
    failureFormat*: string
    failureMessage*: string
    archetype*: string
    width*, height*, frames*: int
    channels*, bitsPerSample*, sampleRate*, samples*: int
    glyphs*, characters*, lineHeight*, baseline*: int
    colours*, colourCycleRanges*: int

  VextWorkLimits* = object
    maximumDepth*: int
    maximumResources*: int
    maximumManifestBytes*: int
    maximumWorkingBytes*: int

  VextProgressTotalState* = enum
    vptsUnknown
    vptsGrowing
    vptsFinal

  VextSessionProgressPhase* = enum
    vsppDetecting
    vsppIndexing
    vsppValidatingManifest
    vsppEnumerating
    vsppMaterializing
    vsppProbing
    vsppDecoding
    vsppExporting
    vsppComplete

  VextSessionProgressEvent* = object
    phase*: VextSessionProgressPhase
    path*: string
    completed*: int
    discovered*: int
    pending*: int
    totalState*: VextProgressTotalState
    message*: string

  VextSessionProgressCallback* = proc(event: VextSessionProgressEvent): bool
    {.closure.}

  VextSessionCancelledError* = object of CatchableError
  VextWorkLimitError* = object of ValueError

  VextResourceDelta* = object
    parent*: VextResourceId
    parentDescriptor*: VextResourceDescriptor
    children*: seq[VextResourceDescriptor]

  VextLoadedResource* = object
    descriptor*: VextResourceDescriptor
    data*: seq[byte]
    resources*: VextResourceTree
    warnings*: seq[VextInspectionWarning]

  VextExtractionEntryKind* = enum
    veekDirectory
    veekFile

  VextExtractionEntry* = object
    kind*: VextExtractionEntryKind
    relativePath*: string
    descriptor*: VextResourceDescriptor

  VextExtractionPlan* = object
    root*: VextResourceDescriptor
    entries*: seq[VextExtractionEntry]
    totalEstimatedBytes*: int64
    warnings*: seq[string]

  VextSessionKind = enum
    vskLegacy
    vskZip
    vskOpenRaster
    vskIso9660
    vskAppImageType1
    vskAppImage
    vskLha
    vskElectronAsar
    vskAmigaAdf
    vskDeferredWrapper

  VextInspectionSession* = ref object
    filename*: string
    sources*: VextSourceCollection
    limits*: VextWorkLimits
    selectedFormat*: VextDetectionCandidate
    candidates*: seq[VextDetectionCandidate]
    warnings*: seq[VextInspectionWarning]
    roots*: seq[VextResourceId]
    kind: VextSessionKind
    nextId: uint64
    descriptors: Table[VextResourceId, VextResourceDescriptor]
    idsByPath: Table[string, VextResourceId]
    children: Table[VextResourceId, seq[VextResourceId]]
    expanded: HashSet[VextResourceId]
    zip: ZipArchive
    manifest: OpenRasterManifest
    zipEntryById: Table[VextResourceId, int]
    manifestSourceById: Table[VextResourceId, string]
    iso: Iso9660Index
    isoSource: VextByteSource
    appImageType1: AppImageType1
    isoEntryById: Table[VextResourceId, Iso9660Entry]
    isoVisited: HashSet[string]
    appImage: AppImageArchive
    appImageEntryById: Table[VextResourceId, int]
    lha: LhaArchive
    lhaEntryById: Table[VextResourceId, int]
    asar: ElectronAsarArchive
    asarEntryById: Table[VextResourceId, int]
    adf: AmigaAdfIndex
    adfEntryById: Table[VextResourceId, AmigaAdfEntry]
    adfVisited: HashSet[int]
    deferredData: seq[byte]
    deferredFormat: string
    deferredRootPath: string
    legacyTree: VextResourceTree
    legacyNodeById: Table[VextResourceId, VextResourceNode]
    closed: bool

proc `==`*(left, right: VextResourceId): bool {.borrow.}
proc hash*(id: VextResourceId): Hash = hash(uint64(id))

proc defaultWorkLimits*(): VextWorkLimits =
  VextWorkLimits(maximumDepth: 8, maximumResources: 200_000,
    maximumManifestBytes: 64 * 1024 * 1024,
    maximumWorkingBytes: 512 * 1024 * 1024)

proc report(callback: VextSessionProgressCallback,
    event: VextSessionProgressEvent) =
  if callback != nil and not callback(event):
    raise newException(VextSessionCancelledError, "operation cancelled")

proc ensureOpen(session: VextInspectionSession) =
  if session.isNil or session.closed:
    raise newException(ValueError, "inspection session is not available")

proc candidate(typeId: string, confidence: VextDetectionConfidence,
    description: string): VextDetectionCandidate =
  VextDetectionCandidate(typeId: typeId, confidence: confidence,
    evidence: @[VextDetectionEvidence(description: description)],
    derivation: baseDerivation(typeId))

proc allocateDescriptor(session: VextInspectionSession, path, typeId: string,
    kind: VextResourceNodeKind,
    capabilities: set[VextResourceCapability],
    validation = vvlStructural, estimatedBytes = 0,
    metadata: seq[VextMetadataEntry] = @[]): VextResourceDescriptor =
  if session.descriptors.len >= session.limits.maximumResources:
    raise newException(VextWorkLimitError,
      "resource count exceeds the inspection limit")
  inc session.nextId
  result = VextResourceDescriptor(id: VextResourceId(session.nextId),
    path: path, typeId: typeId, kind: kind, capabilities: capabilities,
    validatedThrough: validation, estimatedBytes: estimatedBytes,
    metadata: metadata)

proc commit(session: VextInspectionSession,
    descriptor: VextResourceDescriptor) =
  session.descriptors[descriptor.id] = descriptor
  session.idsByPath[descriptor.path] = descriptor.id

proc descriptor*(session: VextInspectionSession,
    id: VextResourceId): VextResourceDescriptor =
  session.ensureOpen()
  if not session.descriptors.hasKey(id):
    raise newException(ValueError, "resource identifier was not found")
  session.descriptors[id]

proc resourceAtPath*(session: VextInspectionSession,
    path: string): VextResourceDescriptor =
  session.ensureOpen()
  let id = session.idsByPath.getOrDefault(path)
  if uint64(id) == 0:
    raise newException(ValueError, "resource was not found: " & path)
  session.descriptors[id]

proc rootDescriptors*(session: VextInspectionSession):
    seq[VextResourceDescriptor] =
  session.ensureOpen()
  for id in session.roots: result.add session.descriptors[id]

proc addLegacyNode(session: VextInspectionSession, node: VextResourceNode,
    parent: VextResourceId) =
  let capabilities = if node.children.len > 0: {vrcEnumerateChildren}
    elif node.kind == vrnkOpaque and node.rawDataAvailable:
      {vrcMaterializePayload, vrcProbeNested}
    else: {vrcDecodeRepresentation}
  let estimatedBytes =
    if node.kind == vrnkAudio and node.soundMaterializer != nil:
      node.derivedAudioMaximumSamples * node.derivedAudioChannels *
        max(1, node.derivedAudioBitsPerSample div 8)
    else: node.retainedByteLength
  let item = session.allocateDescriptor(node.path, node.typeId, node.kind,
    capabilities, vvlRepresentation, estimatedBytes, node.metadata)
  var described = item
  case node.kind
  of vrnkRaster:
    described.archetype = node.raster.archetypeName
    described.width = node.raster.width
    described.height = node.raster.height
    case node.raster.kind
    of vrkIndexedAnimation: described.frames = node.raster.animation.frames.len
    of vrkTrueColourAnimation:
      described.frames = node.raster.trueColourAnimation.frames.len
    else: discard
  of vrnkAudio:
    described.archetype = if node.audioKind == varkSound: "sound"
      else: "sampled-instrument"
    if node.soundMaterializer != nil:
      described.channels = node.derivedAudioChannels
      described.bitsPerSample = node.derivedAudioBitsPerSample
      described.sampleRate = node.derivedAudioSampleRate
    else:
      let sound = node.audioSound
      described.channels = sound.buffer.channels.len
      described.bitsPerSample = sound.buffer.bitsPerSample
      described.sampleRate = sound.sampleRate
      described.samples = sound.buffer.sampleCount
  of vrnkFont:
    described.archetype = "VextBitmapFont"
    described.glyphs = node.font.glyphs.len
    described.characters = node.font.mappings.len
    described.lineHeight = node.font.lineHeight
    described.baseline = node.font.baseline
  of vrnkPalette:
    described.archetype = "VextPalette"
    described.colours = node.palette.colours.len
    described.colourCycleRanges = node.palette.colourCycles.len
  of vrnkTracker:
    described.archetype = "VextTrackerModule"
    described.channels = node.tracker.channels.len
  else: discard
  described.failureFormat = node.failureFormat
  described.failureMessage = node.failureMessage
  session.commit(described)
  session.legacyNodeById[described.id] = node
  if uint64(parent) == 0: session.roots.add described.id
  else: session.children.mgetOrPut(parent, @[]).add described.id
  for child in node.children: session.addLegacyNode(child, described.id)
  session.expanded.incl described.id

proc addManifestElement(session: VextInspectionSession,
    element: OpenRasterManifestElement, path: string,
    parent: VextResourceId) =
  let isStack = element.kind == orekStack
  let item = session.allocateDescriptor(path,
    if isStack: OpenRasterStackTypeId else: OpenRasterLayerTypeId,
    if isStack: vrnkGroup else: vrnkRaster,
    if isStack: {vrcEnumerateChildren}
    else: {vrcMaterializePayload, vrcDecodeRepresentation},
    vvlManifest)
  session.commit(item)
  session.children.mgetOrPut(parent, @[]).add item.id
  if not isStack: session.manifestSourceById[item.id] = element.sourcePath
  for index, child in element.children:
    session.addManifestElement(child, path & "/" & $index, item.id)
  session.expanded.incl item.id

proc selectZip(session: VextInspectionSession, filename: string,
    progress: VextSessionProgressCallback, refine = true) =
  session.zip = parseZipArchive(session.sources.primary)
  let zipCandidate = candidate(ZipArchiveTypeId, vdcCertain,
    "source has a valid single-volume ZIP index")
  session.candidates = @[zipCandidate]
  session.selectedFormat = zipCandidate
  session.kind = vskZip
  progress.report(VextSessionProgressEvent(phase: vsppValidatingManifest,
    path: filename, discovered: session.zip.entries.len,
    pending: session.zip.entries.len, totalState: vptsFinal,
    message: "Checking semantic package manifests"))
  if refine and session.zip.hasOpenRasterMimeMarker(session.sources.primary):
    try:
      session.manifest = parseOpenRasterManifest(session.zip,
        session.sources.primary, session.limits.maximumManifestBytes)
      var ora = candidate(OpenRasterTypeId, vdcCertain,
        "ZIP has a valid OpenRaster MIME marker and layer manifest")
      ora.derivation = zipCandidate.derivation.refinedDerivation(
        OpenRasterTypeId)
      session.selectedFormat = ora
      session.candidates.insert(ora, 0)
      session.kind = vskOpenRaster
    except ValueError as error:
      session.warnings.add VextInspectionWarning(path: "/",
        format: OpenRasterTypeId, message: error.msg)

proc selectIso(session: VextInspectionSession) =
  session.isoSource = session.sources.primary
  session.iso = indexIso9660(session.isoSource)
  let isoCandidate = candidate(Iso9660TypeId, vdcCertain,
    "source has valid ISO 9660 descriptors and root directory bounds")
  session.selectedFormat = isoCandidate
  session.candidates = @[isoCandidate]
  session.kind = vskIso9660

proc selectAppImageType1(session: VextInspectionSession) =
  session.appImageType1 = indexAppImageType1(session.sources.primary)
  session.iso = session.appImageType1.iso
  session.isoSource = sliceByteSource(session.sources.primary,
    session.appImageType1.filesystemOffset,
    session.sources.primary.length - session.appImageType1.filesystemOffset,
    session.filename & " (AppImage ISO)")
  let appCandidate = candidate(AppImageType1TypeId, vdcCertain,
    if session.appImageType1.filesystemOffset == 0:
      "source is a valid ELF runtime in the system area of an ISO 9660 filesystem"
    else:
      "source is a valid ELF with AI01 marker and an appended ISO 9660 filesystem")
  session.selectedFormat = appCandidate
  session.candidates = @[appCandidate]
  session.kind = vskAppImageType1

proc selectAppImage(session: VextInspectionSession) =
  session.appImage = indexAppImage(session.sources.primary)
  let appCandidate = candidate(AppImageTypeId, vdcCertain,
    "source is a valid ELF with AI02 marker and an appended SquashFS 4 filesystem")
  session.selectedFormat = appCandidate
  session.candidates = @[appCandidate]
  session.kind = vskAppImage

proc selectLha(session: VextInspectionSession) =
  session.lha = indexLhaArchive(session.sources.primary)
  let lhaCandidate = candidate(LhaArchiveTypeId, vdcCertain,
    "source has valid checksummed LHA member framing")
  session.selectedFormat = lhaCandidate
  session.candidates = @[lhaCandidate]
  session.kind = vskLha

proc selectElectronAsar(session: VextInspectionSession) =
  session.asar = parseElectronAsar(session.sources.primary,
    session.limits.maximumManifestBytes)
  let asarCandidate = candidate(ElectronAsarTypeId, vdcCertain,
    "source has valid ASAR Pickle framing and a bounded JSON file manifest")
  session.selectedFormat = asarCandidate
  session.candidates = @[asarCandidate]
  session.kind = vskElectronAsar

proc selectAmigaAdf(session: VextInspectionSession) =
  session.adf = indexAmigaAdf(session.sources.primary)
  let adfCandidate = candidate(AmigaAdfTypeId, vdcCertain,
    "source has a valid AmigaDOS root filesystem block")
  session.selectedFormat = adfCandidate
  session.candidates = @[adfCandidate]
  session.kind = vskAmigaAdf

proc selectDeferredWrapper(session: VextInspectionSession, typeId,
    rootPath, description: string) =
  session.deferredData = session.sources.primary.readAll(
    session.limits.maximumWorkingBytes)
  case typeId
  of AmigaDmsTypeId: discard parseAmigaDms(session.deferredData)
  of XpkTypeId: discard parseXpk(session.deferredData)
  of PowerPackerTypeId: discard parsePowerPacker(session.deferredData)
  else: raise newException(ValueError, "unsupported deferred wrapper")
  let wrapperCandidate = candidate(typeId, vdcCertain, description)
  session.selectedFormat = wrapperCandidate
  session.candidates = @[wrapperCandidate]
  session.deferredFormat = typeId
  session.deferredRootPath = rootPath
  session.kind = vskDeferredWrapper

proc openInspectionSession*(filename: string, sources: VextSourceCollection,
    inputFormat = "", ignoreWarnings = false,
    pcxChannelOrder = pcoRgb, ansiLetterSpacing = alsAuto,
    ansiAspect = apaAuto, limits = defaultWorkLimits(),
    progress: VextSessionProgressCallback = nil):
    VextInspectionSession =
  if sources.isNil or sources.primary.isNil:
    raise newException(ValueError, "inspection requires a primary source")
  result = VextInspectionSession(filename: filename, sources: sources,
    limits: limits, nextId: 0)
  try:
    progress.report(VextSessionProgressEvent(phase: vsppDetecting,
      path: filename, totalState: vptsUnknown,
      message: "Detecting input format"))
    let leading = sources.primary.readAt(0, min(11, sources.primary.length))
    let preferAppImage = leading.len >= 11 and leading[0] == 0x7f and
      leading[1] == byte('E') and leading[2] == byte('L') and
      leading[3] == byte('F')
    let preferZip = leading.len >= 4 and leading[0] == byte('P') and
      leading[1] == byte('K') and leading[2] in [1'u8, 3'u8, 5'u8, 7'u8] and
      leading[3] in [2'u8, 4'u8, 6'u8, 8'u8]
    let preferLha = leading.len == 7 and leading[2] == byte('-') and
      leading[6] == byte('-')
    let preferAsar = filename.hasElectronAsarExtension and leading.len >= 4 and
      leading[0] == 4 and leading[1] == 0 and leading[2] == 0 and
      leading[3] == 0
    let preferAdf = leading.len >= 4 and leading[0] == byte('D') and
      leading[1] == byte('O') and leading[2] == byte('S') and leading[3] <= 5 and
      sources.primary.length in [AmigaAdfDdSize, AmigaAdfHdSize]
    let preferDms = leading.len >= 4 and leading[0] == byte('D') and
      leading[1] == byte('M') and leading[2] == byte('S') and
      leading[3] == byte('!')
    let preferXpk = leading.len >= 4 and leading[0] == byte('X') and
      leading[1] == byte('P') and leading[2] == byte('K') and
      leading[3] == byte('F')
    let preferPowerPacker = leading.len >= 4 and leading[0] == byte('P') and
      leading[1] == byte('P') and leading[2] in [byte('1'), byte('2')] and
      leading[3] in [byte('1'), byte('0')]
    template selectLegacy() =
      let data = sources.primary.readAll(limits.maximumWorkingBytes)
      let legacy = inspectSource(filename, data, inputFormat, ignoreWarnings,
        pcxChannelOrder, ansiLetterSpacing, ansiAspect)
      result.selectedFormat = legacy.selectedFormat
      result.candidates = legacy.candidates
      result.warnings = legacy.warnings
      result.legacyTree = legacy.resources
      result.kind = vskLegacy
    if inputFormat.len > 0:
      case inputFormat
      of ZipArchiveTypeId: result.selectZip(filename, progress, false)
      of OpenRasterTypeId:
        result.selectZip(filename, progress)
        if result.kind != vskOpenRaster:
          raise newException(ValueError,
            "source is not a valid OpenRaster package")
      of Iso9660TypeId: result.selectIso()
      of AppImageType1TypeId: result.selectAppImageType1()
      of AppImageTypeId: result.selectAppImage()
      of LhaArchiveTypeId: result.selectLha()
      of ElectronAsarTypeId: result.selectElectronAsar()
      of AmigaAdfTypeId: result.selectAmigaAdf()
      of AmigaDmsTypeId:
        result.selectDeferredWrapper(AmigaDmsTypeId, "/disk",
          "source has valid checksummed DMS track framing")
      of XpkTypeId:
        result.selectDeferredWrapper(XpkTypeId, "/content",
          "source has valid XPK master and chunk framing")
      of PowerPackerTypeId:
        result.selectDeferredWrapper(PowerPackerTypeId, "/content",
          "source has valid PowerPacker framing")
      else: selectLegacy()
    elif preferAppImage:
      try:
        if leading[8] == byte('A') and leading[9] == byte('I') and
            leading[10] == 2: result.selectAppImage()
        else: result.selectAppImageType1()
      except ValueError, LibraryError: selectLegacy()
    elif preferDms:
      try:
        result.selectDeferredWrapper(AmigaDmsTypeId, "/disk",
          "source has valid checksummed DMS track framing")
      except ValueError: selectLegacy()
    elif preferXpk:
      try:
        result.selectDeferredWrapper(XpkTypeId, "/content",
          "source has valid XPK master and chunk framing")
      except ValueError: selectLegacy()
    elif preferAsar:
      try: result.selectElectronAsar()
      except ValueError: selectLegacy()
    elif preferPowerPacker:
      try:
        result.selectDeferredWrapper(PowerPackerTypeId, "/content",
          "source has valid PowerPacker framing")
      except ValueError: selectLegacy()
    elif preferAdf:
      try: result.selectAmigaAdf()
      except ValueError: selectLegacy()
    elif preferLha:
      try: result.selectLha()
      except ValueError: selectLegacy()
    elif preferZip:
      try:
        result.selectZip(filename, progress)
      except ValueError:
        try: result.selectIso()
        except ValueError: selectLegacy()
    else:
      # ISO has a fixed descriptor location. Prefer it for non-PK sources so a
      # disc image never incurs ZIP's variable-size EOCD tail search.
      try:
        result.selectIso()
      except ValueError:
        try: result.selectZip(filename, progress)
        except ValueError: selectLegacy()

    case result.kind
    of vskZip:
      let root = result.allocateDescriptor("/archive", ZipArchiveTypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural, metadata = @[
          integerMetadata("entries", result.zip.entries.len),
          stringMetadata("comment", result.zip.comment)])
      result.commit(root)
      result.roots.add root.id
    of vskOpenRaster:
      let image = result.allocateDescriptor("/image", OpenRasterImageTypeId,
        vrnkRaster, {vrcMaterializePayload, vrcDecodeRepresentation},
        vvlManifest, metadata = @[
          integerMetadata("canvas.width", result.manifest.width),
          integerMetadata("canvas.height", result.manifest.height)])
      result.commit(image)
      result.roots.add image.id
      result.manifestSourceById[image.id] = "mergedimage.png"
      let thumbnail = result.allocateDescriptor("/thumbnail",
        OpenRasterThumbnailTypeId, vrnkRaster,
        {vrcMaterializePayload, vrcDecodeRepresentation}, vvlManifest)
      result.commit(thumbnail)
      result.roots.add thumbnail.id
      result.manifestSourceById[thumbnail.id] = "Thumbnails/thumbnail.png"
      let layers = result.allocateDescriptor("/layers", OpenRasterStackTypeId,
        vrnkGroup, {vrcEnumerateChildren}, vvlManifest, metadata = @[
          stringMetadata("openraster.version", result.manifest.version),
          stringMetadata("document.name", result.manifest.name)])
      result.commit(layers)
      result.roots.add layers.id
      for index, child in result.manifest.stack.children:
        result.addManifestElement(child, "/layers/" & $index, layers.id)
      result.expanded.incl layers.id
    of vskIso9660:
      let root = result.allocateDescriptor("/disc", Iso9660TypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural, metadata = @[
          stringMetadata("layout", result.iso.layout.iso9660LayoutName),
          stringMetadata("volume.identifier", result.iso.volumeIdentifier),
          stringMetadata("system.identifier", result.iso.systemIdentifier),
          integerMetadata("logical-block-size", result.iso.logicalBlockSize),
          integerMetadata("volume.blocks", result.iso.volumeBlocks)])
      result.commit(root)
      result.roots.add root.id
      result.isoVisited.incl($result.iso.rootExtent & ":" &
        $result.iso.rootLength)
    of vskAppImageType1:
      let root = result.allocateDescriptor("/appimage", AppImageType1TypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural,
        metadata = @[
          integerMetadata("appimage.type", 1),
          integerMetadata("elf.class", result.appImageType1.elfClass),
          integerMetadata("elf.endian", result.appImageType1.elfEndian),
          integerMetadata("elf.machine", result.appImageType1.elfMachine),
          integerMetadata("filesystem.offset", result.appImageType1.filesystemOffset),
          stringMetadata("filesystem.type", Iso9660TypeId),
          stringMetadata("iso9660.layout", result.iso.layout.iso9660LayoutName),
          stringMetadata("iso9660.volume.identifier", result.iso.volumeIdentifier),
          integerMetadata("iso9660.logical-block-size", result.iso.logicalBlockSize),
          integerMetadata("iso9660.volume.blocks", result.iso.volumeBlocks)])
      result.commit(root)
      result.roots.add root.id
      result.isoVisited.incl($result.iso.rootExtent & ":" &
        $result.iso.rootLength)
    of vskAppImage:
      let root = result.allocateDescriptor("/appimage", AppImageTypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural,
        metadata = @[
          integerMetadata("appimage.type", 2),
          integerMetadata("elf.class", result.appImage.elfClass),
          integerMetadata("elf.endian", result.appImage.elfEndian),
          integerMetadata("elf.machine", result.appImage.elfMachine),
          integerMetadata("filesystem.offset", result.appImage.filesystemOffset),
          integerMetadata("squashfs.block-size", result.appImage.blockSize),
          integerMetadata("squashfs.compressor", result.appImage.compressor),
          integerMetadata("squashfs.entries", result.appImage.entries.len)])
      result.commit(root)
      result.roots.add root.id
    of vskLha:
      let root = result.allocateDescriptor("/archive", LhaArchiveTypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural, metadata = @[
          integerMetadata("entries", result.lha.entries.len)])
      result.commit(root)
      result.roots.add root.id
    of vskElectronAsar:
      var packedFiles, unpackedFiles: int
      for entry in result.asar.entries:
        if entry.isDirectory: discard
        elif entry.unpacked: inc unpackedFiles
        else: inc packedFiles
      let root = result.allocateDescriptor("/archive", ElectronAsarTypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlManifest,
        metadata = @[
          integerMetadata("entries", result.asar.entries.len),
          integerMetadata("files.packed", packedFiles),
          integerMetadata("files.unpacked", unpackedFiles),
          integerMetadata("header.length", result.asar.headerSize),
          integerMetadata("manifest.length", result.asar.headerJsonSize)])
      result.commit(root)
      result.roots.add root.id
    of vskAmigaAdf:
      let root = result.allocateDescriptor("/disk", AmigaAdfTypeId,
        vrnkGroup, {vrcEnumerateChildren, vrcExtractTree}, vvlStructural, metadata = @[
          stringMetadata("volume.name", result.adf.name),
          stringMetadata("filesystem", result.adf.filesystem),
          integerMetadata("filesystem.flags", result.adf.flags),
          integerMetadata("root.block", result.adf.rootBlock)])
      result.commit(root)
      result.roots.add root.id
      result.adfVisited.incl result.adf.rootBlock
    of vskDeferredWrapper:
      let isDisk = result.deferredFormat == AmigaDmsTypeId
      let root = result.allocateDescriptor(result.deferredRootPath,
        result.deferredFormat, if isDisk: vrnkGroup else: vrnkOpaque,
        if isDisk: {vrcEnumerateChildren}
        else: {vrcMaterializePayload, vrcProbeNested}, vvlStructural,
        result.deferredData.len)
      result.commit(root)
      result.roots.add root.id
    of vskLegacy:
      for root in result.legacyTree.roots:
        result.addLegacyNode(root, VextResourceId(0))
    progress.report(VextSessionProgressEvent(phase: vsppComplete,
      path: filename, completed: result.descriptors.len,
      discovered: result.descriptors.len, totalState: vptsFinal,
      message: "Inspection session ready"))
  except CatchableError:
    sources.close()
    raise

proc prefixSegments(path: string): seq[string] =
  let trimmed = path.strip(chars = {'/'})
  if trimmed.len == 0 or trimmed == "archive": return
  let parts = trimmed.split('/')
  if parts.len > 1: result = parts[1 .. ^1]

proc startsWithSegments(value, prefix: seq[string]): bool =
  if value.len < prefix.len: return false
  for index in 0 ..< prefix.len:
    if value[index] != prefix[index]: return false
  true

proc expandResource*(session: VextInspectionSession, id: VextResourceId,
    progress: VextSessionProgressCallback = nil): VextResourceDelta =
  session.ensureOpen()
  result.parent = id
  result.parentDescriptor = session.descriptor(id)
  if vrcEnumerateChildren notin result.parentDescriptor.capabilities:
    return
  if id in session.expanded:
    for child in session.children.getOrDefault(id):
      result.children.add session.descriptors[child]
    return
  progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
    path: result.parentDescriptor.path, totalState: vptsGrowing,
    message: "Enumerating children"))
  if session.kind == vskAppImage:
    let prefix = prefixSegments(result.parentDescriptor.path)
    var paths = initHashSet[string]()
    var localNext = session.nextId
    var pending: seq[tuple[item: VextResourceDescriptor, entryIndex: int]]
    for entryIndex, entry in session.appImage.entries:
      if not entry.segments.startsWithSegments(prefix) or
          entry.segments.len <= prefix.len:
        continue
      let directIndex = prefix.len
      var path = "/appimage"
      for index in 0 .. directIndex: path.add "/" & entry.segments[index]
      if path in paths: continue
      paths.incl path
      inc localNext
      let direct = entry.segments.len == prefix.len + 1
      let isDirectory = not direct or entry.kind == aiekDirectory
      let materializable = direct and entry.kind == aiekFile
      let item = VextResourceDescriptor(id: VextResourceId(localNext),
        path: path,
        typeId: if isDirectory: AppImageDirectoryTypeId
          elif entry.kind == aiekSymlink: AppImageSymlinkTypeId
          else: AppImageFileTypeId,
        kind: if isDirectory: vrnkGroup else: vrnkOpaque,
        capabilities: if isDirectory: {vrcEnumerateChildren}
          elif materializable: {vrcMaterializePayload, vrcProbeNested}
          else: {}, validatedThrough: vvlStructural,
        estimatedBytes: if materializable: entry.size else: 0,
        metadata: if direct: @[
          integerMetadata("posix.permissions", entry.permissions),
          integerMetadata("posix.uid-index", entry.uidIndex),
          integerMetadata("posix.gid-index", entry.gidIndex),
          integerMetadata("posix.uid", entry.uid),
          integerMetadata("posix.gid", entry.gid),
          integerMetadata("posix.inode", entry.inodeNumber),
          integerMetadata("posix.mtime", int(entry.mtime)),
          integerMetadata("data.length", entry.size),
          stringMetadata("posix.symlink-target", entry.symlinkTarget)] else: @[])
      pending.add (item, if materializable: entryIndex else: -1)
    if session.descriptors.len + pending.len > session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    session.nextId = localNext
    for pendingItem in pending:
      session.commit(pendingItem.item)
      session.children.mgetOrPut(id, @[]).add pendingItem.item.id
      if pendingItem.entryIndex >= 0:
        session.appImageEntryById[pendingItem.item.id] = pendingItem.entryIndex
      result.children.add pendingItem.item
    session.expanded.incl id
    return
  if session.kind in {vskIso9660, vskAppImageType1}:
    var parentSegments: seq[string]
    let stripped = result.parentDescriptor.path.strip(chars = {'/'})
    let parts = stripped.split('/')
    if parts.len > 1: parentSegments = parts[1 .. ^1]
    var extent = session.iso.rootExtent
    var length = session.iso.rootLength
    if session.isoEntryById.hasKey(id):
      let parentEntry = session.isoEntryById[id]
      extent = parentEntry.extentBlock
      length = parentEntry.dataLength
      let identity = $extent & ":" & $length
      if identity in session.isoVisited:
        raise newException(ValueError, "cyclic ISO 9660 directory extent")
    let entries = listIso9660Directory(session.isoSource, session.iso,
      extent, length, parentSegments)
    if session.descriptors.len + entries.len > session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    var localNext = session.nextId
    var pending: seq[tuple[item: VextResourceDescriptor,
      entry: Iso9660Entry]]
    for entry in entries:
      inc localNext
      let rootPath = if session.kind == vskAppImageType1: "/appimage" else: "/disc"
      let path = rootPath & "/" & entry.segments.join("/")
      let item = VextResourceDescriptor(id: VextResourceId(localNext),
        path: path,
        typeId: if entry.isDirectory: Iso9660DirectoryTypeId
          else: Iso9660FileTypeId,
        kind: if entry.isDirectory: vrnkGroup else: vrnkOpaque,
        capabilities: if entry.isDirectory: {vrcEnumerateChildren}
          elif entry.isSymlink: {}
          else: {vrcMaterializePayload, vrcProbeNested},
        validatedThrough: vvlStructural, estimatedBytes: entry.dataLength,
        metadata: @[
          stringMetadata("iso9660.name", entry.name),
          integerMetadata("iso9660.extent-block", entry.extentBlock),
          integerMetadata("data.length", entry.dataLength),
          integerMetadata("iso9660.file-version", entry.fileVersion),
          integerMetadata("posix.mode", entry.posixMode),
          integerMetadata("posix.uid", entry.posixUid),
          integerMetadata("posix.gid", entry.posixGid),
          integerMetadata("posix.serial", entry.posixSerial),
          stringMetadata("posix.symlink-target", entry.symlinkTarget)])
      pending.add (item, entry)
    progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
      path: result.parentDescriptor.path, completed: pending.len,
      discovered: pending.len, pending: 0, totalState: vptsFinal,
      message: "Children enumerated"))
    session.nextId = localNext
    for pendingItem in pending:
      session.commit(pendingItem.item)
      session.children.mgetOrPut(id, @[]).add pendingItem.item.id
      session.isoEntryById[pendingItem.item.id] = pendingItem.entry
      result.children.add pendingItem.item
    if session.isoEntryById.hasKey(id):
      session.isoVisited.incl($extent & ":" & $length)
    session.expanded.incl id
    return
  if session.kind == vskLha:
    let prefix = prefixSegments(result.parentDescriptor.path)
    var paths = initHashSet[string]()
    var localNext = session.nextId
    var pending: seq[tuple[item: VextResourceDescriptor, entryIndex: int]]
    for entryIndex, entry in session.lha.entries:
      if not entry.segments.startsWithSegments(prefix) or
          entry.segments.len <= prefix.len:
        continue
      let directIndex = prefix.len
      var path = "/archive"
      for index in 0 .. directIndex: path.add "/" & entry.segments[index]
      if path in paths: continue
      paths.incl path
      inc localNext
      let directFile = entry.segments.len == prefix.len + 1 and
        not entry.isDirectory
      let item = VextResourceDescriptor(id: VextResourceId(localNext),
        path: path,
        typeId: if directFile: LhaFileTypeId else: LhaDirectoryTypeId,
        kind: if directFile: vrnkOpaque else: vrnkGroup,
        capabilities: if directFile:
          {vrcMaterializePayload, vrcProbeNested}
        else: {vrcEnumerateChildren}, validatedThrough: vvlStructural,
        estimatedBytes: if directFile: entry.uncompressedSize else: 0,
        metadata: if directFile: @[
          stringMetadata("lha.name", entry.name),
          stringMetadata("compression.method", entry.compressionMethod),
          integerMetadata("compressed.length", entry.compressedSize),
          integerMetadata("data.length", entry.uncompressedSize)] else: @[])
      pending.add (item, if directFile: entryIndex else: -1)
    if session.descriptors.len + pending.len > session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
      path: result.parentDescriptor.path, completed: pending.len,
      discovered: pending.len, pending: 0, totalState: vptsFinal,
      message: "Children enumerated"))
    session.nextId = localNext
    for pendingItem in pending:
      session.commit(pendingItem.item)
      session.children.mgetOrPut(id, @[]).add pendingItem.item.id
      if pendingItem.entryIndex >= 0:
        session.lhaEntryById[pendingItem.item.id] = pendingItem.entryIndex
      result.children.add pendingItem.item
    session.expanded.incl id
    return
  if session.kind == vskElectronAsar:
    let prefix = prefixSegments(result.parentDescriptor.path)
    var paths = initHashSet[string]()
    var localNext = session.nextId
    var pending: seq[tuple[item: VextResourceDescriptor, entryIndex: int]]
    for entryIndex, entry in session.asar.entries:
      if not entry.segments.startsWithSegments(prefix) or
          entry.segments.len <= prefix.len:
        continue
      let directIndex = prefix.len
      var path = "/archive"
      for index in 0 .. directIndex: path.add "/" & entry.segments[index]
      if path in paths: continue
      paths.incl path
      inc localNext
      let directFile = entry.segments.len == prefix.len + 1 and
        not entry.isDirectory
      var metadata: seq[VextMetadataEntry]
      if directFile:
        metadata = @[
          stringMetadata("asar.name", entry.name),
          integerMetadata("data.length", entry.size),
          integerMetadata("asar.unpacked", ord(entry.unpacked)),
          integerMetadata("asar.executable", ord(entry.executable))]
        if entry.integrityAlgorithm.len > 0:
          metadata.add stringMetadata("integrity.algorithm",
            entry.integrityAlgorithm)
          metadata.add stringMetadata("integrity.hash", entry.integrityHash)
          metadata.add integerMetadata("integrity.block-size",
            entry.integrityBlockSize)
          metadata.add integerMetadata("integrity.blocks",
            entry.integrityBlocks)
      let item = VextResourceDescriptor(id: VextResourceId(localNext),
        path: path,
        typeId: if directFile: ElectronAsarFileTypeId
          else: ElectronAsarDirectoryTypeId,
        kind: if directFile: vrnkOpaque else: vrnkGroup,
        capabilities: if directFile and not entry.unpacked:
          {vrcMaterializePayload, vrcProbeNested}
        elif directFile: {}
        else: {vrcEnumerateChildren}, validatedThrough: vvlManifest,
        estimatedBytes: if directFile: entry.size else: 0,
        metadata: metadata)
      pending.add (item, if directFile: entryIndex else: -1)
    if session.descriptors.len + pending.len > session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
      path: result.parentDescriptor.path, completed: pending.len,
      discovered: pending.len, pending: 0, totalState: vptsFinal,
      message: "Children enumerated"))
    session.nextId = localNext
    for pendingItem in pending:
      session.commit(pendingItem.item)
      session.children.mgetOrPut(id, @[]).add pendingItem.item.id
      if pendingItem.entryIndex >= 0:
        session.asarEntryById[pendingItem.item.id] = pendingItem.entryIndex
      result.children.add pendingItem.item
    session.expanded.incl id
    return
  if session.kind == vskAmigaAdf:
    var sector = session.adf.rootBlock
    if session.adfEntryById.hasKey(id):
      sector = session.adfEntryById[id].sector
      if sector in session.adfVisited:
        raise newException(ValueError, "cyclic ADF directory tree")
    let entries = listAmigaAdfDirectory(session.sources.primary,
      session.adf, sector)
    if session.descriptors.len + entries.len > session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    var localNext = session.nextId
    var pending: seq[tuple[item: VextResourceDescriptor,
      entry: AmigaAdfEntry]]
    for entry in entries:
      inc localNext
      let path = result.parentDescriptor.path & "/" & entry.name
      let item = VextResourceDescriptor(id: VextResourceId(localNext),
        path: path,
        typeId: case entry.kind
          of aaekDirectory: AmigaAdfDirectoryTypeId
          of aaekFile: AmigaAdfFileTypeId
          of aaekLink: AmigaAdfLinkTypeId,
        kind: if entry.kind == aaekDirectory: vrnkGroup else: vrnkOpaque,
        capabilities: case entry.kind
          of aaekDirectory: {vrcEnumerateChildren}
          of aaekFile: {vrcMaterializePayload, vrcProbeNested}
          of aaekLink: {},
        validatedThrough: vvlStructural,
        estimatedBytes: entry.size, metadata: @[
          integerMetadata("adf.block", entry.sector),
          stringMetadata("adf.name", entry.name),
          stringMetadata("adf.comment", entry.comment)])
      pending.add (item, entry)
    progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
      path: result.parentDescriptor.path, completed: pending.len,
      discovered: pending.len, pending: 0, totalState: vptsFinal,
      message: "Children enumerated"))
    session.nextId = localNext
    for pendingItem in pending:
      session.commit(pendingItem.item)
      session.children.mgetOrPut(id, @[]).add pendingItem.item.id
      session.adfEntryById[pendingItem.item.id] = pendingItem.entry
      result.children.add pendingItem.item
    if session.adfEntryById.hasKey(id): session.adfVisited.incl sector
    session.expanded.incl id
    return
  if session.kind == vskDeferredWrapper:
    if session.deferredFormat != AmigaDmsTypeId:
      session.expanded.incl id
      return
    let inspection = inspectSource(session.filename, session.deferredData,
      session.deferredFormat)
    var sourceRoot: VextResourceNode
    for root in inspection.resources.roots:
      if root.path == session.deferredRootPath: sourceRoot = root
    if sourceRoot.isNil:
      raise newException(ValueError, "deferred wrapper produced no root")
    if session.descriptors.len + VextResourceTree(
        roots: @[sourceRoot]).allResources.len >
        session.limits.maximumResources:
      raise newException(VextWorkLimitError,
        "resource count exceeds the inspection limit")
    for child in sourceRoot.children:
      session.addLegacyNode(child, id)
    for childId in session.children.getOrDefault(id):
      result.children.add session.descriptors[childId]
    session.expanded.incl id
    return
  if session.kind != vskZip:
    session.expanded.incl id
    return
  let prefix = prefixSegments(result.parentDescriptor.path)
  var pending: seq[tuple[item: VextResourceDescriptor, entryIndex: int]]
  var paths = initHashSet[string]()
  var localNext = session.nextId
  for entryIndex, entry in session.zip.entries:
    if entryIndex mod 64 == 0:
      progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
        path: result.parentDescriptor.path, completed: entryIndex,
        discovered: session.zip.entries.len,
        pending: session.zip.entries.len - entryIndex,
        totalState: vptsFinal, message: "Scanning ZIP directory"))
    if not entry.segments.startsWithSegments(prefix) or
        entry.segments.len <= prefix.len:
      continue
    let directIndex = prefix.len
    var path = "/archive"
    for index in 0 .. directIndex: path.add "/" & entry.segments[index]
    if path in paths: continue
    paths.incl path
    inc localNext
    let directFile = entry.segments.len == prefix.len + 1 and
      not entry.isDirectory
    let item = VextResourceDescriptor(id: VextResourceId(localNext),
      path: path,
      typeId: if directFile: ZipFileTypeId else: ZipDirectoryTypeId,
      kind: if directFile: vrnkOpaque else: vrnkGroup,
      capabilities: if directFile:
        {vrcMaterializePayload, vrcProbeNested}
      else: {vrcEnumerateChildren},
      validatedThrough: vvlStructural,
      estimatedBytes: if directFile: entry.uncompressedSize else: 0,
      metadata: if directFile: @[
        stringMetadata("zip.name", entry.name),
        integerMetadata("compression.method", entry.compressionMethod),
        integerMetadata("compressed.length", entry.compressedSize),
        integerMetadata("data.length", entry.uncompressedSize)] else: @[])
    pending.add (item, if directFile: entryIndex else: -1)
  if session.descriptors.len + pending.len > session.limits.maximumResources:
    raise newException(VextWorkLimitError,
      "resource count exceeds the inspection limit")
  # Commit only after enumeration and its cancellation point succeed.
  progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
    path: result.parentDescriptor.path, completed: pending.len,
    discovered: pending.len, pending: 0, totalState: vptsFinal,
    message: "Children enumerated"))
  session.nextId = localNext
  for pendingItem in pending:
    session.commit(pendingItem.item)
    session.children.mgetOrPut(id, @[]).add pendingItem.item.id
    if pendingItem.entryIndex >= 0:
      session.zipEntryById[pendingItem.item.id] = pendingItem.entryIndex
    result.children.add pendingItem.item
  session.expanded.incl id

proc findZipEntry(archive: ZipArchive, name: string): int =
  for index, entry in archive.entries:
    if entry.name == name and not entry.isDirectory: return index
  -1

proc materializePayload*(session: VextInspectionSession, id: VextResourceId,
    progress: VextSessionProgressCallback = nil,
    maximumWorkingBytes = 0): seq[byte] =
  ## Materializes only the retained container-member bytes. Unlike
  ## loadResource, this deliberately performs no nested probing or decoding.
  session.ensureOpen()
  let descriptor = session.descriptor(id)
  if vrcMaterializePayload notin descriptor.capabilities:
    raise newException(ValueError, "resource has no extractable payload: " &
      descriptor.path)
  let workingLimit = if maximumWorkingBytes > 0: maximumWorkingBytes
    else: session.limits.maximumWorkingBytes
  if descriptor.estimatedBytes > workingLimit:
    raise newException(VextWorkLimitError,
      "resource requires " & $descriptor.estimatedBytes &
      " bytes, exceeding the active working-data limit of " &
      $workingLimit & " bytes: " & descriptor.path)
  progress.report(VextSessionProgressEvent(phase: vsppMaterializing,
    path: descriptor.path, discovered: 1, pending: 1,
    totalState: vptsFinal, message: "Materializing payload"))
  if session.legacyNodeById.hasKey(id):
    return session.legacyNodeById[id].resourceBytes
  case session.kind
  of vskZip:
    let entryIndex = session.zipEntryById.getOrDefault(id, -1)
    if entryIndex < 0:
      raise newException(ValueError, "resource has no ZIP payload")
    result = extractZipEntry(session.sources.primary,
      session.zip.entries[entryIndex], workingLimit)
  of vskOpenRaster:
    let sourcePath = session.manifestSourceById.getOrDefault(id)
    let entryIndex = session.zip.findZipEntry(sourcePath)
    if entryIndex < 0:
      raise newException(ValueError, "OpenRaster resource payload is missing")
    result = extractZipEntry(session.sources.primary,
      session.zip.entries[entryIndex], workingLimit)
  of vskIso9660, vskAppImageType1:
    if not session.isoEntryById.hasKey(id):
      raise newException(ValueError, "resource has no ISO 9660 payload")
    result = extractIso9660Entry(session.isoSource, session.iso,
      session.isoEntryById[id], workingLimit)
  of vskAppImage:
    let entryIndex = session.appImageEntryById.getOrDefault(id, -1)
    if entryIndex < 0:
      raise newException(ValueError, "resource has no AppImage payload")
    result = extractAppImageEntry(session.sources.primary, session.appImage,
      session.appImage.entries[entryIndex], workingLimit)
  of vskLha:
    let entryIndex = session.lhaEntryById.getOrDefault(id, -1)
    if entryIndex < 0:
      raise newException(ValueError, "resource has no LHA payload")
    result = extractLhaEntry(session.sources.primary,
      session.lha.entries[entryIndex], workingLimit)
  of vskElectronAsar:
    let entryIndex = session.asarEntryById.getOrDefault(id, -1)
    if entryIndex < 0:
      raise newException(ValueError, "resource has no ASAR payload")
    result = extractElectronAsarEntry(session.sources.primary,
      session.asar.entries[entryIndex], workingLimit)
  of vskAmigaAdf:
    if not session.adfEntryById.hasKey(id):
      raise newException(ValueError, "resource has no ADF payload")
    result = extractAmigaAdfFile(session.sources.primary, session.adf,
      session.adfEntryById[id], workingLimit)
  of vskDeferredWrapper, vskLegacy:
    raise newException(ValueError, "resource has no extractable payload: " &
      descriptor.path)
  progress.report(VextSessionProgressEvent(phase: vsppComplete,
    path: descriptor.path, completed: 1, discovered: 1,
    totalState: vptsFinal, message: "Payload materialized"))

proc loadResource*(session: VextInspectionSession, id: VextResourceId,
    progress: VextSessionProgressCallback = nil,
    maximumWorkingBytes = 0): VextLoadedResource =
  session.ensureOpen()
  result.descriptor = session.descriptor(id)
  let workingLimit = if maximumWorkingBytes > 0: maximumWorkingBytes
    else: session.limits.maximumWorkingBytes
  if result.descriptor.estimatedBytes > workingLimit:
    raise newException(VextWorkLimitError,
      "resource requires " & $result.descriptor.estimatedBytes &
      " bytes, exceeding the active working-data limit of " &
      $workingLimit & " bytes: " & result.descriptor.path)
  if session.legacyNodeById.hasKey(id):
    let node = session.legacyNodeById[id]
    if node.kind == vrnkAudio and node.soundMaterializer != nil:
      discard node.audioSound
    result.data = node.resourceBytes
    result.resources = VextResourceTree(roots: @[node])
    return
  case session.kind
  of vskDeferredWrapper:
    let inspection = inspectSource(session.filename, session.deferredData,
      session.deferredFormat)
    result.resources = inspection.resources
    result.warnings = inspection.warnings
    result.data = session.deferredData
    return
  of vskLegacy:
    let node = session.legacyNodeById.getOrDefault(id)
    if node.isNil:
      raise newException(ValueError, "resource was not found")
    result.data = node.resourceBytes
    result.resources = VextResourceTree(roots: @[node])
    return
  else:
    result.data = session.materializePayload(id, progress, workingLimit)
  let leafName = result.descriptor.path.split('/')[^1]
  var candidates: seq[VextDetectionCandidate]
  try:
    candidates = detectFormats(leafName, result.data)
  except CatchableError as error:
    result.resources = VextResourceTree(roots: @[VextResourceNode(
      path: result.descriptor.path, typeId: result.descriptor.typeId,
      kind: vrnkOpaque, data: result.data, rawDataAvailable: true,
      failureFormat: "recognized contained format",
      failureMessage: error.msg,
      metadata: @[stringMetadata("decode.warning", error.msg)])])
    result.descriptor.failureFormat = "recognized contained format"
    result.descriptor.failureMessage = error.msg
    result.descriptor.validatedThrough = vvlPayload
  if result.resources.roots.len == 0:
    if candidates.len == 0:
      result.resources = VextResourceTree(roots: @[VextResourceNode(
        path: result.descriptor.path, typeId: result.descriptor.typeId,
        kind: vrnkOpaque, data: result.data, rawDataAvailable: true,
        metadata: @[stringMetadata("decode.status", "format not recognized")])])
      result.descriptor.validatedThrough = vvlPayload
    else:
      try:
        let inspection = inspectSource(leafName, result.data)
        result.resources = inspection.resources
        result.warnings = inspection.warnings
        result.descriptor.validatedThrough = vvlRepresentation
      except CatchableError as error:
        result.resources = VextResourceTree(roots: @[VextResourceNode(
          path: result.descriptor.path, typeId: result.descriptor.typeId,
          kind: vrnkOpaque, data: result.data, rawDataAvailable: true,
          failureFormat: candidates[0].typeId,
          failureMessage: error.msg,
          metadata: @[
            stringMetadata("decode.format", candidates[0].typeId),
            stringMetadata("decode.warning", error.msg)])])
        result.descriptor.failureFormat = candidates[0].typeId
        result.descriptor.failureMessage = error.msg
        result.descriptor.validatedThrough = vvlPayload
  progress.report(VextSessionProgressEvent(phase: vsppComplete,
    path: result.descriptor.path, completed: 1, discovered: 1,
    totalState: vptsFinal, message: "Resource loaded"))

proc walkTopology*(session: VextInspectionSession,
    visitor: proc(descriptor: VextResourceDescriptor): bool {.closure.},
    progress: VextSessionProgressCallback = nil) =
  session.ensureOpen()
  var pending: seq[VextResourceId]
  for index in countdown(session.roots.high, 0): pending.add session.roots[index]
  var completed = 0
  var discovered = pending.len
  while pending.len > 0:
    let id = pending.pop()
    let item = session.descriptor(id)
    if visitor != nil and not visitor(item):
      raise newException(VextSessionCancelledError, "operation cancelled")
    inc completed
    if vrcEnumerateChildren in item.capabilities:
      let delta = session.expandResource(id, progress)
      discovered += delta.children.len
      for index in countdown(delta.children.high, 0):
        pending.add delta.children[index].id
    progress.report(VextSessionProgressEvent(phase: vsppEnumerating,
      path: item.path, completed: completed, discovered: discovered,
      pending: pending.len, totalState: vptsGrowing,
      message: "Walking resource topology"))
  progress.report(VextSessionProgressEvent(phase: vsppComplete,
    completed: completed, discovered: completed, pending: 0,
    totalState: vptsFinal, message: "Resource topology complete"))

const ExtractionDeviceNames = [
  "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5",
  "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4",
  "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]

proc portableExtractionSegment(segment: string): string =
  for value in segment:
    if ord(value) < 32 or value in {'<', '>', ':', '"', '/', '\\', '|', '?', '*'}:
      result.add '_'
    else:
      result.add value
  result = result.strip(chars = {' ', '.'}, leading = false, trailing = true)
  if result.len == 0: result = "_"
  let stem = result.split('.', maxsplit = 1)[0].toLowerAscii
  if stem in ExtractionDeviceNames: result = "_" & result

proc extractionPlan*(session: VextInspectionSession,
    rootId = VextResourceId(0),
    progress: VextSessionProgressCallback = nil): VextExtractionPlan =
  ## Enumerates a container hierarchy without loading its file payloads.
  ## Relative paths are portable and collision-checked before any write.
  session.ensureOpen()
  var planned: VextExtractionPlan
  var selectedId = rootId
  if uint64(selectedId) == 0:
    for id in session.roots:
      if vrcExtractTree in session.descriptors[id].capabilities:
        if uint64(selectedId) != 0:
          raise newException(ValueError,
            "more than one extractable container root is available")
        selectedId = id
  if uint64(selectedId) == 0:
    raise newException(ValueError,
      "the selected format does not expose an extractable hierarchy")
  planned.root = session.descriptor(selectedId)
  if vrcExtractTree notin planned.root.capabilities:
    raise newException(ValueError,
      "resource is not an extractable container: " & planned.root.path)

  var used = initTable[string, string]()
  proc visit(parentId: VextResourceId, sourceParts,
      destinationParts: seq[string]) =
    let delta = session.expandResource(parentId, progress)
    for child in delta.children:
      let sourceName = child.path.split('/')[^1]
      let safeName = portableExtractionSegment(sourceName)
      let childSource = sourceParts & @[sourceName]
      let childDestination = destinationParts & @[safeName]
      let relativePath = childDestination.join("/")
      if safeName != sourceName:
        planned.warnings.add "renamed unsafe member '" &
          childSource.join("/") & "' to '" & relativePath & "'"
      let collisionKey = relativePath.toLowerAscii
      if used.hasKey(collisionKey):
        raise newException(ValueError, "extraction path collision: " &
          used[collisionKey] & " and " & childSource.join("/"))
      used[collisionKey] = childSource.join("/")
      if vrcEnumerateChildren in child.capabilities:
        planned.entries.add VextExtractionEntry(kind: veekDirectory,
          relativePath: relativePath, descriptor: child)
        visit(child.id, childSource, childDestination)
      elif vrcMaterializePayload in child.capabilities:
        planned.entries.add VextExtractionEntry(kind: veekFile,
          relativePath: relativePath, descriptor: child)
        planned.totalEstimatedBytes += int64(max(0, child.estimatedBytes))
      else:
        planned.warnings.add "skipped non-materializable member '" &
          childSource.join("/") & "'"
  visit(selectedId, @[], @[])
  progress.report(VextSessionProgressEvent(phase: vsppComplete,
    path: planned.root.path, completed: planned.entries.len,
    discovered: planned.entries.len, pending: 0,
    totalState: vptsFinal, message: "Extraction plan complete"))
  result = move(planned)

proc close*(session: VextInspectionSession) =
  if session.isNil or session.closed: return
  session.closed = true
  session.sources.close()
  session.descriptors.clear()
  session.children.clear()
  session.idsByPath.clear()
  session.asarEntryById.clear()
  session.appImageEntryById.clear()
  session.legacyNodeById.clear()
