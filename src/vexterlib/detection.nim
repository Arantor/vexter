## Evidence-based input format detection.

import std/[os, strutils]
import ./containers/[amiga_acbm, amiga_adf, amiga_anim, amiga_iff, amiga_ilbm, amos_bank, amos_bank_set, amos_program,
  amos_sprite_icon_bank, bmp, pcx,
  zip_archive, zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
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

proc `$`*(confidence: VextDetectionConfidence): string =
  case confidence
  of vdcPossible: "possible"
  of vdcProbable: "probable"
  of vdcCertain: "certain"

proc detectFormats*(filename: string, data: openArray[byte]):
    seq[VextDetectionCandidate] =
  ## Returns every format candidate recognized from currently available
  ## evidence, ordered from strongest to weakest.
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

  if isAmigaAnim(data):
    var evidence = @[VextDetectionEvidence(
      description: "file is a valid FORM ANIM containing ILBM frame forms")]
    if hasAmigaAnimExtension(filename):
      evidence.add VextDetectionEvidence(
        description: "file extension is associated with ANIM")
    result.add VextDetectionCandidate(
      typeId: AmigaAnimTypeId,
      confidence: vdcCertain,
      evidence: evidence)
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
