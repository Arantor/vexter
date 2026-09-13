## Aseprite .ase/.aseprite structural and palette parsing.

import std/[algorithm, strutils, unicode]
import ../archetypes/[palette, raster]

const
  AsepriteTypeId* = "aseprite.sprite"
  AsepritePaletteResourcePath* = "/palette"
  AsepriteSpriteResourcePath* = "/sprite"
  AsepriteMagic* = 0xa5e0
  AsepriteFrameMagic* = 0xf1fa
  MaximumAsepritePaletteColours* = 65536
  MaximumAsepritePixels* = 268_435_456

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
elif defined(macosx):
  const ZlibLibrary = "libz.dylib"
else:
  const ZlibLibrary = "libz.so(|.1)"

type ZStream = object
  nextIn: ptr byte
  availIn: cuint
  totalIn: culong
  nextOut: ptr byte
  availOut: cuint
  totalOut: culong
  msg: cstring
  state, zalloc, zfree, opaque: pointer
  dataType: cint
  adler, reserved: culong

proc zlibVersion(): cstring {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateInit(stream: ptr ZStream, version: cstring, size: cint): cint
    {.cdecl, importc: "inflateInit_", dynlib: ZlibLibrary.}
proc inflate(stream: ptr ZStream, flush: cint): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateEnd(stream: ptr ZStream): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}

type
  AsepritePaletteChange = object
    frameIndex: int
    chunkType: int
    newSize: int
    firstIndex: int
    colours: seq[VextRgba]

  AsepriteLayer* = object
    name*: string
    flags*, layerType*, childLevel*, blendMode*, opacity*: int

  AsepriteCel* = object
    layerIndex*, frameIndex*, x*, y*, opacity*, celType*, zIndex*: int
    linkedFrame*: int
    width*, height*: int
    pixels*: seq[byte]

  AsepriteSource* = object
    width*, height*: int
    colourDepth*: int
    frames*: int
    speedMs*: int
    transparentIndex*: int
    declaredColours*: int
    flags*: uint32
    chunkCount*: int
    paletteChunkCount*: int
    palette*: VextPalette
    layers*: seq[AsepriteLayer]
    cels*: seq[AsepriteCel]
    frameDurations*: seq[int]
    framePalettes*: seq[VextPalette]
    unsupportedBlendModes*, unsupportedGroupCompositing*,
      tilemapLayers*, tilemapCels*: int

proc word(data: openArray[byte], offset: int): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated Aseprite WORD")
  int(data[offset]) or int(data[offset + 1]) shl 8

proc short(data: openArray[byte], offset: int): int =
  let value = word(data, offset)
  if value >= 0x8000: value - 0x10000 else: value

proc dword(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "truncated Aseprite DWORD")
  uint32(data[offset]) or uint32(data[offset + 1]) shl 8 or
    uint32(data[offset + 2]) shl 16 or uint32(data[offset + 3]) shl 24

proc checkedInt(value: uint32, description: string): int =
  if uint64(value) > uint64(high(int)):
    raise newException(ValueError, description & " exceeds host limits")
  int(value)

proc checkedImageLength(width, height, bytesPerPixel: int): int =
  if width < 1 or height < 1 or bytesPerPixel < 1 or
      width > MaximumAsepritePixels div height or
      width * height > MaximumAsepritePixels div bytesPerPixel:
    raise newException(ValueError, "invalid or oversized Aseprite cel dimensions")
  width * height * bytesPerPixel

proc zlibInflate(source: openArray[byte], expectedSize: int): seq[byte] =
  result = newSeq[byte](expectedSize)
  var stream: ZStream
  if source.len > 0: stream.nextIn = unsafeAddr source[0]
  stream.availIn = cuint(source.len)
  if result.len > 0: stream.nextOut = addr result[0]
  stream.availOut = cuint(result.len)
  if inflateInit(addr stream, zlibVersion(), cint(sizeof(ZStream))) != 0:
    raise newException(ValueError, "could not initialize Aseprite zlib decoder")
  let status = inflate(addr stream, 4)
  discard inflateEnd(addr stream)
  if status != 1 or int(stream.totalOut) != expectedSize or stream.availIn != 0:
    raise newException(ValueError, "invalid or truncated Aseprite compressed cel")

