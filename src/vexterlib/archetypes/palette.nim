## Generic ordered colour palette values.

import ./raster

type VextPalette* = object
  colours*: seq[VextRgba]
  colourCycles*: seq[VextColourCycleRange]

proc validate*(palette: VextPalette) =
  if palette.colours.len == 0:
    raise newException(ValueError, "palette must contain at least one colour")
  for cycle in palette.colourCycles:
    if cycle.low < 0 or cycle.high >= palette.colours.len or
        cycle.low >= cycle.high or cycle.direction notin [-1, 1] or
        cycle.stepDurationMs <= 0:
      raise newException(ValueError, "invalid palette colour-cycle range")
