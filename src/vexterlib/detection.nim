## Evidence-based input format detection.

import std/[os, strutils]
import ./byte_sources
import ./handler_registry
import ./format_detection_types
export format_detection_types
import ./containers/[adobe_color_table, amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_deep, amiga_dr2d,
  amiga_diskfont, amiga_dms, amiga_hunk_executable, amiga_iff, amiga_ilbm,
  amiga_lha_sfx, amiga_pbm, amiga_workbench_icon, amos_bank, amos_bank_set,
  amos_program,
  adobe_swatch_exchange, amos_sprite_icon_bank, ansi_art, appimage, aseprite,
  bmfont, bmp, creative_voice, d64, doom_wad, electron_asar, fat_disk_image, flic, fzx,
  gif_container, gimp_palette, inno_setup, iso9660, jasc_palette, jpeg, koala_painter, netpbm,
  paint_net_palette, pcx, pdf, png_container, protracker_mod, qoi,
  rgba8_palette, tga,
  sqlite, wav, windows_icon, windows_write, zip_archive, lha_archive,
  zx_spectrum_gigascreen_dump,
  zx_spectrum_next_image,
  zx_spectrum_next_palette,
  zx_spectrum_screen_dump,
  wordstar, zx_spectrum_snapshot, zx_spectrum_tap, zx_spectrum_tzx]
import ./containers/xpk_shri
import ./containers/powerpacker
import ./resources/zx_spectrum_screen

type
  VextDetectionWindow* = object
    offset*: int
    data*: seq[byte]

  VextDetectionRead* = proc(offset, amount: int): seq[byte] {.closure.}

  VextDetectionInput* = ref object
    ## One bounded, reusable evidence view shared by every detector. Windows
    ## carry absolute source offsets; complete data is cached on first demand.
    filename*: string
    length*: int
    windows*: seq[VextDetectionWindow]
    completeAvailable*: bool
    completeData: seq[byte]
    read: VextDetectionRead
    maximumBytes: int

  VextSourceDetectionKind* = enum
    vsdkCompleteInput
    vsdkZip
    vsdkIso9660
    vsdkAppImageType1
    vsdkAppImage
    vsdkLha
    vsdkElectronAsar
    vsdkAmigaAdf
    vsdkInnoSetup
    vsdkAmigaDms
    vsdkXpk
    vsdkPowerPacker

  VextDetectedFormat* = object
    candidate*: VextDetectionCandidate
    parsed*: VextParsedContainer

proc addWindow(input: VextDetectionInput, offset: int, data: seq[byte]) =
  if data.len == 0: return
  for window in input.windows:
    if window.offset == offset and window.data.len == data.len: return
  input.windows.add VextDetectionWindow(offset: offset, data: data)

proc newDetectionInput*(filename: string, data: openArray[byte]):
    VextDetectionInput =
  ## Creates an already-complete input for in-memory callers.
  let owned = @data
  result = VextDetectionInput(filename: filename, length: owned.len,
    completeAvailable: true, completeData: owned,
    maximumBytes: owned.len)
  result.addWindow(0, owned)

proc newDetectionInput*(filename: string, source: VextByteSource,
    maximumBytes: int, leadingBytes = 11, trailingBytes = 0,
    completeThreshold = 0): VextDetectionInput =
  ## Creates a bounded random-access input. Requested leading and trailing
  ## evidence is read once; callers may opt to make small inputs complete.
  if source.isNil:
    raise newException(ValueError, "detection requires a byte source")
  result = VextDetectionInput(filename: filename, length: source.length,
    maximumBytes: maximumBytes,
    read: proc(offset, amount: int): seq[byte] = source.readAt(offset, amount))
  if completeThreshold > 0 and source.length <= completeThreshold and
      source.length <= maximumBytes:
    result.completeData = source.readAll(maximumBytes)
    result.completeAvailable = true
    result.addWindow(0, result.completeData)
  else:
    let initialBudget = max(0, maximumBytes)
    let leadingLength = min(min(leadingBytes, source.length), initialBudget)
    result.addWindow(0, source.readAt(0, leadingLength))
    let trailingLength = min(min(trailingBytes,
      source.length - leadingLength), initialBudget - leadingLength)
    let trailingOffset = source.length - trailingLength
    if trailingLength > 0:
      result.addWindow(trailingOffset,
        source.readAt(trailingOffset, trailingLength))

proc readWindow*(input: VextDetectionInput, offset, amount: int): seq[byte] =
  ## Returns one cached absolute range, reading it through the shared broker
  ## only when the initial windows do not already contain it.
  if input.isNil or offset < 0 or amount < 0 or offset > input.length or
      amount > input.length - offset:
    raise newException(ValueError, "detection range is outside the source")
  if amount == 0: return @[]
  if input.completeAvailable:
    return input.completeData[offset ..< offset + amount]
  for window in input.windows:
    if offset >= window.offset and
        offset + amount <= window.offset + window.data.len:
      let first = offset - window.offset
      return window.data[first ..< first + amount]
  if input.read.isNil:
    raise newException(ValueError, "detection range is not available")
  result = input.read(offset, amount)
  input.addWindow(offset, result)

proc completeBytes*(input: VextDetectionInput): seq[byte] =
  ## Materializes the input at most once. Detectors still using whole-input
  ## parsers therefore share one bounded read while they migrate to windows.
  if input.isNil:
    raise newException(ValueError, "detection input is not available")
  if not input.completeAvailable:
    if input.length > input.maximumBytes:
      raise newException(ValueError,
        "input exceeds the detection working-data limit")
    if input.read.isNil:
      raise newException(ValueError, "complete detection data is unavailable")
    input.completeData = input.read(0, input.length)
    input.completeAvailable = true
    input.windows.setLen(0)
    input.addWindow(0, input.completeData)
  input.completeData

