## Complete static-image decoding for PNG, including Adam7 interlacing.

import ../archetypes/raster
import ../containers/png_container

const
  PngImageTypeId* = "png.image"
  PngImageResourcePath* = "/image"

type
  ZStream = object
    nextIn: ptr byte
    availIn: uint32
    totalIn: culong
    nextOut: ptr byte
    availOut: uint32
    totalOut: culong
    msg: cstring
    state, zalloc, zfree, opaque: pointer
    dataType: cint
    adler, reserved: culong

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
elif defined(macosx):
  const ZlibLibrary = "libz.dylib"
else:
  const ZlibLibrary = "libz.so(|.1)"

proc zlibVersion(): cstring {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateInit(stream: ptr ZStream, version: cstring, size: cint): cint
    {.cdecl, importc: "inflateInit_", dynlib: ZlibLibrary.}
proc inflate(stream: ptr ZStream, flush: cint): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateEnd(stream: ptr ZStream): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}

proc channels(colourType: int): int =
  case colourType
  of 0, 3: 1
  of 2: 3
  of 4: 2
  of 6: 4
  else: 0

proc passExtent(size, start, step: int): int =
  if size <= start: 0 else: (size - start + step - 1) div step

proc expectedInflatedSize(source: PngImageSource): int =
  let bits = channels(source.colourType) * source.bitDepth
  if source.interlaceMethod == 0:
    return source.height * (1 + (source.width * bits + 7) div 8)
  const startsX = [0, 4, 0, 2, 0, 1, 0]
  const startsY = [0, 0, 4, 0, 2, 0, 1]
  const stepsX = [8, 8, 4, 4, 2, 2, 1]
  const stepsY = [8, 8, 8, 4, 4, 2, 2]
  for pass in 0 ..< 7:
    let width = passExtent(source.width, startsX[pass], stepsX[pass])
    let height = passExtent(source.height, startsY[pass], stepsY[pass])
    if width > 0 and height > 0:
      result += height * (1 + (width * bits + 7) div 8)

proc inflateImage(source: PngImageSource): seq[byte] =
  result = newSeq[byte](expectedInflatedSize(source))
  var stream: ZStream
  if source.imageData.len > 0: stream.nextIn = unsafeAddr source.imageData[0]
  stream.availIn = uint32(source.imageData.len)
  if result.len > 0: stream.nextOut = addr result[0]
  stream.availOut = uint32(result.len)
  if inflateInit(addr stream, zlibVersion(), cint(sizeof(ZStream))) != 0:
    raise newException(ValueError, "could not initialize PNG inflater")
  let status = inflate(addr stream, 4)
  discard inflateEnd(addr stream)
  if status != 1 or int(stream.totalOut) != result.len or stream.availIn != 0:
    raise newException(ValueError, "invalid or incorrectly sized PNG image data")

proc paeth(left, above, upperLeft: int): int =
  let estimate = left + above - upperLeft
  let leftDistance = abs(estimate - left)
  let aboveDistance = abs(estimate - above)
  let cornerDistance = abs(estimate - upperLeft)
  if leftDistance <= aboveDistance and leftDistance <= cornerDistance: left
  elif aboveDistance <= cornerDistance: above
  else: upperLeft

proc unfilterRow(filtered: openArray[byte], previous: openArray[byte],
    filter, pixelBytes: int): seq[byte] =
  result = newSeq[byte](filtered.len)
  for index, value in filtered:
    let left = if index >= pixelBytes: int(result[index - pixelBytes]) else: 0
    let above = if previous.len > 0: int(previous[index]) else: 0
    let upperLeft = if previous.len > 0 and index >= pixelBytes:
      int(previous[index - pixelBytes]) else: 0
    let predictor = case filter
      of 0: 0
      of 1: left
      of 2: above
      of 3: (left + above) div 2
      of 4: paeth(left, above, upperLeft)
      else: raise newException(ValueError, "invalid PNG scanline filter")
    result[index] = byte((int(value) + predictor) and 0xff)

proc sample(row: openArray[byte], sampleIndex, depth: int): uint16 =
  if depth == 16:
    return (uint16(row[sampleIndex * 2]) shl 8) or
      uint16(row[sampleIndex * 2 + 1])
  if depth == 8: return uint16(row[sampleIndex])
  let bit = sampleIndex * depth
  uint16((int(row[bit div 8]) shr (8 - depth - bit mod 8)) and
    ((1 shl depth) - 1))

