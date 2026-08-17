## Decoder entry points for uncompressed 48K ZX Spectrum SNA snapshots.

import ../archetypes/raster
import ./zx_spectrum_screen

const
  ZxSpectrumSnapshotTypeId* = "zx-spectrum.snapshot"
  ZxSpectrumSnapshot48Size* = 49179
  ZxSpectrumSnapshotHeaderSize* = 27

proc extractZxSpectrumSnapshotScreen*(data: openArray[byte]): seq[byte] =
  ## Extracts the 6,912-byte display-memory region from a 48K SNA snapshot.
  if data.len != ZxSpectrumSnapshot48Size:
    raise newException(ValueError,
      "48K ZX Spectrum snapshot must contain exactly 49179 bytes")
  result = newSeq[byte](ZxSpectrumScreenSize)
  for index in 0 ..< ZxSpectrumScreenSize:
    result[index] = data[ZxSpectrumSnapshotHeaderSize + index]

proc decodeZxSpectrumSnapshotScreen*(data: openArray[byte]):
    VextRaster =
  ## Extracts and decodes the snapshot's current screen.
  decodeZxSpectrumScreen(extractZxSpectrumSnapshotScreen(data))
