## Shared evidence and derivation contracts for physical formats and semantic
## refinements.

type
  VextFormatSupport* = enum
    ## The format has both detection and structural inspection support.
    vfsInspectable
    ## The format can be identified from evidence, but has no parser yet.
    vfsDetectionOnly

  VextDetectionConfidence* = enum
    vdcPossible
    vdcProbable
    vdcCertain

  VextDetectionEvidence* = object
    description*: string

  VextFormatDerivationStage* = object
    typeId*: string

  VextFormatDerivation* = object
    ## Ordered physical-to-semantic interpretation stages.
    stages*: seq[VextFormatDerivationStage]

  VextDetectionCandidate* = object
    typeId*: string
    support*: VextFormatSupport
    confidence*: VextDetectionConfidence
    evidence*: seq[VextDetectionEvidence]
    derivation*: VextFormatDerivation

proc `$`*(confidence: VextDetectionConfidence): string =
  case confidence
  of vdcPossible: "possible"
  of vdcProbable: "probable"
  of vdcCertain: "certain"

proc `$`*(support: VextFormatSupport): string =
  case support
  of vfsInspectable: "inspectable"
  of vfsDetectionOnly: "detection-only"

proc baseDerivation*(typeId: string): VextFormatDerivation =
  VextFormatDerivation(stages: @[VextFormatDerivationStage(typeId: typeId)])

proc refinedDerivation*(parent: VextFormatDerivation,
    typeId: string): VextFormatDerivation =
  result.stages = parent.stages
  result.stages.add VextFormatDerivationStage(typeId: typeId)
