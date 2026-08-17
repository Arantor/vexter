## Common resource decoding operations across registered container types.

import ./archetypes/raster
import ./containers/[zx_spectrum_screen, zx_spectrum_snapshot, zx_spectrum_tap]

proc screenResourcePaths*(containerTypeId: string,
    data: openArray[byte]): seq[string] =
  case containerTypeId
  of ZxSpectrumScreenTypeId, ZxSpectrumSnapshotTypeId:
    @[ZxSpectrumScreenResourcePath]
  of ZxSpectrumTapTypeId:
    zxSpectrumTapScreenPaths(data)
  else:
    @[]

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

proc decodeScreenResource*(containerTypeId, path: string,
    data: openArray[byte]): VextRaster =
  if containerTypeId == ZxSpectrumTapTypeId:
    return decodeZxSpectrumTapScreen(data, path)
  if path != ZxSpectrumScreenResourcePath:
    raise newException(ValueError, "resource was not found: " & path)
  decodeScreenResource(containerTypeId, data)
