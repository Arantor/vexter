## Evidence-based input format detection.

import std/[os, strutils]
import ./handler_registry
import ./format_detection_types
export format_detection_types
import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_diskfont, amiga_dms, amiga_hunk_executable, amiga_iff, amiga_ilbm, amiga_lha_sfx, amiga_pbm, amiga_workbench_icon, amos_bank, amos_bank_set, amos_program,
  adobe_swatch_exchange, amos_sprite_icon_bank, ansi_art, appimage, aseprite, bmfont, bmp, creative_voice, doom_wad, electron_asar, flic, fzx, gif_container, gimp_palette, iso9660, jpeg, koala_painter, netpbm, paint_net_palette, pcx, png_container, protracker_mod, qoi, tga,
  wav, windows_icon, zip_archive, lha_archive, zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
import ./containers/xpk_shri
import ./containers/powerpacker
import ./resources/zx_spectrum_screen

type
  VextDetectedFormat* = object
    candidate*: VextDetectionCandidate
    parsed*: VextParsedContainer

proc detectBaseFormats(filename: string, data: openArray[byte]):
    seq[VextDetectionCandidate] =
  ## Returns every format candidate recognized from currently available
  ## evidence, ordered from strongest to weakest.
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
      " bitmap font index with " & $index.entries.len & " size entry or entries")]
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
      " directory with " & $icon.entries.len & " bounded image entry or entries")]
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
    var evidence = @[VextDetectionEvidence(
      description: "file size is exactly 6912 bytes")]
    if hasZxSpectrumScreenDumpExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is .scr")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumScreenTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  if isZxSpectrumSnapshotSize(data.len):
    var evidence = @[VextDetectionEvidence(
      description: "file size is exactly " & $data.len & " bytes")]
    if filename.splitFile.ext.toLowerAscii == ".sna":
      evidence.add VextDetectionEvidence(
        description: "file extension is .sna")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumSnapshotTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  if isZxSpectrumTap(data):
    var evidence = @[VextDetectionEvidence(
      description: "all TAP blocks have valid lengths and checksums")]
    if filename.splitFile.ext.toLowerAscii == ".tap":
      evidence.add VextDetectionEvidence(
        description: "file extension is .tap")
    result.add VextDetectionCandidate(
      typeId: ZxSpectrumTapTypeId,
      confidence: vdcProbable,
      evidence: evidence
    )

  for candidate in result:
    if formatHandler(candidate.typeId).isNil:
      raise newException(Defect,
        "detector returned an unregistered input format: " & candidate.typeId)

  for candidate in result.mitems:
    candidate.derivation = baseDerivation(candidate.typeId)

proc applyFormatRefiners*(filename: string, data: openArray[byte],
    carrier: VextDetectedFormat, refiners: openArray[VextFormatRefiner],
    depth = 0): seq[VextDetectedFormat] =
  ## Applies semantic refiners to an already parsed physical or semantic
  ## carrier. More-specific descendants precede their immediate parent.
  if depth >= 8: return
  for refiner in refiners:
    if refiner.carrierTypeId != carrier.candidate.typeId or
        refiner.probe.isNil:
      continue
    var repeated = false
    for stage in carrier.candidate.derivation.stages:
      if stage.typeId == refiner.typeId: repeated = true
    if repeated: continue
    let matched = refiner.probe(filename, data, carrier.parsed)
    if matched.parsed.isNil: continue
    let refined = VextDetectedFormat(candidate: VextDetectionCandidate(
      typeId: refiner.typeId, confidence: matched.confidence,
      evidence: matched.evidence,
      derivation: carrier.candidate.derivation.refinedDerivation(refiner.typeId)),
      parsed: matched.parsed)
    result.add applyFormatRefiners(filename, data, refined, refiners, depth + 1)
    result.add refined

proc detectParsedFormatsWith*(filename: string, data: openArray[byte],
    refiners: openArray[VextFormatRefiner]): seq[VextDetectedFormat] =
  ## Detection entry point used by the registered path and focused tests.
  ## Every base parser runs once; refiners receive and may retain that value.
  for candidate in detectBaseFormats(filename, data):
    let handler = formatHandler(candidate.typeId)
    let carrier = VextDetectedFormat(candidate: candidate,
      parsed: handler[].parse(data))
    result.add applyFormatRefiners(filename, data, carrier, refiners)
    result.add carrier

proc detectParsedFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectedFormat] =
  ## Detects physical formats plus registered semantic refinements.
  let refiners = formatRefiners()
  for refiner in refiners:
    let target = formatHandler(refiner.typeId)
    if target.isNil or target[].carrierTypeId != refiner.carrierTypeId:
      raise newException(Defect,
        "refiner does not match its registered semantic handler: " &
          refiner.typeId)
  detectParsedFormatsWith(filename, data, refiners)

proc detectFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectionCandidate] =
  for detected in detectParsedFormats(filename, data):
    result.add detected.candidate

proc forceFormatWithDepth(filename: string, data: openArray[byte],
    typeId: string, refiners: openArray[VextFormatRefiner],
    depth: int): VextDetectedFormat =
  ## Forces either a physical handler or a semantic refinement. Forcing a
  ## physical carrier deliberately bypasses its refiners.
  if depth >= 8:
    raise newException(ValueError,
      "format refinement exceeds the maximum derivation depth")
  let direct = formatHandler(typeId)
  if not direct.isNil and direct[].carrierTypeId.len == 0:
    result = VextDetectedFormat(candidate: VextDetectionCandidate(typeId: typeId,
      confidence: vdcProbable, evidence: @[VextDetectionEvidence(
        description: "format selected by the caller")],
      derivation: baseDerivation(typeId)), parsed: direct[].parse(data))
    return
  for refiner in refiners:
    if refiner.typeId != typeId: continue
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
        forceFormatWithDepth(filename, data, refiner.carrierTypeId, refiners,
          depth + 1)
    for refined in applyFormatRefiners(filename, data, carrier, refiners):
      if refined.candidate.typeId == typeId: return refined
    raise newException(ValueError,
      "input does not match forced format: " & typeId)
  raise newException(ValueError, "unsupported input format: " & typeId)

proc forceFormatWith*(filename: string, data: openArray[byte], typeId: string,
    refiners: openArray[VextFormatRefiner]): VextDetectedFormat =
  forceFormatWithDepth(filename, data, typeId, refiners, 0)

proc forceFormat*(filename: string, data: openArray[byte],
    typeId: string): VextDetectedFormat =
  forceFormatWith(filename, data, typeId, formatRefiners())
