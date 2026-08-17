## Evidence-based input format detection.

import std/[os, strutils]
import ./containers/[amos_bank, amos_sprite_icon_bank,
  zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap]
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
