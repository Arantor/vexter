## In-memory results produced by exporters.

type
  VextArtifact* = object
    suggestedFilename*: string
    mediaType*: string
    data*: seq[byte]

  VextArtifactSet* = object
    artifacts*: seq[VextArtifact]
