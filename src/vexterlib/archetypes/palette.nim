## Generic ordered colour palette values.

import ./raster

type VextPalette* = object
  colours*: seq[VextRgba]
  colourCycles*: seq[VextColourCycleRange]

proc validate*(palette: VextPalette) =
  if palette.colours.len == 0:
    raise newException(ValueError, "palette must contain at least one colour")
  for cycle in palette.colourCycles:
    var valid = cycle.direction in [-1, 1] and cycle.stepDurationMs > 0
    if cycle.cells.len > 0:
      valid = valid and cycle.cells.len > 1
      var registers = 0
      for cell in cycle.cells:
        if cell.isRegister:
          inc registers
          valid = valid and cell.register >= 0 and
            cell.register < palette.colours.len
      valid = valid and registers > 0
    else:
      valid = valid and cycle.low >= 0 and
        cycle.high < palette.colours.len and cycle.low < cycle.high
    if not valid:
      raise newException(ValueError, "invalid palette colour-cycle range")
