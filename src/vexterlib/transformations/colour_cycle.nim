## Expansion of indexed palette-cycle metadata into explicit animation frames.

import ../archetypes/raster

const DefaultColourCycleFrameLimit* = 1000

proc gcd(a, b: int64): int64 =
  var x = abs(a)
  var y = abs(b)
  while y != 0:
    let remainder = x mod y
    x = y
    y = remainder
  x

proc lcm(a, b: int64): int64 =
  if a <= 0 or b <= 0:
    raise newException(ValueError, "colour-cycle periods must be positive")
  let divided = a div gcd(a, b)
  if divided > high(int64) div b:
    raise newException(ValueError, "combined colour-cycle period is too large")
  divided * b

proc colourCycledImageAt*(image: VextIndexedImage,
    ranges: openArray[VextColourCycleRange],
    elapsedMs: int64): VextIndexedImage =
  result = image
  result.palette = @(image.palette)
  result.colourCycles.setLen(0)
  for cycle in ranges:
    let
      length = cycle.high - cycle.low + 1
      rawShift = int((elapsedMs div int64(cycle.stepDurationMs)) mod int64(length))
      shift = if cycle.direction < 0: (length - rawShift) mod length
        else: rawShift
      palette = @(result.palette)
    for offset in 0 ..< length:
      result.palette[cycle.low + ((offset + shift) mod length)] =
        palette[cycle.low + offset]

proc colourCyclePeriodMs*(ranges: openArray[VextColourCycleRange]): int64 =
  result = 1
  for cycle in ranges:
    result = lcm(result,
      int64(cycle.stepDurationMs) * int64(cycle.high - cycle.low + 1))

proc colourCycleNextBoundaryMs*(ranges: openArray[VextColourCycleRange],
    elapsedMs: int64): int64 =
  if ranges.len == 0:
    raise newException(ValueError, "image has no effective colour-cycle ranges")
  result = high(int64)
  for cycle in ranges:
    let
      step = int64(cycle.stepDurationMs)
      boundary = (elapsedMs div step + 1) * step
    if boundary < result: result = boundary

proc colourCycleRanges*(raster: VextRaster): seq[VextColourCycleRange] =
  case raster.kind
  of vrkIndexedImage: raster.image.colourCycles
  of vrkIndexedAnimation: raster.animation.colourCycles
  else: @[]

proc expandColourCycles*(raster: VextRaster,
    frameLimit = DefaultColourCycleFrameLimit,
    allowLargeAnimation = false): VextIndexedAnimation =
  let ranges = raster.colourCycleRanges
  if ranges.len == 0:
    raise newException(ValueError, "raster has no effective colour-cycle ranges")
  var baseFrames: seq[VextIndexedAnimationFrame]
  var isStill = false
  case raster.kind
  of vrkIndexedImage:
    isStill = true
    baseFrames = @[VextIndexedAnimationFrame(image: raster.image,
      durationMs: 1)]
  of vrkIndexedAnimation:
    baseFrames = raster.animation.frames
  else:
    raise newException(ValueError, "colour cycling requires indexed colour")
  if baseFrames.len == 0:
    raise newException(ValueError, "animation contains no frames")

  var combinedPeriod = 1'i64
  if not isStill:
    for frame in baseFrames:
      combinedPeriod += int64(max(1, frame.durationMs))
    dec combinedPeriod
  for cycle in ranges:
    combinedPeriod = lcm(combinedPeriod,
      int64(cycle.stepDurationMs) * int64(cycle.high - cycle.low + 1))

  result = VextIndexedAnimation(width: baseFrames[0].image.width,
    height: baseFrames[0].image.height)
  var
    elapsed: int64
    baseIndex = 0
    baseEnd = if isStill: combinedPeriod
      else: int64(max(1, baseFrames[0].durationMs))
  while elapsed < combinedPeriod:
    var next = baseEnd
    for cycle in ranges:
      let step = int64(cycle.stepDurationMs)
      let boundary = (elapsed div step + 1) * step
      if boundary < next: next = boundary
    if next > combinedPeriod: next = combinedPeriod
    if next <= elapsed:
      raise newException(ValueError, "invalid colour-cycle timeline")
    if not allowLargeAnimation and result.frames.len >= frameLimit:
      raise newException(ValueError, "colour cycling would exceed " &
        $frameLimit & " frames; explicitly allow a large animation to export it")
    result.frames.add VextIndexedAnimationFrame(
      image: colourCycledImageAt(baseFrames[baseIndex].image, ranges, elapsed),
      durationMs: int(next - elapsed))
    elapsed = next
    if not isStill and elapsed == baseEnd and elapsed < combinedPeriod:
      baseIndex = (baseIndex + 1) mod baseFrames.len
      baseEnd += int64(max(1, baseFrames[baseIndex].durationMs))
