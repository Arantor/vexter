## Common resource decoding operations across registered container types.

import ./archetypes/indexed_animation
import ./containers/[zx_spectrum_screen, zx_spectrum_snapshot]

proc decodeScreenResource*(containerTypeId: string,
    data: openArray[byte]): VextIndexedAnimation =
  ## Decodes the canonical `/screen` resource exposed by a supported
  ## container.
  case containerTypeId
  of ZxSpectrumScreenTypeId:
    decodeZxSpectrumScreen(data)
  of ZxSpectrumSnapshotTypeId:
    decodeZxSpectrumSnapshotScreen(data)
  else:
    raise newException(ValueError,
      "container does not expose a screen resource: " & containerTypeId)
