## Platform-neutral sizing and resampling policy for GUI raster previews.

type VextPreviewResampling* = enum
  vprNearest
  vprFiltered

proc previewFitSize*(sourceWidth, sourceHeight, availableWidth,
    availableHeight: int, maximumEnlargement = 5.0): tuple[width, height: int] =
  if sourceWidth <= 0 or sourceHeight <= 0 or availableWidth <= 0 or
      availableHeight <= 0 or maximumEnlargement <= 0:
    return
  let factor = min(maximumEnlargement, min(
    availableWidth.float / sourceWidth.float,
    availableHeight.float / sourceHeight.float))
  result.width = max(1, int(sourceWidth.float * factor))
  result.height = max(1, int(sourceHeight.float * factor))

proc previewResampling*(indexed: bool, sourceWidth, sourceHeight,
    destinationWidth, destinationHeight: int): VextPreviewResampling =
  ## Reductions always use filtering. Enlargement preserves hard pixel edges
  ## for indexed material, while true-colour material remains filtered.
  if indexed and destinationWidth >= sourceWidth and
      destinationHeight >= sourceHeight:
    vprNearest
  else:
    vprFiltered
