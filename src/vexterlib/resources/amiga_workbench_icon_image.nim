## Rendering of classic planar Workbench icon imagery.

import ../archetypes/raster
import ../containers/amiga_workbench_icon

const Workbench13Palette* = [
  VextRgb(r: 0x00, g: 0x55, b: 0xaa),
  VextRgb(r: 0xff, g: 0xff, b: 0xff),
  VextRgb(r: 0x00, g: 0x00, b: 0x00),
  VextRgb(r: 0xff, g: 0x88, b: 0x00)]

proc decodeWorkbenchIconImage*(source: WorkbenchIconImage): VextIndexedImage =
  result = VextIndexedImage(width: source.width, height: source.height,
    palette: @Workbench13Palette,
    pixels: newSeq[byte](source.width * source.height))
  let rowBytes = ((source.width + 15) div 16) * 2
  for y in 0 ..< source.height:
    for x in 0 ..< source.width:
      var pen = int(source.planeOnOff)
      var sourcePlane = 0
      for destinationPlane in 0 .. 7:
        let mask = 1 shl destinationPlane
        if (int(source.planePick) and mask) != 0:
          if sourcePlane < source.depth and source.data.len > 0:
            let byteOffset = sourcePlane * rowBytes * source.height + y * rowBytes + x div 8
            let bit = (int(source.data[byteOffset]) shr (7 - (x mod 8))) and 1
            if bit != 0: pen = pen or mask else: pen = pen and not mask
          sourcePlane += 1
      result.pixels[y * source.width + x] = byte(pen and 3)

proc decodeWorkbenchEnhancedImage*(source: WorkbenchEnhancedImage): VextIndexedImage =
  result = VextIndexedImage(width: source.width, height: source.height,
    pixels: source.pixels, alpha: source.alpha)
  for colour in source.palette:
    result.palette.add VextRgb(r: colour[0], g: colour[1], b: colour[2])