proc sourceDetectionOrder*(input: VextDetectionInput):
    seq[VextSourceDetectionKind] =
  ## Cheap carrier routing shared by incremental sessions. Each attempted
  ## parser still validates its structure before a candidate is accepted.
  let leading = input.readWindow(0, min(11, input.length))
  let preferAppImage = leading.len >= 11 and leading[0] == 0x7f and
    leading[1] == byte('E') and leading[2] == byte('L') and
    leading[3] == byte('F')
  let preferZip = leading.len >= 4 and leading[0] == byte('P') and
    leading[1] == byte('K') and leading[2] in [1'u8, 3'u8, 5'u8, 7'u8] and
    leading[3] in [2'u8, 4'u8, 6'u8, 8'u8]
  let preferLha = leading.len >= 7 and leading[2] == byte('-') and
    leading[6] == byte('-')
  let preferAsar = input.filename.hasElectronAsarExtension and
    leading.len >= 4 and leading[0] == 4 and leading[1] == 0 and
    leading[2] == 0 and leading[3] == 0
  let preferAdf = leading.len >= 4 and leading[0] == byte('D') and
    leading[1] == byte('O') and leading[2] == byte('S') and leading[3] <= 5 and
    input.length in [AmigaAdfDdSize, AmigaAdfHdSize]
  let preferDms = leading.len >= 4 and leading[0] == byte('D') and
    leading[1] == byte('M') and leading[2] == byte('S') and
    leading[3] == byte('!')
  let preferXpk = leading.len >= 4 and leading[0] == byte('X') and
    leading[1] == byte('P') and leading[2] == byte('K') and
    leading[3] == byte('F')
  let preferPowerPacker = leading.len >= 4 and leading[0] == byte('P') and
    leading[1] == byte('P') and leading[2] in [byte('1'), byte('2')] and
    leading[3] in [byte('1'), byte('0')]
  let preferInno = leading.len >= 2 and leading[0] == byte('M') and
    leading[1] == byte('Z') and input.filename.hasInnoSetupExtension
  if preferInno: return @[vsdkInnoSetup, vsdkCompleteInput]
  if preferAppImage:
    return @[(if leading[8] == byte('A') and leading[9] == byte('I') and
      leading[10] == 2: vsdkAppImage else: vsdkAppImageType1),
      vsdkCompleteInput]
  if preferDms: return @[vsdkAmigaDms, vsdkCompleteInput]
  if preferXpk: return @[vsdkXpk, vsdkCompleteInput]
  if preferAsar: return @[vsdkElectronAsar, vsdkCompleteInput]
  if preferPowerPacker: return @[vsdkPowerPacker, vsdkCompleteInput]
  if preferAdf: return @[vsdkAmigaAdf, vsdkCompleteInput]
  if preferLha: return @[vsdkLha, vsdkCompleteInput]
  if preferZip: return @[vsdkZip, vsdkIso9660, vsdkCompleteInput]
  @[vsdkIso9660, vsdkZip, vsdkCompleteInput]

proc detectDetectionOnlyFormats*(input: VextDetectionInput):
    seq[VextDetectionCandidate] =
  ## Recognizes physical formats whose bounded evidence does not require a
  ## parser. Incremental sessions can use this before considering eager paths.
  let filename = input.filename
  if input.length >= PdfHeaderLength:
    let version = input.readWindow(0, PdfHeaderLength).pdfVersion
    if version.len > 0:
      var evidence = @[VextDetectionEvidence(description:
        "file begins with %PDF-" & version &
        ", a recognized core PDF version header")]
      if filename.hasPdfExtension:
        evidence.add VextDetectionEvidence(description: "file extension is .pdf")
      return @[VextDetectionCandidate(typeId: PdfTypeId,
        support: vfsDetectionOnly, confidence: vdcCertain,
        evidence: evidence, derivation: baseDerivation(PdfTypeId))]

