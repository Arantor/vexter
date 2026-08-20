## Byte-preserving export for opaque resources.

import ../artifacts

proc exportRaw*(data: openArray[byte],
    suggestedFilename = "resource.bin"): VextArtifactSet =
  result.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "application/octet-stream",
    data: @data)