proc expanded(value: uint16, depth: int): uint8 =
  let maximum = (1'u32 shl depth) - 1
  uint8((uint32(value) * 255 + maximum div 2) div maximum)

proc decodePng*(source: PngImageSource): VextRaster =
  let inflated = inflateImage(source)
  let componentCount = channels(source.colourType)
  let pixelBytes = max(1, (componentCount * source.bitDepth + 7) div 8)
  var colours = newSeq[VextRgb](source.width * source.height)
  var indices = newSeq[uint8](source.width * source.height)
  var alpha = newSeq[uint8](source.width * source.height)
  for index in 0 ..< alpha.len: alpha[index] = 255
  var anyAlpha = false
  var offset = 0
  const startsX = [0, 4, 0, 2, 0, 1, 0]
  const startsY = [0, 0, 4, 0, 2, 0, 1]
  const stepsX = [8, 8, 4, 4, 2, 2, 1]
  const stepsY = [8, 8, 8, 4, 4, 2, 2]
  let passCount = if source.interlaceMethod == 0: 1 else: 7
  for pass in 0 ..< passCount:
    let startX = if passCount == 1: 0 else: startsX[pass]
    let startY = if passCount == 1: 0 else: startsY[pass]
    let stepX = if passCount == 1: 1 else: stepsX[pass]
    let stepY = if passCount == 1: 1 else: stepsY[pass]
    let width = passExtent(source.width, startX, stepX)
    let height = passExtent(source.height, startY, stepY)
    if width == 0 or height == 0: continue
    let rowBytes = (width * componentCount * source.bitDepth + 7) div 8
    var previous: seq[byte]
    for passY in 0 ..< height:
      let filter = int(inflated[offset]); inc offset
      let row = unfilterRow(inflated.toOpenArray(offset, offset + rowBytes - 1),
        previous, filter, pixelBytes)
      offset += rowBytes
      previous = row
      for passX in 0 ..< width:
        let x = startX + passX * stepX
        let y = startY + passY * stepY
        let output = y * source.width + x
        case source.colourType
        of 0:
          let gray = sample(row, passX, source.bitDepth)
          let value = expanded(gray, source.bitDepth)
          colours[output] = VextRgb(r: value, g: value, b: value)
          if source.transparency.len == 2:
            let transparent = (uint16(source.transparency[0]) shl 8) or
              uint16(source.transparency[1])
            if gray == transparent: alpha[output] = 0; anyAlpha = true
        of 2:
          let base = passX * 3
          let red = sample(row, base, source.bitDepth)
          let green = sample(row, base + 1, source.bitDepth)
          let blue = sample(row, base + 2, source.bitDepth)
          colours[output] = VextRgb(r: expanded(red, source.bitDepth),
            g: expanded(green, source.bitDepth), b: expanded(blue, source.bitDepth))
          if source.transparency.len == 6:
            let tr = (uint16(source.transparency[0]) shl 8) or uint16(source.transparency[1])
            let tg = (uint16(source.transparency[2]) shl 8) or uint16(source.transparency[3])
            let tb = (uint16(source.transparency[4]) shl 8) or uint16(source.transparency[5])
            if red == tr and green == tg and blue == tb:
              alpha[output] = 0; anyAlpha = true
        of 3:
          let index = int(sample(row, passX, source.bitDepth))
          if index >= source.palette.len div 3:
            raise newException(ValueError, "PNG pixel references a missing palette entry")
          indices[output] = uint8(index)
          if index < source.transparency.len:
            alpha[output] = source.transparency[index]
            if alpha[output] != 255: anyAlpha = true
        of 4:
          let base = passX * 2
          let gray = expanded(sample(row, base, source.bitDepth), source.bitDepth)
          colours[output] = VextRgb(r: gray, g: gray, b: gray)
          alpha[output] = expanded(sample(row, base + 1, source.bitDepth), source.bitDepth)
          if alpha[output] != 255: anyAlpha = true
        of 6:
          let base = passX * 4
          colours[output] = VextRgb(
            r: expanded(sample(row, base, source.bitDepth), source.bitDepth),
            g: expanded(sample(row, base + 1, source.bitDepth), source.bitDepth),
            b: expanded(sample(row, base + 2, source.bitDepth), source.bitDepth))
          alpha[output] = expanded(sample(row, base + 3, source.bitDepth), source.bitDepth)
          if alpha[output] != 255: anyAlpha = true
        else: discard
  if source.colourType == 3:
    var palette: seq[VextRgb]
    for index in 0 ..< source.palette.len div 3:
      palette.add VextRgb(r: source.palette[index * 3],
        g: source.palette[index * 3 + 1], b: source.palette[index * 3 + 2])
    return VextRaster(kind: vrkIndexedImage,
      image: VextIndexedImage(width: source.width, height: source.height,
        palette: palette, pixels: indices,
        alpha: (if anyAlpha: alpha else: @[])))
  VextRaster(kind: vrkTrueColourImage,
    trueColourImage: VextTrueColourImage(width: source.width,
      height: source.height, pixels: colours,
      alpha: (if anyAlpha: alpha else: @[])))