proc readString(data: openArray[byte], offset: var int, limit: int): string

proc parseLayer(data: openArray[byte], start, limit: int,
    headerFlags: uint32): AsepriteLayer =
  if limit - start < 16:
    raise newException(ValueError, "truncated Aseprite layer chunk")
  result.flags = word(data, start)
  result.layerType = word(data, start + 2)
  result.childLevel = word(data, start + 4)
  result.blendMode = word(data, start + 10)
  result.opacity = int(data[start + 12])
  if result.layerType notin 0 .. 2 or result.blendMode notin 0 .. 18:
    raise newException(ValueError, "invalid Aseprite layer type or blend mode")
  var offset = start + 16
  result.name = readString(data, offset, limit)
  if result.layerType == 2:
    if offset + 4 > limit: raise newException(ValueError, "truncated Aseprite tilemap layer")
    offset += 4
  if (headerFlags and 4) != 0:
    if offset + 16 > limit: raise newException(ValueError, "truncated Aseprite layer UUID")
    offset += 16
  if offset != limit:
    raise newException(ValueError, "unexpected trailing Aseprite layer data")

proc parseCel(data: openArray[byte], start, limit, frameIndex,
    bytesPerPixel: int): AsepriteCel =
  if limit - start < 16:
    raise newException(ValueError, "truncated Aseprite cel chunk")
  result.layerIndex = word(data, start)
  result.frameIndex = frameIndex
  result.x = short(data, start + 2)
  result.y = short(data, start + 4)
  result.opacity = int(data[start + 6])
  result.celType = word(data, start + 7)
  result.zIndex = short(data, start + 9)
  var offset = start + 16
  case result.celType
  of 0, 2:
    if offset + 4 > limit: raise newException(ValueError, "truncated Aseprite image cel")
    result.width = word(data, offset)
    result.height = word(data, offset + 2)
    offset += 4
    let expected = checkedImageLength(result.width, result.height, bytesPerPixel)
    if result.celType == 0:
      if limit - offset != expected:
        raise newException(ValueError, "Aseprite raw cel has the wrong data length")
      result.pixels = @data[offset ..< limit]
    else:
      if offset >= limit:
        raise newException(ValueError, "empty Aseprite compressed cel")
      result.pixels = zlibInflate(data.toOpenArray(offset, limit - 1), expected)
  of 1:
    if offset + 2 != limit:
      raise newException(ValueError, "invalid Aseprite linked cel")
    result.linkedFrame = word(data, offset)
  of 3:
    discard
  else:
    raise newException(ValueError, "unsupported Aseprite cel type")

proc readString(data: openArray[byte], offset: var int, limit: int): string =
  if offset + 2 > limit:
    raise newException(ValueError, "truncated Aseprite string length")
  let length = word(data, offset)
  offset += 2
  if length > limit - offset:
    raise newException(ValueError, "truncated Aseprite UTF-8 string")
  result = newString(length)
  for index in 0 ..< length:
    result[index] = char(data[offset + index])
  if validateUtf8(result) != -1:
    raise newException(ValueError, "Aseprite string must be valid UTF-8")
  offset += length

proc parseNewPalette(data: openArray[byte], start, limit: int): AsepritePaletteChange =
  if limit - start < 20:
    raise newException(ValueError, "truncated Aseprite palette chunk")
  result.chunkType = 0x2019
  result.newSize = checkedInt(dword(data, start), "Aseprite palette size")
  result.firstIndex = checkedInt(dword(data, start + 4), "Aseprite palette index")
  let lastIndex = checkedInt(dword(data, start + 8), "Aseprite palette index")
  if result.newSize < 1 or result.newSize > MaximumAsepritePaletteColours or
      result.firstIndex < 0 or lastIndex < result.firstIndex or
      lastIndex >= result.newSize:
    raise newException(ValueError, "invalid Aseprite palette range")
  var offset = start + 20
  for index in result.firstIndex .. lastIndex:
    if offset + 6 > limit:
      raise newException(ValueError, "truncated Aseprite palette entry")
    let flags = word(data, offset)
    if (flags and not 1) != 0:
      raise newException(ValueError, "unsupported Aseprite palette entry flags")
    result.colours.add VextRgba(r: data[offset + 2], g: data[offset + 3],
      b: data[offset + 4], a: data[offset + 5])
    offset += 6
    if (flags and 1) != 0:
      discard readString(data, offset, limit)
  if offset != limit:
    raise newException(ValueError, "unexpected trailing Aseprite palette data")

