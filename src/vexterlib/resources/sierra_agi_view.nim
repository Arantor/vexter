## Sierra AGI VIEW sprite decoding.
## Format facts are derived from the supplied AGI Specifications chapter 8.

import ../archetypes/raster

type
  AgiViewCel* = object
    width*, height*, transparentColour*: int
    mirrored*: bool
    mirrorLoop*: int
    pixels*: seq[uint8]

  AgiViewLoop* = object
    cels*: seq[AgiViewCel]

  AgiView* = object
    description*: string
    loops*: seq[AgiViewLoop]

const AgiEgaPalette* = [
  VextRgb(r: 0, g: 0, b: 0), VextRgb(r: 0, g: 0, b: 170),
  VextRgb(r: 0, g: 170, b: 0), VextRgb(r: 0, g: 170, b: 170),
  VextRgb(r: 170, g: 0, b: 0), VextRgb(r: 170, g: 0, b: 170),
  VextRgb(r: 170, g: 85, b: 0), VextRgb(r: 170, g: 170, b: 170),
  VextRgb(r: 85, g: 85, b: 85), VextRgb(r: 85, g: 85, b: 255),
  VextRgb(r: 85, g: 255, b: 85), VextRgb(r: 85, g: 255, b: 255),
  VextRgb(r: 255, g: 85, b: 85), VextRgb(r: 255, g: 85, b: 255),
  VextRgb(r: 255, g: 255, b: 85), VextRgb(r: 255, g: 255, b: 255)]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at + 2 > data.len:
    raise newException(ValueError, "truncated AGI VIEW offset")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc parseAgiView*(data: openArray[byte]): AgiView =
  if data.len < 5: raise newException(ValueError, "truncated AGI VIEW header")
  let loopCount = int(data[2])
  if loopCount == 0 or 5 + loopCount * 2 > data.len:
    raise newException(ValueError, "invalid AGI VIEW loop table")
  let descriptionAt = le16(data, 3)
  if descriptionAt != 0:
    if descriptionAt < 5 + loopCount * 2 or descriptionAt >= data.len:
      raise newException(ValueError, "AGI VIEW description is outside the resource")
    var at = descriptionAt
    while at < data.len and data[at] != 0:
      let value = data[at]
      result.description.add(if value == 10: '\n' elif value >= 0x20 and value < 0x7f:
        char(value) else: '?')
      inc at
    if at >= data.len:
      raise newException(ValueError, "unterminated AGI VIEW description")

  for loopIndex in 0 ..< loopCount:
    let loopAt = le16(data, 5 + loopIndex * 2)
    if loopAt < 5 + loopCount * 2 or loopAt >= data.len:
      raise newException(ValueError, "AGI VIEW loop is outside the resource")
    let celCount = int(data[loopAt])
    if celCount == 0 or loopAt + 1 + celCount * 2 > data.len:
      raise newException(ValueError, "invalid AGI VIEW cel table")
    var loop: AgiViewLoop
    for celIndex in 0 ..< celCount:
      let celAt = loopAt + le16(data, loopAt + 1 + celIndex * 2)
      if celAt < loopAt + 1 + celCount * 2 or celAt + 3 > data.len:
        raise newException(ValueError, "AGI VIEW cel is outside the resource")
      var cel = AgiViewCel(width: int(data[celAt]), height: int(data[celAt + 1]),
        transparentColour: int(data[celAt + 2] and 0x0f),
        mirrored: (data[celAt + 2] and 0x80) != 0,
        mirrorLoop: int((data[celAt + 2] shr 4) and 0x07))
      if cel.width == 0 or cel.height == 0:
        raise newException(ValueError, "AGI VIEW cel has zero dimensions")
      cel.pixels = newSeq[uint8](cel.width * cel.height)
      for pixel in cel.pixels.mitems: pixel = uint8(cel.transparentColour)
      var at = celAt + 3
      for y in 0 ..< cel.height:
        var x = 0
        while true:
          if at >= data.len: raise newException(ValueError, "truncated AGI VIEW cel data")
          let chunk = data[at]; inc at
          if chunk == 0: break
          let count = int(chunk and 0x0f)
          if count == 0 or x > cel.width - count:
            raise newException(ValueError, "AGI VIEW run exceeds its scanline")
          let colour = chunk shr 4
          for offset in 0 ..< count: cel.pixels[y * cel.width + x + offset] = colour
          x += count
      if cel.mirrored and cel.mirrorLoop != loopIndex:
        for y in 0 ..< cel.height:
          for x in 0 ..< cel.width div 2:
            swap(cel.pixels[y * cel.width + x],
              cel.pixels[y * cel.width + cel.width - 1 - x])
      loop.cels.add move(cel)
    result.loops.add move(loop)

proc raster*(cel: AgiViewCel): VextRaster =
  var image = VextIndexedImage(width: cel.width * 2, height: cel.height,
    palette: @AgiEgaPalette, pixels: newSeq[uint8](cel.width * 2 * cel.height),
    alpha: newSeq[uint8](cel.width * 2 * cel.height))
  for y in 0 ..< cel.height:
    for x in 0 ..< cel.width:
      let colour = cel.pixels[y * cel.width + x]
      for displayX in x * 2 .. x * 2 + 1:
        let target = y * image.width + displayX
        image.pixels[target] = colour
        image.alpha[target] = if int(colour) == cel.transparentColour: 0 else: 255
  VextRaster(kind: vrkIndexedImage, image: image)
