## Generic ordered colour palette values.

import ./raster

type VextPalette* = object
  colours*: seq[VextRgb]
  ## Optional per-colour alpha. Empty means every colour is opaque.
  alpha*: seq[uint8]
  colourCycles*: seq[VextColourCycleRange]

proc validate*(palette: VextPalette) =
  if palette.colours.len == 0:
    raise newException(ValueError, "palette must contain at least one colour")
  if palette.alpha.len notin [0, palette.colours.len]:
    raise newException(ValueError,
      "palette alpha must be empty or match the number of colours")
  for cycle in palette.colourCycles:
    if cycle.low < 0 or cycle.high >= palette.colours.len or
        cycle.low >= cycle.high or cycle.direction notin [-1, 1] or
        cycle.stepDurationMs <= 0:
      raise newException(ValueError, "invalid palette colour-cycle range")