proc parseOldPalette(data: openArray[byte], start, limit, chunkType: int):
    seq[AsepritePaletteChange] =
  if start + 2 > limit:
    raise newException(ValueError, "truncated old Aseprite palette chunk")
  let packets = word(data, start)
  var offset = start + 2
  var paletteIndex = 0
  for packet in 0 ..< packets:
    if offset + 2 > limit:
      raise newException(ValueError, "truncated old Aseprite palette packet")
    paletteIndex += int(data[offset])
    let storedCount = int(data[offset + 1])
    let count = if storedCount == 0: 256 else: storedCount
    offset += 2
    if paletteIndex + count > 256 or count > (limit - offset) div 3:
      raise newException(ValueError, "invalid old Aseprite palette packet")
    var change = AsepritePaletteChange(chunkType: chunkType,
      newSize: 256, firstIndex: paletteIndex)
    for index in 0 ..< count:
      let red = int(data[offset])
      let green = int(data[offset + 1])
      let blue = int(data[offset + 2])
      if chunkType == 0x0011 and (red > 63 or green > 63 or blue > 63):
        raise newException(ValueError, "six-bit Aseprite palette value exceeds 63")
      change.colours.add VextRgba(
        r: uint8(if chunkType == 0x0011: red * 255 div 63 else: red),
        g: uint8(if chunkType == 0x0011: green * 255 div 63 else: green),
        b: uint8(if chunkType == 0x0011: blue * 255 div 63 else: blue), a: 255)
      offset += 3
    result.add change
    paletteIndex += count
  if offset != limit:
    raise newException(ValueError, "unexpected trailing old Aseprite palette data")

proc applyChanges(changes: seq[AsepritePaletteChange], preferNew: bool,
    throughFrame = high(int)): VextPalette =
  var colours: seq[VextRgba]
  for change in changes:
    if change.frameIndex > throughFrame: continue
    if preferNew and change.chunkType != 0x2019: continue
    if not preferNew and change.chunkType == 0x2019: continue
    if colours.len != change.newSize:
      colours.setLen(change.newSize)
    for index, colour in change.colours:
      colours[change.firstIndex + index] = colour
  result.colours = colours
  if result.colours.len > 0: result.validate

