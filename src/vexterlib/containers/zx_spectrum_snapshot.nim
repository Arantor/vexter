## Validation and resource extraction for uncompressed ZX Spectrum snapshots.

import ../resources/zx_spectrum_screen

const
  ZxSpectrumSnapshotTypeId* = "zx-spectrum.snapshot"
  ZxSpectrumSnapshot48Size* = 49179
  ZxSpectrumSnapshot128Size* = 131103
  ZxSpectrumSnapshot128ExtendedSize* = 147487
  ZxSpectrumSnapshotHeaderSize* = 27

proc isZxSpectrumSnapshotSize*(size: int): bool =
  ## Returns whether `size` is one of the supported 48K or 128K SNA sizes.
  size in [ZxSpectrumSnapshot48Size, ZxSpectrumSnapshot128Size,
    ZxSpectrumSnapshot128ExtendedSize]

proc extractZxSpectrumSnapshotScreen*(data: openArray[byte]): seq[byte] =
  ## Extracts the 6,912-byte display-memory region from a supported SNA snapshot.
  if not isZxSpectrumSnapshotSize(data.len):
    raise newException(ValueError,
      "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
  result = newSeq[byte](ZxSpectrumScreenSize)
  for index in 0 ..< ZxSpectrumScreenSize:
    result[index] = data[ZxSpectrumSnapshotHeaderSize + index]
