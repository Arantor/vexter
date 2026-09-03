## Platform-neutral formatting and policy for GUI previews.

import std/strutils

const
  MaximumHexdumpPreviewBytes* = 1024 * 1024
  HexdumpBytesPerLine* = 16

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

proc canShowHexdump*(isOpaque, rawDataAvailable: bool, byteLength: int): bool =
  isOpaque and rawDataAvailable and byteLength >= 0 and
    byteLength <= MaximumHexdumpPreviewBytes

proc formatHexdump*(data: openArray[byte]): string =
  ## Uses fixed columns so the hexadecimal and printable-ASCII runs align.
  if data.len > MaximumHexdumpPreviewBytes:
    raise newException(ValueError, "hexdump preview exceeds the 1 MiB limit")
  var offset = 0
  while offset < data.len:
    if result.len > 0: result.add "\r\n"
    result.add offset.toHex(8)
    result.add "  "
    let lineLength = min(HexdumpBytesPerLine, data.len - offset)
    for index in 0 ..< HexdumpBytesPerLine:
      if index > 0: result.add ' '
      if index < lineLength:
        result.add data[offset + index].toHex(2)
      else:
        result.add "  "
    result.add "  "
    for index in 0 ..< lineLength:
      let value = data[offset + index]
      result.add if value >= 32 and value < 127: char(value) else: '.'
    offset += lineLength
