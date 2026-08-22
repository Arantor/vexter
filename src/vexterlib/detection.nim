## Evidence-based input format detection.

import std/[os, strutils]
import ./handler_registry
import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim, amiga_dms, amiga_iff, amiga_ilbm, amiga_pbm, amiga_workbench_icon, amos_bank, amos_bank_set, amos_program,
  amos_sprite_icon_bank, bmp, flic, gif_container, netpbm, pcx, png_container, qoi, tga,
  wav, zip_archive, lha_archive, zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
import ./containers/xpk_shri
import ./containers/powerpacker
import ./resources/zx_spectrum_screen

type
  VextDetectionConfidence* = enum
    vdcPossible
    vdcProbable
    vdcCertain

  VextDetectionEvidence* = object
    description*: string

  VextDetectionCandidate* = object
    typeId*: string
    confidence*: VextDetectionConfidence
    evidence*: seq[VextDetectionEvidence]

  VextDetectedFormat* = object
    candidate*: VextDetectionCandidate
    parsed*: VextParsedContainer

proc `$`*(confidence: VextDetectionConfidence): string =
  case confidence
  of vdcPossible: "possible"
  of vdcProbable: "probable"
  of vdcCertain: "certain"

proc detectFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectionCandidate] =
  ## Returns every format candidate recognized from currently available
  ## evidence, ordered from strongest to weakest.
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

  if isQoi(data):
    let image = parseQoi(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid qoif header and complete " &
        $image.width & "x" & $image.height & " chunk stream")]
    if hasQoiExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .qoi")
    result.add VextDetectionCandidate(typeId: QoiTypeId,
      confidence: vdcCertain, evidence: evidence)

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

  if isPcx(data):
    let image = parsePcx(data)
    var evidence = @[VextDetectionEvidence(
      description: "file has a valid PCX header describing " & $image.width &
        "x" & $image.height & " image data")]
    if hasPcxExtension(filename):
      evidence.add VextDetectionEvidence(description: "file extension is .pcx")
    result.add VextDetectionCandidate(typeId: PcxTypeId,
      confidence: vdcProbable, evidence: evidence)

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
      description: "file has valid checksummed level-0 LHA member framing")]
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
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM ACBM with BMHD and ABIT chunks")]
    if hasAmigaAcbmExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with ACBM")
    result.add VextDetectionCandidate(
      typeId: AmigaAcbmTypeId,
      confidence: vdcCertain,
      evidence: evidence)
  elif isAmigaIlbm(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM ILBM with BMHD and BODY chunks")]
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

proc detectParsedFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectedFormat] =
  ## Detects formats and retains each parsed container for later inspection.
  for candidate in detectFormats(filename, data):
    let handler = formatHandler(candidate.typeId)
    result.add VextDetectedFormat(candidate: candidate,
      parsed: handler[].parse(data))
