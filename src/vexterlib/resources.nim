## Common resource decoding operations across registered container types.

import ./archetypes/raster
import ./containers/[zx_spectrum_screen, zx_spectrum_snapshot]

proc decodeScreenResource*(containerTypeId: string,
    data: openArray[byte]): VextRaster =
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