proc parseAseprite*(data: openArray[byte]): AsepriteSource =
  if data.len < 128:
    raise newException(ValueError, "Aseprite file is shorter than its header")
  let fileSize = checkedInt(dword(data, 0), "Aseprite file size")
  if fileSize != data.len or word(data, 4) != AsepriteMagic:
    raise newException(ValueError, "invalid Aseprite file header")
  result.frames = word(data, 6)
  result.width = word(data, 8)
  result.height = word(data, 10)
  result.colourDepth = word(data, 12)
  result.flags = dword(data, 14)
  result.speedMs = word(data, 18)
  result.transparentIndex = int(data[28])
  result.declaredColours = word(data, 32)
  if result.declaredColours == 0: result.declaredColours = 256
  if result.frames < 1 or result.width < 1 or result.height < 1 or
      result.colourDepth notin [8, 16, 32]:
    raise newException(ValueError, "invalid Aseprite dimensions, frames, or colour depth")
  discard checkedImageLength(result.width, result.height, 4)

  var changes: seq[AsepritePaletteChange]
  var hasNewPalette = false
  var offset = 128
  let bytesPerPixel = result.colourDepth div 8
  for frameIndex in 0 ..< result.frames:
    if offset + 16 > data.len:
      raise newException(ValueError, "truncated Aseprite frame header")
    let frameSize = checkedInt(dword(data, offset), "Aseprite frame size")
    if frameSize < 16 or frameSize > data.len - offset or
        word(data, offset + 4) != AsepriteFrameMagic:
      raise newException(ValueError, "invalid Aseprite frame header")
    let oldChunkCount = word(data, offset + 6)
    let declaredDuration = word(data, offset + 8)
    result.frameDurations.add(if declaredDuration > 0: declaredDuration else: result.speedMs)
    let newChunkCount = checkedInt(dword(data, offset + 12), "Aseprite chunk count")
    let chunkCount = if newChunkCount == 0: oldChunkCount else: newChunkCount
    let frameLimit = offset + frameSize
    var chunkOffset = offset + 16
    for chunkIndex in 0 ..< chunkCount:
      if chunkOffset + 6 > frameLimit:
        raise newException(ValueError, "truncated Aseprite chunk header")
      let chunkSize = checkedInt(dword(data, chunkOffset), "Aseprite chunk size")
      if chunkSize < 6 or chunkSize > frameLimit - chunkOffset:
        raise newException(ValueError, "invalid Aseprite chunk size")
      let chunkType = word(data, chunkOffset + 4)
      let chunkStart = chunkOffset + 6
      let chunkLimit = chunkOffset + chunkSize
      case chunkType
      of 0x2019:
        var change = parseNewPalette(data, chunkStart, chunkLimit)
        change.frameIndex = frameIndex
        changes.add change
        hasNewPalette = true
        inc result.paletteChunkCount
      of 0x0004, 0x0011:
        var oldChanges = parseOldPalette(data, chunkStart, chunkLimit, chunkType)
        for change in oldChanges.mitems: change.frameIndex = frameIndex
        changes.add oldChanges
        inc result.paletteChunkCount
      of 0x2004:
        let layer = parseLayer(data, chunkStart, chunkLimit, result.flags)
        if layer.layerType == 2: inc result.tilemapLayers
        if layer.blendMode != 0: inc result.unsupportedBlendModes
        if layer.layerType == 1 and (result.flags and 2) != 0 and
            (layer.blendMode != 0 or layer.opacity != 255):
          inc result.unsupportedGroupCompositing
        result.layers.add layer
      of 0x2005:
        let cel = parseCel(data, chunkStart, chunkLimit, frameIndex, bytesPerPixel)
        if cel.celType == 3: inc result.tilemapCels
        result.cels.add cel
      else: discard
      inc result.chunkCount
      chunkOffset = chunkLimit
    if chunkOffset != frameLimit:
      raise newException(ValueError, "Aseprite frame size does not match its chunks")
    offset = frameLimit
  if offset != data.len:
    raise newException(ValueError, "unexpected data after Aseprite frames")
  result.palette = applyChanges(changes, hasNewPalette)
  for frameIndex in 0 ..< result.frames:
    result.framePalettes.add applyChanges(changes, hasNewPalette, frameIndex)

proc effectiveCel(source: AsepriteSource, cel: AsepriteCel): AsepriteCel =
  result = cel
  var linkedFrame = cel.linkedFrame
  var remaining = source.frames
  while result.celType == 1:
    if linkedFrame < 0 or linkedFrame >= source.frames or remaining == 0:
      raise newException(ValueError, "invalid or cyclic Aseprite linked cel")
    var found = false
    for candidate in source.cels:
      if candidate.frameIndex == linkedFrame and
          candidate.layerIndex == cel.layerIndex:
        result = candidate
        linkedFrame = result.linkedFrame
        found = true
        break
    if not found:
      raise newException(ValueError, "Aseprite linked cel target is missing")
    dec remaining
  if result.celType notin [0, 2]:
    raise newException(ValueError, "Aseprite linked cel target is not an image")
  result.x = cel.x
  result.y = cel.y
  result.opacity = cel.opacity
  result.zIndex = cel.zIndex

proc sourcePixel(source: AsepriteSource, cel: AsepriteCel, frameIndex,
    index: int, backgroundLayer: bool): VextRgba =
  case source.colourDepth
  of 32:
    let offset = index * 4
    VextRgba(r: cel.pixels[offset], g: cel.pixels[offset + 1],
      b: cel.pixels[offset + 2], a: cel.pixels[offset + 3])
  of 16:
    let offset = index * 2
    VextRgba(r: cel.pixels[offset], g: cel.pixels[offset],
      b: cel.pixels[offset], a: cel.pixels[offset + 1])
  of 8:
    let paletteIndex = int(cel.pixels[index])
    if paletteIndex == source.transparentIndex and not backgroundLayer:
      VextRgba(a: 0)
    elif frameIndex >= source.framePalettes.len or
        paletteIndex >= source.framePalettes[frameIndex].colours.len:
      raise newException(ValueError, "Aseprite cel references a missing palette entry")
    else:
      source.framePalettes[frameIndex].colours[paletteIndex]
  else:
    raise newException(ValueError, "unsupported Aseprite colour depth")

