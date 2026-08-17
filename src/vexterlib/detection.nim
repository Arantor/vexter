## Evidence-based input format detection.

import std/[os, strutils]
import ./containers/[zx_spectrum_screen, zx_spectrum_snapshot, zx_spectrum_tap]

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
  if data.len == ZxSpectrumScreenSize:
    var evidence = @[VextDetectionEvidence(
      description: "file size is exactly 6912 bytes")]
    if filename.splitFile.ext.toLowerAscii == ".scr":
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