proc detectBaseFormats(input: VextDetectionInput):
    seq[VextDetectionCandidate] =
  ## Returns every format candidate recognized from currently available
  ## evidence, ordered from strongest to weakest.
  let detectionOnly = input.detectDetectionOnlyFormats
  if detectionOnly.len > 0: return detectionOnly
  let filename = input.filename
  let data = input.completeBytes
  if isWindowsWrite(data):
    let source = parseWindowsWrite(data)
    var evidence = @[VextDetectionEvidence(description:
      "0x" & source.signatureByte.toHex(2) &
      "BE signature, text boundary, and page-aligned section boundaries " &
      "match the supplied Windows 3.1 Write documents")]
    if source.embeddedImages.len > 0:
      evidence.add VextDetectionEvidence(description:
        $source.embeddedImages.len &
        " bounded Paintbrush BMP object(s) were decoded")
    if filename.hasWindowsWriteExtension:
      evidence.add VextDetectionEvidence(description: "file extension is .wri")
    return @[VextDetectionCandidate(typeId: WindowsWriteTypeId,
      confidence: vdcProbable, evidence: evidence,
      derivation: baseDerivation(WindowsWriteTypeId))]
  if isSqlite(data):
    try:
      let database = parseSqlite(data)
      var evidence = @[VextDetectionEvidence(description:
        "file has a valid SQLite 3 header, schema table, and " &
        $database.tables.len & " bounded table b-tree(s)")]
      if filename.hasSqliteExtension:
        evidence.add VextDetectionEvidence(description:
          "filename uses a conventional SQLite extension")
      return @[VextDetectionCandidate(typeId: SqliteTypeId,
        confidence: vdcCertain, evidence: evidence,
        derivation: baseDerivation(SqliteTypeId))]
    except ValueError:
      discard
  try:
    let installer = parseInnoSetup(data)
    var evidence = @[VextDetectionEvidence(description:
      "executable contains a recognized Inno Setup " & installer.loaderVersion &
      " loader and bounded setup data version " & installer.setupVersion)]
    if filename.hasInnoSetupExtension:
      evidence.add VextDetectionEvidence(description: "file extension is .exe")
    return @[VextDetectionCandidate(typeId: InnoSetupTypeId,
      confidence: vdcCertain, evidence: evidence,
      derivation: baseDerivation(InnoSetupTypeId))]
  except ValueError:
    discard
  if data.len >= 11 and data[0] == 0x7f and data[1] == byte('E') and
      data[2] == byte('L') and data[3] == byte('F') and
      not (data[8] == byte('A') and data[9] == byte('I') and data[10] == 2):
    try:
      let image = parseAppImageType1(data)
      var evidence = @[VextDetectionEvidence(description:
        "file is a valid ELF combined with an ISO 9660 filesystem " &
        (if image.filesystemOffset == 0: "in a hybrid image" else:
          "appended after an AI01 marker"))]
      if filename.hasAppImageExtension:
        evidence.add VextDetectionEvidence(description:
          "file extension is .AppImage")
      return @[VextDetectionCandidate(typeId: AppImageType1TypeId,
        confidence: vdcCertain, evidence: evidence,
        derivation: baseDerivation(AppImageType1TypeId))]
    except ValueError, LibraryError:
      discard
  if data.len >= 11 and data[0] == 0x7f and data[1] == byte('E') and
      data[2] == byte('L') and data[3] == byte('F') and
      data[8] == byte('A') and data[9] == byte('I') and data[10] == 2:
    try:
      discard parseAppImage(data)
      var evidence = @[VextDetectionEvidence(description:
        "file is a valid ELF with AI02 marker and an appended SquashFS 4 " &
        "filesystem containing AppRun")]
      if filename.hasAppImageExtension:
        evidence.add VextDetectionEvidence(description:
          "file extension is .AppImage")
      return @[VextDetectionCandidate(typeId: AppImageTypeId,
        confidence: vdcCertain, evidence: evidence,
        derivation: baseDerivation(AppImageTypeId))]
    except ValueError, LibraryError:
      discard
  # A structurally valid disc image is a terminal physical carrier. Recognize
  # it before running probes designed for much smaller standalone files; some
  # of those parsers necessarily allocate candidate output proportional to the
  # input before rejecting it.
  try:
    let image = probeIso9660(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid ISO 9660 primary volume descriptor, root directory, " &
      "and descriptor terminator in " & image.layout.iso9660LayoutName)]
    if hasIso9660Extension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .iso")
    return @[VextDetectionCandidate(typeId: Iso9660TypeId,
      confidence: vdcCertain, evidence: evidence,
      derivation: baseDerivation(Iso9660TypeId))]
  except ValueError:
    discard

  # Raw IMG has no universal magic. A complete FAT filesystem validation is
  # therefore the primary signal; the extension only strengthens confidence.
  try:
    let volume = parseFatDiskImage(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a consistent " & volume.kind.fatKindName &
      " BIOS parameter block, reserved FAT entries, " &
      "matching FAT copies, bounded directories, and valid cluster chains")]
    if filename.hasImgExtension:
      evidence.add VextDetectionEvidence(description:
        "file extension is .img, .ima, or .dsk")
    return @[VextDetectionCandidate(typeId: FatDiskImageTypeId,
      confidence: if filename.hasImgExtension: vdcProbable else: vdcPossible,
      evidence: evidence, derivation: baseDerivation(FatDiskImageTypeId))]
  except ValueError:
    discard

  if data.len in [D64StandardSize, D64StandardErrorSize, D64ExtendedSize,
      D64ExtendedErrorSize]:
    try:
      let disk = parseD64(data)
      var evidence = @[VextDetectionEvidence(description:
        "file has a valid " & $disk.tracks & "-track D64 BAM, directory, " &
        "and bounded file-sector chains")]
      if filename.hasD64Extension:
        evidence.add VextDetectionEvidence(description:
          "file extension is .d64")
      return @[VextDetectionCandidate(typeId: D64TypeId,
        confidence: if filename.hasD64Extension: vdcProbable else: vdcPossible,
        evidence: evidence, derivation: baseDerivation(D64TypeId))]
    except ValueError:
      discard

  if isDoomWad(data):
    let wad = parseDoomWad(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid " & wad.kind.doomWadKindName & " header and " &
      $wad.entries.len & " bounded directory entries")]
    if hasDoomWadExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .wad")
    result.add VextDetectionCandidate(typeId: DoomWadTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isElectronAsar(data):
    let archive = parseElectronAsar(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has valid ASAR Pickle framing, a JSON file manifest, and " &
      $archive.entries.len & " bounded entries")]
    if hasElectronAsarExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .asar")
    result.add VextDetectionCandidate(typeId: ElectronAsarTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isAmigaDiskfontIndex(data):
    let index = parseAmigaDiskfontIndex(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid " & (if index.tagged: "TFCH_ID" else: "FCH_ID") &
      " bitmap font index with " & $index.entries.len &
          " size entry or entries")]
    if filename.splitFile.ext.toLowerAscii == ".font":
      evidence.add VextDetectionEvidence(description: "file extension is .font")
    result.add VextDetectionCandidate(typeId: AmigaDiskfontIndexTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isAmigaDiskfont(data):
    let font = parseAmigaDiskfont(data)
    result.add VextDetectionCandidate(typeId: AmigaDiskfontTypeId,
      confidence: vdcCertain, evidence: @[
        VextDetectionEvidence(description:
      "file has a loadable Amiga hunk containing a valid DFH_ID bitmap " &
      "font descriptor with " & $font.glyphs.len & " bounded glyphs")])

  if isAmigaLhaSfx(data):
    result.add VextDetectionCandidate(typeId: AmigaLhaSfxTypeId,
      confidence: vdcCertain, evidence: @[
        VextDetectionEvidence(description:
      "file is a valid Amiga Hunk executable with appended LHA archives")])

  if isAmigaHunkExecutable(data):
    result.add VextDetectionCandidate(typeId: AmigaHunkExecutableTypeId,
      confidence: vdcCertain, evidence: @[
        VextDetectionEvidence(description:
      "file has a valid Amiga HUNK_HEADER and loadable hunk sequence")])

  if isWorkbenchIcon(data):
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid Workbench DiskObject header and serialized resources")]
    if hasWorkbenchIconExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .info")
    result.add VextDetectionCandidate(typeId: AmigaWorkbenchIconTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isGif(data):
    let image = parseGif(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid " & image.version & " block stream with " &
        $image.frames.len & " image frame(s)")]
    if hasGifExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .gif")
    result.add VextDetectionCandidate(typeId: GifTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isFlic(data):
    let animation = parseFlic(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a recognized FLIC magic and a valid chunk stream " &
        "containing " & $animation.frameCount & " frame(s)")]
    if hasFlicExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with the FLIC family")
    result.add VextDetectionCandidate(typeId: FlicTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isPng(data):
    let image = parsePng(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid PNG signature and CRC-checked " &
        $image.width & "x" & $image.height & " chunk stream")]
    if hasPngExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .png")
    result.add VextDetectionCandidate(typeId: PngTypeId,
      confidence: vdcCertain, evidence: evidence)

  try:
    let image = parseJpeg(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has valid JPEG marker framing and an " & $image.width & "x" &
      $image.height & " eight-bit DCT frame")]
    if hasJpegExtension(filename):
      evidence.add VextDetectionEvidence(description:
        "filename uses a conventional JPEG extension")
    result.add VextDetectionCandidate(typeId: JpegTypeId,
      confidence: vdcCertain, evidence: evidence)
  except ValueError:
    discard

  if isQoi(data):
    let image = parseQoi(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid qoif header and complete " &
        $image.width & "x" & $image.height & " chunk stream")]
    if hasQoiExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .qoi")
    result.add VextDetectionCandidate(typeId: QoiTypeId,
      confidence: vdcCertain, evidence: evidence)

  let koalaExtension = filename.splitFile.ext.toLowerAscii
  let koalaExactSize = data.len == KoalaPainterFileSize
  let koalaLoadAddress = if data.len >= 2:
      int(data[0]) or (int(data[1]) shl 8)
    else: -1
  let koalaCandidate = data.len >= KoalaPainterFileSize and
    ((koalaExactSize and (koalaLoadAddress == KoalaPainterLoadAddress or
      koalaExtension in [".koa", ".koala"])) or
     koalaExtension == ".koala")
  if koalaCandidate and isKoalaPainter(data):
    let extension = koalaExtension
    let exactSize = koalaExactSize
    let conventionalExtension = hasKoalaPainterExtension(filename)
    var evidence = @[VextDetectionEvidence(description:
      "file contains a complete 10003-byte KoalaPainter payload")]
    if data.len > KoalaPainterFileSize:
      evidence.add VextDetectionEvidence(description:
        "file has " & $(data.len - KoalaPainterFileSize) &
        " trailing byte(s) after the image payload")
    if conventionalExtension:
      evidence.add VextDetectionEvidence(description:
        "filename uses a conventional .kla, .koa, .koala, or .prg extension")
    let confidence =
      if exactSize and extension in [".koa", ".koala"]: vdcProbable
      elif exactSize and conventionalExtension and
          koalaLoadAddress == KoalaPainterLoadAddress:
        vdcProbable
      else: vdcPossible
    result.add VextDetectionCandidate(typeId: KoalaPainterTypeId,
      confidence: confidence, evidence: evidence)

  if isNetpbm(data):
    let source = parseNetpbm(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid NetPBM P" &
        $ord(source.images[0].variant) & " stream containing " &
        $source.images.len & " image(s)")]
    if hasNetpbmExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with NetPBM")
    result.add VextDetectionCandidate(typeId: NetpbmTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isBmp(data):
    let image = parseBmp(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a BM signature and valid " & $image.width & "x" &
        $image.height & " DIB structure")]
    if hasBmpExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .bmp")
    result.add VextDetectionCandidate(typeId: BmpTypeId,
      confidence: vdcCertain, evidence: evidence)
  elif isDib(data):
    let image = parseDib(data)
    var evidence = @[VextDetectionEvidence(
      description: "file begins with a supported DIB header describing " &
        $image.width & "x" & $image.height & " bitmap data")]
    if hasDibExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .dib")
    result.add VextDetectionCandidate(typeId: DibTypeId,
      confidence: vdcProbable, evidence: evidence)

  if isWindowsIcon(data):
    let icon = parseWindowsIcon(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid " & (if icon.kind == wikIcon: "ICO" else: "CUR") &
      " directory with " & $icon.entries.len &
          " bounded image entry or entries")]
    if hasWindowsIconExtension(filename, icon.kind):
      evidence.add VextDetectionEvidence(description:
        "file extension matches the container type")
    result.add VextDetectionCandidate(typeId: icon.windowsIconTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isPcx(data):
    let image = parsePcx(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid PCX header describing " & $image.width &
        "x" & $image.height & " image data")]
    if hasPcxExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .pcx")
    result.add VextDetectionCandidate(typeId: PcxTypeId,
      confidence: vdcProbable, evidence: evidence)

  if isFzx(data):
    let font = parseFzx(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid relative FZX character table and " &
      $font.glyphs.len & " bounded bitmap definition(s)")]
    let extension = hasFzxExtension(filename)
    if extension:
      evidence.add VextDetectionEvidence(description: "file extension is .fzx")
    result.add VextDetectionCandidate(typeId: FzxTypeId,
      confidence: if extension: vdcProbable else: vdcPossible,
      evidence: evidence)

  if isBmFont(data):
    let font = parseBmFont(data)
    let encoding = case font.encoding
      of bfeText: "text"
      of bfeXml: "XML"
      of bfeBinary: "binary"
    var evidence = @[VextDetectionEvidence(description:
      "file is an AngelCode BMFont " & encoding & " descriptor")]
    let countsMatch = font.encoding != bfeText or
      (font.declaredCharacters == font.characters.len and
       font.declaredKernings == font.kernings.len)
    if not countsMatch:
      evidence.add VextDetectionEvidence(description:
        "declared character or kerning count differs from parsed records")
    if filename.splitFile.ext.toLowerAscii == ".fnt":
      evidence.add VextDetectionEvidence(description: "file extension is .fnt")
    result.add VextDetectionCandidate(typeId: BmFontTypeId,
      confidence: if countsMatch: vdcCertain
        else: vdcProbable,
      evidence: evidence)

  if isTga(data):
    let image = parseTga(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid TGA header and complete " & $image.width &
        "x" & $image.height & " image stream")]
    if hasTgaExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with TGA")
    result.add VextDetectionCandidate(typeId: TgaTypeId,
      confidence: vdcProbable, evidence: evidence)

  if isWav(data):
    let sound = parseWav(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid RIFF/WAVE integer PCM stream with " &
        $sound.channelCount & " channel(s) at " & $sound.sampleRate & " Hz")]
    if hasWavExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .wav or .wave")
    result.add VextDetectionCandidate(typeId: WavTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isCreativeVoice(data):
    let sound = parseCreativeVoice(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid Creative Voice header and bounded PCM/ADPCM " &
      "block stream at " & $sound.sampleRate & " Hz")]
    if hasCreativeVoiceExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .voc")
    result.add VextDetectionCandidate(typeId: CreativeVoiceTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isPaintNetPalette(data):
    let source = parsePaintNetPalette(data)
    var evidence = @[VextDetectionEvidence(description:
      "file begins with the Paint.NET palette magic comment and contains " &
      $source.palette.colours.len & " valid ARGB colour entries")]
    if hasPaintNetPaletteExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .txt")
    result.add VextDetectionCandidate(typeId: PaintNetPaletteTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isGimpPalette(data):
    let source = parseGimpPalette(data)
    var evidence = @[VextDetectionEvidence(description:
      "file begins with the GIMP palette magic identifier and contains " &
      $source.palette.colours.len & " valid " &
      (if source.hasAlpha: "Aseprite RGBA" else: "RGB") &
      " colour entries")]
    if hasGimpPaletteExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .gpl")
    result.add VextDetectionCandidate(typeId: GimpPaletteTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isJascPalette(data):
    let palette = parseJascPalette(data)
    var evidence = @[VextDetectionEvidence(description:
      "file begins with JASC-PAL, declares version 0100, and contains " &
      $palette.colours.len & " bounded RGB colour entries")]
    if filename.hasJascPaletteExtension:
      evidence.add VextDetectionEvidence(description: "file extension is .pal")
    result.add VextDetectionCandidate(typeId: JascPaletteTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isAseprite(data):
    let source = parseAseprite(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid Aseprite header and " & $source.frames &
      " structurally complete frame(s)")]
    if hasAsepriteExtension(filename):
      evidence.add VextDetectionEvidence(description:
        "file extension is .ase or .aseprite")
    result.add VextDetectionCandidate(typeId: AsepriteTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isAdobeSwatchExchange(data):
    let source = parseAdobeSwatchExchange(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid ASEF version 1.0 header and " &
      $source.blockCount & " complete block(s)")]
    if hasAdobeSwatchExchangeExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .ase")
    result.add VextDetectionCandidate(typeId: AdobeSwatchExchangeTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isProtrackerMod(data):
    let source = parseProtrackerMod(data)
    var evidence = @[VextDetectionEvidence(description:
      "file has a valid " & (if source.sampleCount == 31:
        source.signature & " 31-sample" else: "unmarked 15-sample") &
      " MOD structure with " & $source.module.channels.len & " channel(s), " &
      $source.module.patterns.len & " pattern(s), and exact sample lengths")]
    if hasProtrackerModExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .mod")
    result.add VextDetectionCandidate(typeId: ProtrackerModTypeId,
      confidence: if source.sampleCount == 31: vdcCertain else: vdcProbable,
      evidence: evidence)

  if isZipArchive(data):
    let archive = parseZipArchive(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid single-volume ZIP central directory and " &
        $archive.entries.len & " valid entry or entries")]
    if hasZipExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .zip")
    result.add VextDetectionCandidate(
      typeId: ZipArchiveTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isLhaArchiveStructure(data):
    var evidence = @[VextDetectionEvidence(
      description: "file has valid checksummed LHA member framing")]
    if hasLhaExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .lha or .lzh")
    result.add VextDetectionCandidate(typeId: LhaArchiveTypeId,
      confidence: vdcCertain, evidence: evidence)

  if isAmigaAdf(data):
    let volume = parseAmigaAdf(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid DOS boot signature and checksummed " &
        volume.filesystem & " root filesystem block")]
    if data.len == AmigaAdfDdSize:
      evidence.add VextDetectionEvidence(
        description: "file size is exactly 901120 bytes (Amiga DD floppy)")
    elif data.len == AmigaAdfHdSize:
      evidence.add VextDetectionEvidence(
        description: "file size is exactly 1802240 bytes (Amiga HD floppy)")
    if hasAmigaAdfExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .adf")
    result.add VextDetectionCandidate(
      typeId: AmigaAdfTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAmigaDms(data):
    let archive = parseAmigaDms(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a DMS! identifier and a complete framed stream of " &
        $archive.tracks.len & " track(s)")]
    if hasAmigaDmsExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .dms or .fms")
    result.add VextDetectionCandidate(
      typeId: AmigaDmsTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isXpk(data):
    let archive = parseXpk(data)
    result.add VextDetectionCandidate(
      typeId: XpkTypeId,
      confidence: vdcCertain,
      evidence: @[VextDetectionEvidence(
        description: "file has a checksummed XPKF " & archive.compression &
          " chunk stream")])

  if isPowerPacker(data):
    let archive = parsePowerPacker(data)
    result.add VextDetectionCandidate(
      typeId: PowerPackerTypeId,
      confidence: vdcCertain,
      evidence: @[VextDetectionEvidence(
        description: "file has a valid " & archive.version &
          " PowerPacker header and efficiency table")])

  if isAmiga16sv(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM 16SV sampled instrument")]
    if hasAmiga16svExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with 16SV")
    result.add VextDetectionCandidate(
      typeId: Amiga16svTypeId, confidence: vdcCertain, evidence: evidence)
  elif isAmiga8svx(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM 8SVX sampled instrument")]
    if hasAmiga8svxExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with 8SVX")
    result.add VextDetectionCandidate(
      typeId: Amiga8svxTypeId, confidence: vdcCertain, evidence: evidence)
  elif isAmigaAnim(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM ANIM containing ILBM frame forms")]
    if hasAmigaAnimExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with ANIM")
    result.add VextDetectionCandidate(
      typeId: AmigaAnimTypeId,
      confidence: vdcCertain,
      evidence: evidence)
  elif isAmigaDeep(data):
    let deep = parseAmigaDeep(data)
    var evidence = @[VextDetectionEvidence(description:
      "file is a valid FORM DEEP direct-colour image with " &
      $deep.frames.len & " frame(s)")]
    if hasAmigaDeepExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with IFF DEEP")
    result.add VextDetectionCandidate(typeId: AmigaDeepTypeId,
      confidence: vdcCertain, evidence: evidence)
  elif isAmigaPbm(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM PBM packed eight-bit image")]
    if hasAmigaPbmExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with IFF PBM")
    result.add VextDetectionCandidate(typeId: AmigaPbmTypeId,
      confidence: vdcCertain, evidence: evidence)
  elif isAmigaAcbm(data):
    let acbm = parseAmigaAcbm(data)
    var evidence = @[VextDetectionEvidence(description:
      if acbm.image.hasBitmap:
        "file is a valid FORM ACBM with BMHD and ABIT chunks"
      else:
        "file is a valid palette-only FORM ACBM with a CMAP chunk")]
    if hasAmigaAcbmExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with ACBM")
    result.add VextDetectionCandidate(
      typeId: AmigaAcbmTypeId,
      confidence: vdcCertain,
      evidence: evidence)
  elif isAmigaDr2d(data):
    let drawing = parseAmigaDr2d(data)
    var evidence = @[VextDetectionEvidence(description:
      "file is a valid FORM DR2D drawing with " & $drawing.pathCount &
      " vector path(s)")]
    if hasAmigaDr2dExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with IFF DR2D")
    result.add VextDetectionCandidate(typeId: AmigaDr2dTypeId,
      confidence: vdcCertain, evidence: evidence)
  elif isAmigaIlbm(data):
    let ilbm = parseAmigaIlbm(data)
    var evidence = @[VextDetectionEvidence(description:
      if ilbm.image.hasBitmap:
        "file is a valid FORM ILBM with BMHD and BODY chunks"
      else:
        "file is a valid palette-only FORM ILBM with a CMAP chunk")]
    if hasAmigaIlbmExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with ILBM")
    result.add VextDetectionCandidate(
      typeId: AmigaIlbmTypeId,
      confidence: vdcCertain,
      evidence: evidence)
  elif isAmigaIff(data):
    let form = parseAmigaIff(data)
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM " & form.formType & " container")]
    if hasAmigaIffExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with IFF")
    result.add VextDetectionCandidate(
      typeId: AmigaIffTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAmosProgram(data):
    let program = parseAmosProgram(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid " & program.header &
        " header, tokenised listing boundary, and AmBs appendix")]
    if hasAmosProgramExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .amos")
    result.add VextDetectionCandidate(
      typeId: AmosProgramTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAmosBankSet(data):
    let bankSet = parseAmosBankSet(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid AmBs identifier and " &
        $bankSet.banks.len & " valid bank member(s)")]
    if hasAmosBankSetExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .abs")
    result.add VextDetectionCandidate(
      typeId: AmosBankSetTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAmosBank(data):
    let bank = parseAmosBank(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid AmBk identifier and " & bank.bankType &
        " bank structure")]
    if hasAmosBankExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .abk")
    result.add VextDetectionCandidate(
      typeId: AmosBankTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAmosSpriteIconBank(data):
    let bank = parseAmosSpriteIconBank(data)
    let identifier =
      if bank.kind == asibkSprite: AmosSpriteBankMagic else: AmosIconBankMagic
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid " & identifier &
        " identifier and sprite/icon bank structure")]
    if hasAmosSpriteIconBankExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .abk")
    result.add VextDetectionCandidate(
      typeId: bank.amosSpriteIconBankTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  if isAnsiArt(data):
    let source = parseAnsiArt(data)
    var evidence = @[VextDetectionEvidence(description:
      "file contains " & $source.meaningfulSequences &
      " presentation-affecting ANSI control sequence(s)")]
    if source.sauce.present:
      evidence.add VextDetectionEvidence(description:
        "valid SAUCE record classifies the payload as Character/ANSI")
    if hasAnsiArtExtension(filename):
      evidence.add VextDetectionEvidence(description:
        "file extension is associated with ANSI or character art")
    result.add VextDetectionCandidate(typeId: AnsiArtTypeId,
      confidence: if source.sauce.present: vdcCertain else: vdcProbable,
      evidence: evidence)

  if isZxSpectrumScreenDump(data):
    var evidence = @[VextDetectionEvidence(description:
      if data.len == ZxSpectrumScreenSize:
        "file size is exactly 6912 bytes"
      else:
        "valid 128-byte +3DOS CODE header declares a 6912-byte screen at address 16384")]
    if hasZxSpectrumScreenDumpExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .scr")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumScreenTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  if filename.hasZxSpectrumGigascreenExtension and
      isZxSpectrumGigascreen(data):
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumGigascreenTypeId,
      confidence: vdcProbable,
      evidence: @[
        VextDetectionEvidence(description: "file size is exactly 7680 bytes"),
        VextDetectionEvidence(description: "file extension is .scr"),
        VextDetectionEvidence(description:
          "file does not begin with a DOS executable header")])

  if (filename.hasZxSpectrumNextImageExtension and
      isZxSpectrumNextImage(data)) or
      (filename.hasZxSpectrumNextSl2Extension and
      isZxSpectrumNextSl2Image(data)):
    let extension = if filename.hasZxSpectrumNextSl2Extension: ".sl2" else: ".nxi"
    var evidence = @[
      VextDetectionEvidence(description: "file size is exactly " &
        $data.len & " bytes for a recognized Layer 2 layout"),
      VextDetectionEvidence(description: "file extension is " & extension)]
    if data.len == ZxSpectrumNextSmallPlus3DosSize:
      evidence.add VextDetectionEvidence(description:
        "leading 128-byte +3DOS signature, length, reserved bytes, and checksum validate")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumNextImageTypeId,
      confidence: vdcProbable,
      evidence: evidence)

  if isZxSpectrumSnapshotSize(data.len):
    var evidence = @[VextDetectionEvidence(
      description: "file size is exactly " & $data.len & " bytes")]
    if filename.hasZxSpectrumSnapshotExtension:
      let extension = filename.splitFile.ext.toLowerAscii
      evidence.add VextDetectionEvidence(
        description: "file extension is " & extension)
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumSnapshotTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  if isZxSpectrumTap(data):
    var evidence = @[VextDetectionEvidence(
      description: "TAP block lengths exactly frame the source")]
    let extension = filename.splitFile.ext.toLowerAscii
    if extension in [".tap", ".tape"]:
      evidence.add VextDetectionEvidence(
        description: "file extension is " & extension)
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumTapTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  if isZxSpectrumTzx(data):
    let tzx = parseZxSpectrumTzx(data)
    var evidence = @[VextDetectionEvidence(
      description: "TZX signature, version, and complete block structure are valid")]
    if filename.splitFile.ext.toLowerAscii == ".tzx":
      evidence.add VextDetectionEvidence(description: "file extension is .tzx")
    evidence.add VextDetectionEvidence(description:
      $tzx.blockCount & " TZX blocks were structurally validated")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumTzxTypeId,
      confidence: vdcCertain,
      evidence: evidence)

  # Headerless WordStar is necessarily heuristic and remains behind stronger
  # fixed-layout formats. A valid version-5-or-later header is independently
  # strong even though this probe shares the same late position.
  if isWordStar(data):
    let source = parseWordStar(data)
    var evidence: seq[VextDetectionEvidence]
    if source.hasHeader:
      evidence.add VextDetectionEvidence(description:
        "valid WordStar " & source.versionName &
        " symmetrical header and bounded document stream")
    else:
      evidence.add VextDetectionEvidence(description:
        "headerless stream has WordStar returns and format-specific " &
        "high-bit or control semantics")
    if source.eofPaddingBytes > 0:
      evidence.add VextDetectionEvidence(description:
        "document ends with " & $source.eofPaddingBytes &
        " WordStar/CP/M EOF padding byte(s)")
    if filename.hasWordStarExtension:
      evidence.add VextDetectionEvidence(description:
        "filename uses a WordStar-associated extension")
    result.add VextDetectionCandidate(typeId: WordStarTypeId,
      confidence: if source.hasHeader: vdcCertain
        elif filename.hasWordStarExtension: vdcProbable else: vdcPossible,
      evidence: evidence)

  # This deliberately weak, extension-dependent detector stays last so a
  # stronger format remains the preferred candidate for ambiguous bytes.
  if filename.hasRgba8PaletteExtension and isRgba8Palette(data):
    let palette = parseRgba8Palette(data)
    result.add VextDetectionCandidate(
      typeId: Rgba8PaletteTypeId,
      confidence: vdcPossible,
      evidence: @[
        VextDetectionEvidence(description: "file extension is .pal"),
        VextDetectionEvidence(description: "little-endian colour count and " &
          "exact RGBA8 payload size describe " & $palette.colours.len &
          " colours")])

  if filename.hasZxSpectrumNextPaletteExtension and
      isZxSpectrumNextPalette(data):
    let source = parseZxSpectrumNextPalette(data)
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumNextPaletteTypeId,
      confidence: if filename.hasZxSpectrumNextNxpExtension or
          filename.hasZxSpectrumNextNplExtension: vdcProbable
        else: vdcPossible,
      evidence: @[
        VextDetectionEvidence(description:
          if filename.hasZxSpectrumNextNxpExtension: "file extension is .nxp"
          elif filename.hasZxSpectrumNextNplExtension: "file extension is .npl"
          else: "file extension is .pal"),
        VextDetectionEvidence(description: "exact payload size and " &
          $(source.bitsPerColour) & "-bit RGB palette encoding describe " &
          $source.palette.colours.len & " colours" &
          (if source.transparentIndex >= 0:
            " with transparent index " & $source.transparentIndex else: ""))])

  if filename.hasAdobeColorTableExtension and isAdobeColorTable(data):
    result.add VextDetectionCandidate(typeId: AdobeColorTableTypeId,
      confidence: vdcProbable,
      evidence: @[
        VextDetectionEvidence(description: "file extension is .act"),
        VextDetectionEvidence(description:
          "exact 768-byte size describes 256 consecutive RGB8 triplets")])

  for candidate in result:
    if formatHandler(candidate.typeId).isNil:
      raise newException(Defect,
        "detector returned an unregistered input format: " & candidate.typeId)

  for candidate in result.mitems:
    candidate.support = formatHandler(candidate.typeId)[].support
    candidate.derivation = baseDerivation(candidate.typeId)

proc applyFormatRefiners*(filename: string, data: openArray[byte],
    carrier: VextDetectedFormat, refiners: openArray[VextFormatRefiner],
    depth = 0): seq[VextDetectedFormat] =
  ## Applies semantic refiners to an already parsed physical or semantic
  ## carrier. More-specific descendants precede their immediate parent.
  if depth >= 8: return
  for refiner in refiners:
    if refiner.carrierTypeId != carrier.candidate.typeId or
        (refiner.probe.isNil and refiner.sourceProbe.isNil):
      continue
    var repeated = false
    for stage in carrier.candidate.derivation.stages:
      if stage.typeId == refiner.typeId: repeated = true
    if repeated: continue
    var matched: VextRefinementMatch
    if not refiner.probe.isNil:
      matched = refiner.probe(filename, data, carrier.parsed)
    else:
      let source = memoryByteSource(@data, filename)
      try:
        matched = refiner.sourceProbe(filename, source, carrier.parsed)
      finally:
        source.close()
    if not matched.matched and matched.parsed.isNil: continue
    let target = formatHandler(refiner.typeId)
    let support = if target.isNil:
        (if matched.parsed.isNil: vfsDetectionOnly else: vfsInspectable)
      else: target[].support
    if support == vfsInspectable and matched.parsed.isNil:
      raise newException(Defect,
        "inspectable semantic refinement produced no parsed value: " &
          refiner.typeId)
    let refined = VextDetectedFormat(candidate: VextDetectionCandidate(
      typeId: refiner.typeId, support: support,
      confidence: matched.confidence,
      evidence: matched.evidence,
      derivation: carrier.candidate.derivation.refinedDerivation(
          refiner.typeId)),
      parsed: matched.parsed)
    if not refined.parsed.isNil:
      result.add applyFormatRefiners(filename, data, refined, refiners,
        depth + 1)
    result.add refined

proc applySourceFormatRefiners*(filename: string, source: VextByteSource,
    carrier: VextDetectedFormat, refiners: openArray[VextFormatRefiner],
    depth = 0): seq[VextDetectedFormat] =
  ## Applies refiners which explicitly support bounded random-access carrier
  ## evidence. Incremental sessions use this without materializing the carrier.
  if depth >= 8: return
  for refiner in refiners:
    if refiner.carrierTypeId != carrier.candidate.typeId or
        refiner.sourceProbe.isNil:
      continue
    var repeated = false
    for stage in carrier.candidate.derivation.stages:
      if stage.typeId == refiner.typeId: repeated = true
    if repeated: continue
    let matched = refiner.sourceProbe(filename, source, carrier.parsed)
    if not matched.matched and matched.parsed.isNil: continue
    let target = formatHandler(refiner.typeId)
    let support = if target.isNil:
        (if matched.parsed.isNil: vfsDetectionOnly else: vfsInspectable)
      else: target[].support
    if support == vfsInspectable and matched.parsed.isNil:
      raise newException(Defect,
        "inspectable source refinement produced no parsed value: " &
          refiner.typeId)
    let refined = VextDetectedFormat(candidate: VextDetectionCandidate(
      typeId: refiner.typeId, support: support,
      confidence: matched.confidence, evidence: matched.evidence,
      derivation: carrier.candidate.derivation.refinedDerivation(
        refiner.typeId)), parsed: matched.parsed)
    if not refined.parsed.isNil:
      result.add applySourceFormatRefiners(filename, source, refined,
        refiners, depth + 1)
    result.add refined

proc detectParsedFormatsWith*(input: VextDetectionInput,
    refiners: openArray[VextFormatRefiner]): seq[VextDetectedFormat] =
  ## Detection entry point used by the registered path and focused tests.
  ## Every inspectable base parser runs once; detection-only matches retain no
  ## fabricated parsed value. Refiners receive and may retain parsed carriers.
  for baseCandidate in detectBaseFormats(input):
    var candidate = baseCandidate
    let handler = formatHandler(candidate.typeId)
    if handler.isNil:
      raise newException(Defect,
        "detector returned an unregistered input format: " & candidate.typeId)
    candidate.support = handler[].support
    if candidate.derivation.stages.len == 0:
      candidate.derivation = baseDerivation(candidate.typeId)
    if not handler[].isInspectable:
      result.add VextDetectedFormat(candidate: candidate)
      continue
    let data = input.completeBytes
    let carrier = VextDetectedFormat(candidate: candidate,
      parsed: handler[].parse(data))
    result.add applyFormatRefiners(input.filename, data, carrier, refiners)
    result.add carrier

proc detectParsedFormats*(input: VextDetectionInput):
    seq[VextDetectedFormat] =
  ## Detects physical formats plus registered semantic refinements.
  let refiners = formatRefiners()
  for refiner in refiners:
    let target = formatHandler(refiner.typeId)
    if target.isNil or target[].carrierTypeId != refiner.carrierTypeId:
      raise newException(Defect,
        "refiner does not match its registered semantic handler: " &
          refiner.typeId)
    if refiner.probe.isNil and refiner.sourceProbe.isNil:
      raise newException(Defect,
        "refiner has no evidence probe: " & refiner.typeId)
  detectParsedFormatsWith(input, refiners)

proc detectParsedFormatsWith*(filename: string, data: openArray[byte],
    refiners: openArray[VextFormatRefiner]): seq[VextDetectedFormat] =
  ## Compatibility entry point for callers that already own complete bytes.
  detectParsedFormatsWith(newDetectionInput(filename, data), refiners)

proc detectParsedFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectedFormat] =
  ## Compatibility entry point for callers that already own complete bytes.
  detectParsedFormats(newDetectionInput(filename, data))

proc detectFormats*(input: VextDetectionInput):
    seq[VextDetectionCandidate] =
  for detected in detectParsedFormats(input):
    result.add detected.candidate

proc detectFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectionCandidate] =
  ## Compatibility entry point for callers that already own complete bytes.
  detectFormats(newDetectionInput(filename, data))

proc forceFormatWithDepth(input: VextDetectionInput,
    typeId: string, refiners: openArray[VextFormatRefiner],
    depth: int): VextDetectedFormat =
  ## Forces either a physical handler or a semantic refinement. Forcing a
  ## physical carrier deliberately bypasses its refiners.
  if depth >= 8:
    raise newException(ValueError,
      "format refinement exceeds the maximum derivation depth")
  let direct = formatHandler(typeId)
  if not direct.isNil and direct[].carrierTypeId.len == 0:
    if not direct[].isInspectable:
      for baseCandidate in detectBaseFormats(input):
        var candidate = baseCandidate
        if candidate.typeId == typeId:
          candidate.support = direct[].support
          if candidate.derivation.stages.len == 0:
            candidate.derivation = baseDerivation(candidate.typeId)
          return VextDetectedFormat(candidate: candidate)
      raise newException(ValueError,
        "input does not match forced format: " & typeId)
    let data = input.completeBytes
    result = VextDetectedFormat(candidate: VextDetectionCandidate(
      typeId: typeId,
      confidence: vdcProbable, evidence: @[VextDetectionEvidence(
        description: "format selected by the caller")],
      derivation: baseDerivation(typeId)), parsed: direct[].parse(data))
    return
  for refiner in refiners:
    if refiner.typeId != typeId: continue
    let data = input.completeBytes
    let carrierHandler = formatHandler(refiner.carrierTypeId)
    let carrier = if not carrierHandler.isNil and
        carrierHandler[].carrierTypeId.len == 0:
        VextDetectedFormat(candidate: VextDetectionCandidate(
          typeId: refiner.carrierTypeId, confidence: vdcProbable,
          evidence: @[VextDetectionEvidence(description:
            "carrier selected for a forced semantic format")],
          derivation: baseDerivation(refiner.carrierTypeId)),
          parsed: carrierHandler[].parse(data))
      else:
        forceFormatWithDepth(input, refiner.carrierTypeId, refiners,
          depth + 1)
    for refined in applyFormatRefiners(input.filename, data, carrier, refiners):
      if refined.candidate.typeId == typeId: return refined
    raise newException(ValueError,
      "input does not match forced format: " & typeId)
  raise newException(ValueError, "unsupported input format: " & typeId)

proc forceFormatWith*(input: VextDetectionInput, typeId: string,
    refiners: openArray[VextFormatRefiner]): VextDetectedFormat =
  forceFormatWithDepth(input, typeId, refiners, 0)

proc forceFormat*(input: VextDetectionInput,
    typeId: string): VextDetectedFormat =
  forceFormatWith(input, typeId, formatRefiners())

proc forceFormatWith*(filename: string, data: openArray[byte], typeId: string,
    refiners: openArray[VextFormatRefiner]): VextDetectedFormat =
  ## Compatibility entry point for callers that already own complete bytes.
  forceFormatWith(newDetectionInput(filename, data), typeId, refiners)

proc forceFormat*(filename: string, data: openArray[byte],
    typeId: string): VextDetectedFormat =
  ## Compatibility entry point for callers that already own complete bytes.
  forceFormat(newDetectionInput(filename, data), typeId)