proc blendNormal(destination, source: VextRgba, opacity: int): VextRgba =
  let sourceAlpha = (int(source.a) * opacity + 127) div 255
  let inverse = 255 - sourceAlpha
  let outputAlpha = sourceAlpha + (int(destination.a) * inverse + 127) div 255
  if outputAlpha == 0: return VextRgba()
  template channel(src, dst: uint8): uint8 =
    uint8((int(src) * sourceAlpha * 255 + int(dst) * int(destination.a) * inverse +
      outputAlpha * 127) div (outputAlpha * 255))
  result = VextRgba(r: channel(source.r, destination.r),
    g: channel(source.g, destination.g), b: channel(source.b, destination.b),
    a: uint8(outputAlpha))

proc layerIsVisible(source: AsepriteSource, layerIndex: int): bool =
  let level = source.layers[layerIndex].childLevel
  if (source.layers[layerIndex].flags and 1) == 0: return false
  var requiredLevel = level
  var index = layerIndex - 1
  while requiredLevel > 0 and index >= 0:
    let candidate = source.layers[index]
    if candidate.childLevel < requiredLevel:
      if candidate.layerType != 1 or (candidate.flags and 1) == 0: return false
      requiredLevel = candidate.childLevel
    dec index
  requiredLevel == 0

proc decodeAseprite*(source: AsepriteSource): VextRaster =
  if source.layers.len == 0 or source.cels.len == 0:
    raise newException(ValueError, "Aseprite sprite contains no decodable image cels")
  var animation = VextTrueColourAnimation(width: source.width, height: source.height)
  for frameIndex in 0 ..< source.frames:
    var image = VextTrueColourImage(width: source.width, height: source.height,
      pixels: newSeq[VextRgb](source.width * source.height),
      alpha: newSeq[uint8](source.width * source.height))
    var frameCels: seq[AsepriteCel]
    for cel in source.cels:
      if cel.frameIndex == frameIndex and cel.celType != 3:
        if cel.layerIndex >= source.layers.len:
          raise newException(ValueError, "Aseprite cel references a missing layer")
        frameCels.add cel
    frameCels.sort(proc(a, b: AsepriteCel): int =
      let ao = a.layerIndex + a.zIndex
      let bo = b.layerIndex + b.zIndex
      if ao != bo: cmp(ao, bo) else: cmp(a.zIndex, b.zIndex))
    for original in frameCels:
      let layer = source.layers[original.layerIndex]
      if layer.layerType != 0 or not source.layerIsVisible(original.layerIndex) or
          layer.blendMode != 0:
        continue
      let cel = source.effectiveCel(original)
      let layerOpacity = if (source.flags and 1) != 0: layer.opacity else: 255
      let opacity = (cel.opacity * layerOpacity + 127) div 255
      for sy in 0 ..< cel.height:
        let dy = cel.y + sy
        if dy < 0 or dy >= source.height: continue
        for sx in 0 ..< cel.width:
          let dx = cel.x + sx
          if dx < 0 or dx >= source.width: continue
          let target = dy * source.width + dx
          let foreground = source.sourcePixel(cel, frameIndex,
            sy * cel.width + sx, (layer.flags and 8) != 0)
          let background = VextRgba(r: image.pixels[target].r,
            g: image.pixels[target].g, b: image.pixels[target].b,
            a: image.alpha[target])
          let blended = blendNormal(background, foreground, opacity)
          image.pixels[target] = blended.rgb
          image.alpha[target] = blended.a
    animation.frames.add VextTrueColourAnimationFrame(image: image,
      durationMs: source.frameDurations[frameIndex])
  if animation.frames.len == 1:
    VextRaster(kind: vrkTrueColourImage,
      trueColourImage: animation.frames[0].image)
  else:
    VextRaster(kind: vrkTrueColourAnimation, trueColourAnimation: animation)

proc isAseprite*(data: openArray[byte]): bool =
  try:
    discard parseAseprite(data)
    true
  except ValueError:
    false

proc hasAsepriteExtension*(filename: string): bool =
  let lower = filename.toLowerAscii
  lower.endsWith(".ase") or lower.endsWith(".aseprite")
