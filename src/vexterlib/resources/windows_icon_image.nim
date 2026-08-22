## Raster decoding for the image representations embedded in ICO/CUR files.

import ../archetypes/raster
import ../containers/windows_icon
import ./[bmp_image, png_image]

const WindowsIconImageTypeId* = "windows.icon-image"

proc decodeWindowsIconEntry*(entry: WindowsIconEntry): VextRaster =
  case entry.encoding
  of wiePng:
    result = decodePngOrApng(entry.png)
  of wieUnknown:
    raise newException(ValueError, "unsupported ICO/CUR image encoding")
  of wieDib:
    result = decodeBmp(entry.dib)
    let pixelCount = entry.dib.width * entry.dib.height
    var alpha = newSeq[uint8](pixelCount)
    for index in 0 ..< pixelCount: alpha[index] = 255
    var meaningfulDibAlpha = false
    if entry.dib.bitsPerPixel == 32 and entry.dib.compression == 0:
      let rowBytes = entry.dib.width * 4
      for outputY in 0 ..< entry.dib.height:
        let storedY = entry.dib.height - 1 - outputY
        for x in 0 ..< entry.dib.width:
          let value = entry.dib.pixelData[storedY * rowBytes + x * 4 + 3]
          alpha[outputY * entry.dib.width + x] = value
          if value != 0: meaningfulDibAlpha = true
    if not meaningfulDibAlpha:
      for index in 0 ..< pixelCount: alpha[index] = 255
    let maskRowBytes = ((entry.dib.width + 31) div 32) * 4
    for outputY in 0 ..< entry.dib.height:
      let storedY = entry.dib.height - 1 - outputY
      for x in 0 ..< entry.dib.width:
        if (entry.andMask[storedY * maskRowBytes + x div 8] and
            byte(0x80 shr (x mod 8))) != 0:
          alpha[outputY * entry.dib.width + x] = 0
    case result.kind
    of vrkIndexedImage: result.image.alpha = alpha
    of vrkTrueColourImage: result.trueColourImage.alpha = alpha
    else: discard
