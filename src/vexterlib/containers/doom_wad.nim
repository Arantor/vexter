## Structural validation and image extraction for classic DOOM IWAD/PWAD files.

import std/[os, strutils]
import ../archetypes/[audio, palette, raster]

const
  DoomWadTypeId* = "doom.wad"
  DoomWadPaletteTypeId* = "doom.palette"
  DoomWadFlatTypeId* = "doom.flat"
  DoomWadPatchTypeId* = "doom.patch"
  DoomWadTextureDirectoryTypeId* = "doom.texture-directory"
  DoomWadTextureTypeId* = "doom.wall-texture"
  DoomWadSoundTypeId* = "doom.sound"
  DoomWadAutomapTypeId* = "doom.automap"
  DoomWadLumpTypeId* = "doom.lump"
  DoomPaletteColours* = 256
  DoomPaletteBytes* = DoomPaletteColours * 3
  DoomPaletteCount* = 14
  DoomFlatSize* = 64 * 64
  MaximumDoomPatchPixels* = 64 * 1024 * 1024
  MaximumDoomMapElements* = 100_000
  MaximumDoomAutomapDimension* = 1024

type
  DoomWadKind* = enum
    dwkIwad
    dwkPwad

  DoomWadEntry* = object
    offset*, size*: int
    name*: string

  DoomWad* = object
    kind*: DoomWadKind
    directoryOffset*: int
    entries*: seq[DoomWadEntry]

  DoomPatchPost* = object
    top*: int
    pixels*: seq[uint8]

  DoomPatchColumn* = object
    posts*: seq[DoomPatchPost]

  DoomPatch* = object
    width*, height*: int
    leftOffset*, topOffset*: int
    columns*: seq[DoomPatchColumn]

  DoomTexturePatch* = object
    originX*, originY*: int
    patchIndex*: int
    stepDirection*, colourMap*: int

  DoomTexture* = object
    name*: string
    masked*, columnDirectory*: uint64
    width*, height*: int
    patches*: seq[DoomTexturePatch]

  DoomTextureDirectory* = object
    textures*: seq[DoomTexture]

  DoomSoundSource* = object
    format*: int
    sampleRate*: int
    declaredSamples*: int
    reserved*: int
    samples*: seq[byte]

  DoomMapVertex* = object
    x*, y*: int

  DoomMapLine* = object
    startVertex*, endVertex*: int
    flags*, lineType*, tag*: int
    rightSide*, leftSide*: int

  DoomMapSide* = object
    sector*: int

  DoomMapSector* = object
    floorHeight*, ceilingHeight*: int

  DoomAutomapSource* = object
    vertices*: seq[DoomMapVertex]
    lines*: seq[DoomMapLine]
    sides*: seq[DoomMapSide]
    sectors*: seq[DoomMapSector]

proc littleWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc signedLittleWord(data: openArray[byte], offset: int): int {.inline.} =
  let value = littleWord(data, offset)
  if value >= 0x8000: value - 0x10000 else: value

proc littleLong(data: openArray[byte], offset: int): uint64 {.inline.} =
  uint64(data[offset]) or (uint64(data[offset + 1]) shl 8) or
    (uint64(data[offset + 2]) shl 16) or (uint64(data[offset + 3]) shl 24)

proc lumpName(data: openArray[byte], offset: int): string =
  var ended = false
  for index in 0 ..< 8:
    let value = data[offset + index]
    if value == 0:
      ended = true
      continue
    if ended:
      raise newException(ValueError, "WAD lump name has nonzero padding")
    if value < 0x20 or value > 0x7e:
      raise newException(ValueError, "WAD lump name contains a non-ASCII byte")
    result.add char(value)
  if result.len == 0:
    raise newException(ValueError, "WAD lump name must not be empty")

proc parseDoomWad*(data: openArray[byte]): DoomWad =
  if data.len < 12:
    raise newException(ValueError, "truncated WAD header")
  let identifier = data[0 ..< 4]
  if identifier == [byte('I'), byte('W'), byte('A'), byte('D')]:
    result.kind = dwkIwad
  elif identifier == [byte('P'), byte('W'), byte('A'), byte('D')]:
    result.kind = dwkPwad
  else:
    raise newException(ValueError, "invalid WAD identifier")

  let entryCount64 = littleLong(data, 4)
  let directoryOffset64 = littleLong(data, 8)
  if entryCount64 > uint64(high(int)) or directoryOffset64 > uint64(high(int)):
    raise newException(ValueError, "WAD directory values exceed host limits")
  let entryCount = int(entryCount64)
  if entryCount == 0:
    raise newException(ValueError, "WAD must contain at least one directory entry")
  result.directoryOffset = int(directoryOffset64)
  if entryCount > (data.len - min(data.len, result.directoryOffset)) div 16 or
      result.directoryOffset < 12 or
      result.directoryOffset > data.len - entryCount * 16:
    raise newException(ValueError, "WAD directory is outside the file")

  for index in 0 ..< entryCount:
    let directoryEntry = result.directoryOffset + index * 16
    let offset64 = littleLong(data, directoryEntry)
    let size64 = littleLong(data, directoryEntry + 4)
    if offset64 > uint64(high(int)) or size64 > uint64(high(int)):
      raise newException(ValueError, "WAD lump bounds exceed host limits")
    let offset = int(offset64)
    let size = int(size64)
    if offset < 0 or size < 0 or offset > data.len - size:
      raise newException(ValueError, "WAD lump is outside the file")
    result.entries.add DoomWadEntry(offset: offset, size: size,
      name: lumpName(data, directoryEntry + 8))

proc isDoomWad*(data: openArray[byte]): bool =
  try:
    discard parseDoomWad(data)
    true
  except ValueError:
    false

proc hasDoomWadExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".wad"

proc doomWadKindName*(kind: DoomWadKind): string =
  case kind
  of dwkIwad: "IWAD"
  of dwkPwad: "PWAD"

proc entryBytes*(entry: DoomWadEntry, data: openArray[byte]): seq[byte] =
  @data[entry.offset ..< entry.offset + entry.size]

proc decodeDoomPalettes*(data: openArray[byte]): seq[VextPalette] =
  if data.len != DoomPaletteCount * DoomPaletteBytes:
    raise newException(ValueError, "PLAYPAL must contain fourteen 256-colour palettes")
  for paletteIndex in 0 ..< DoomPaletteCount:
    var palette: seq[VextRgb]
    let start = paletteIndex * DoomPaletteBytes
    for colour in 0 ..< DoomPaletteColours:
      let offset = start + colour * 3
      palette.add VextRgb(r: data[offset], g: data[offset + 1],
        b: data[offset + 2])
    result.add VextPalette(colours: palette)

proc parseDoomSound*(data: openArray[byte]): DoomSoundSource =
  if data.len < 8:
    raise newException(ValueError, "truncated DOOM sound header")
  result = DoomSoundSource(format: littleWord(data, 0),
    sampleRate: littleWord(data, 2),
    declaredSamples: littleWord(data, 4),
    reserved: littleWord(data, 6))
  if result.format != 3:
    raise newException(ValueError, "DOOM sound format must be 3")
  if result.sampleRate <= 0:
    raise newException(ValueError, "DOOM sound sample rate must be positive")
  if result.reserved != 0:
    raise newException(ValueError, "DOOM sound reserved header field must be zero")
  if data.len != 8 + result.declaredSamples:
    raise newException(ValueError,
      "DOOM sound sample count does not match its lump length")
  result.samples = @data[8 ..< data.len]

proc decodeDoomSound*(source: DoomSoundSource): VextSound =
  var samples = newSeq[VextAudioSample](source.samples.len)
  for index, sample in source.samples:
    samples[index] = int32(sample) - 128
  result = VextSound(buffer: VextAudioBuffer(bitsPerSample: 8,
    channels: @[samples]), sampleRate: source.sampleRate)
  result.buffer.validate

proc isDoomMapMarker*(name: string): bool =
  let upper = name.toUpperAscii
  (upper.len == 4 and upper[0] == 'E' and upper[1] in {'0' .. '9'} and
    upper[2] == 'M' and upper[3] in {'0' .. '9'}) or
  (upper.len == 5 and upper.startsWith("MAP") and
    upper[3] in {'0' .. '9'} and upper[4] in {'0' .. '9'})

proc isDoomMapLumpName*(name: string): bool =
  name.toUpperAscii in ["THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES",
    "SEGS", "SSECTORS", "NODES", "SECTORS", "REJECT", "BLOCKMAP"]

proc checkedRecordCount*(data: openArray[byte], recordSize: int,
    label: string): int =
  if data.len mod recordSize != 0:
    raise newException(ValueError, label & " lump has a partial record")
  result = data.len div recordSize
  if result > MaximumDoomMapElements:
    raise newException(ValueError, label & " record count exceeds the safety limit")

proc parseDoomMapVertices*(data: openArray[byte]): seq[DoomMapVertex] =
  let count = checkedRecordCount(data, 4, "VERTEXES")
  for index in 0 ..< count:
    let offset = index * 4
    result.add DoomMapVertex(x: signedLittleWord(data, offset),
      y: signedLittleWord(data, offset + 2))

proc parseDoomMapLines*(data: openArray[byte],
    vertexCount: int): seq[DoomMapLine] =
  let count = checkedRecordCount(data, 14, "LINEDEFS")
  for index in 0 ..< count:
    let offset = index * 14
    let line = DoomMapLine(startVertex: littleWord(data, offset),
      endVertex: littleWord(data, offset + 2),
      flags: littleWord(data, offset + 4),
      lineType: littleWord(data, offset + 6),
      tag: littleWord(data, offset + 8),
      rightSide: signedLittleWord(data, offset + 10),
      leftSide: signedLittleWord(data, offset + 12))
    if line.startVertex >= vertexCount or line.endVertex >= vertexCount:
      raise newException(ValueError, "LINEDEFS references a missing vertex")
    if line.rightSide < 0:
      raise newException(ValueError, "LINEDEFS line has no right SIDEDEF")
    result.add line

proc parseDoomMapSides*(data: openArray[byte]): seq[DoomMapSide] =
  let count = checkedRecordCount(data, 30, "SIDEDEFS")
  for index in 0 ..< count:
    result.add DoomMapSide(sector: littleWord(data, index * 30 + 28))

proc parseDoomMapSectors*(data: openArray[byte]): seq[DoomMapSector] =
  let count = checkedRecordCount(data, 26, "SECTORS")
  for index in 0 ..< count:
    let offset = index * 26
    result.add DoomMapSector(floorHeight: signedLittleWord(data, offset),
      ceilingHeight: signedLittleWord(data, offset + 2))

proc validateDoomMapReferences*(source: DoomAutomapSource) =
  for line in source.lines:
    if line.rightSide >= source.sides.len or line.leftSide >= source.sides.len:
      raise newException(ValueError, "LINEDEFS references a missing SIDEDEF")
  for side in source.sides:
    if side.sector >= source.sectors.len:
      raise newException(ValueError, "SIDEDEFS references a missing SECTOR")

proc renderDoomAutomap*(source: DoomAutomapSource): VextTrueColourImage =
  if source.vertices.len == 0:
    raise newException(ValueError, "automap requires at least one vertex")
  if source.lines.len == 0:
    raise newException(ValueError, "automap requires at least one linedef")
  var minX = source.vertices[0].x
  var maxX = minX
  var minY = source.vertices[0].y
  var maxY = minY
  for vertex in source.vertices:
    minX = min(minX, vertex.x)
    maxX = max(maxX, vertex.x)
    minY = min(minY, vertex.y)
    maxY = max(maxY, vertex.y)
  let spanX = max(1, maxX - minX)
  let spanY = max(1, maxY - minY)
  const margin = 8
  let available = MaximumDoomAutomapDimension - margin * 2
  let scale = min(1.0, min(float(available) / float(spanX),
    float(available) / float(spanY)))
  let width = max(margin * 2 + 1,
    int(float(spanX) * scale) + margin * 2 + 1)
  let height = max(margin * 2 + 1,
    int(float(spanY) * scale) + margin * 2 + 1)
  var pixels = newSeq[VextRgb](width * height)

  proc plot(x, y: int, colour: VextRgb) =
    if x >= 0 and x < width and y >= 0 and y < height:
      pixels[y * width + x] = colour

  proc drawLine(x0, y0, x1, y1: int, colour: VextRgb) =
    var x = x0
    var y = y0
    let dx = abs(x1 - x0)
    let sx = if x0 < x1: 1 else: -1
    let dy = -abs(y1 - y0)
    let sy = if y0 < y1: 1 else: -1
    var error = dx + dy
    while true:
      plot(x, y, colour)
      if x == x1 and y == y1: break
      let twice = error * 2
      if twice >= dy:
        error += dy
        x += sx
      if twice <= dx:
        error += dx
        y += sy

  for line in source.lines:
    if (line.flags and (1 shl 7)) != 0: continue
    var colour = VextRgb(r: 128, g: 128, b: 128)
    if line.leftSide < 0 or (line.flags and (1 shl 5)) != 0:
      colour = VextRgb(r: 255, g: 0, b: 0)
    elif source.sides.len > 0 and source.sectors.len > 0:
      let right = source.sectors[source.sides[line.rightSide].sector]
      let left = source.sectors[source.sides[line.leftSide].sector]
      if right.ceilingHeight != left.ceilingHeight:
        colour = VextRgb(r: 255, g: 255, b: 0)
      elif right.floorHeight != left.floorHeight:
        colour = VextRgb(r: 160, g: 80, b: 0)
    let start = source.vertices[line.startVertex]
    let finish = source.vertices[line.endVertex]
    let x0 = margin + int(float(start.x - minX) * scale)
    let y0 = height - margin - 1 - int(float(start.y - minY) * scale)
    let x1 = margin + int(float(finish.x - minX) * scale)
    let y1 = height - margin - 1 - int(float(finish.y - minY) * scale)
    drawLine(x0, y0, x1, y1, colour)
  result = VextTrueColourImage(width: width, height: height, pixels: pixels)

proc parseDoomPatchNames*(data: openArray[byte]): seq[string] =
  if data.len < 4:
    raise newException(ValueError, "truncated PNAMES header")
  let count64 = littleLong(data, 0)
  if count64 > uint64(high(int)):
    raise newException(ValueError, "PNAMES count exceeds host limits")
  let count = int(count64)
  if count > (data.len - 4) div 8 or data.len != 4 + count * 8:
    raise newException(ValueError, "PNAMES name table has an invalid length")
  for index in 0 ..< count:
    result.add lumpName(data, 4 + index * 8)

proc parseDoomTextureDirectory*(data: openArray[byte]): DoomTextureDirectory =
  if data.len < 4:
    raise newException(ValueError, "truncated DOOM texture-directory header")
  let count64 = littleLong(data, 0)
  if count64 > uint64(high(int)):
    raise newException(ValueError, "DOOM texture count exceeds host limits")
  let count = int(count64)
  if count > (data.len - 4) div 4:
    raise newException(ValueError, "truncated DOOM texture offset table")
  let definitionsStart = 4 + count * 4
  for index in 0 ..< count:
    let offset64 = littleLong(data, 4 + index * 4)
    if offset64 > uint64(high(int)):
      raise newException(ValueError, "DOOM texture offset exceeds host limits")
    let offset = int(offset64)
    if offset < definitionsStart or offset > data.len - 22:
      raise newException(ValueError, "DOOM texture definition is outside its lump")
    var texture = DoomTexture(name: lumpName(data, offset),
      masked: littleLong(data, offset + 8),
      width: littleWord(data, offset + 12),
      height: littleWord(data, offset + 14),
      columnDirectory: littleLong(data, offset + 16))
    if texture.width <= 0 or texture.height <= 0:
      raise newException(ValueError, "DOOM texture dimensions must be positive")
    if texture.width > MaximumDoomPatchPixels div texture.height:
      raise newException(ValueError, "DOOM texture dimensions exceed the safety limit")
    let patchCount = littleWord(data, offset + 20)
    if patchCount > (data.len - offset - 22) div 10:
      raise newException(ValueError, "truncated DOOM texture patch table")
    for patchIndex in 0 ..< patchCount:
      let patchOffset = offset + 22 + patchIndex * 10
      texture.patches.add DoomTexturePatch(
        originX: signedLittleWord(data, patchOffset),
        originY: signedLittleWord(data, patchOffset + 2),
        patchIndex: littleWord(data, patchOffset + 4),
        stepDirection: signedLittleWord(data, patchOffset + 6),
        colourMap: signedLittleWord(data, patchOffset + 8))
    result.textures.add texture

proc decodeDoomFlat*(data: openArray[byte],
    palette: openArray[VextRgb]): VextIndexedImage =
  if data.len != DoomFlatSize:
    raise newException(ValueError, "DOOM flat must contain exactly 4096 pixels")
  if palette.len != DoomPaletteColours:
    raise newException(ValueError, "DOOM flat requires a 256-colour palette")
  VextIndexedImage(width: 64, height: 64, palette: @palette, pixels: @data)

proc parseDoomPatch*(data: openArray[byte]): DoomPatch =
  if data.len < 12:
    raise newException(ValueError, "truncated DOOM patch header")
  result.width = littleWord(data, 0)
  result.height = littleWord(data, 2)
  result.leftOffset = signedLittleWord(data, 4)
  result.topOffset = signedLittleWord(data, 6)
  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "DOOM patch dimensions must be positive")
  if result.width > MaximumDoomPatchPixels div result.height:
    raise newException(ValueError, "DOOM patch dimensions exceed the safety limit")
  if result.width > (data.len - 8) div 4:
    raise newException(ValueError, "truncated DOOM patch column table")
  let pixelDataStart = 8 + result.width * 4
  result.columns.setLen(result.width)
  for columnIndex in 0 ..< result.width:
    let offset64 = littleLong(data, 8 + columnIndex * 4)
    if offset64 > uint64(high(int)):
      raise newException(ValueError, "DOOM patch column offset exceeds host limits")
    var offset = int(offset64)
    if offset < pixelDataStart or offset >= data.len:
      raise newException(ValueError, "DOOM patch column is outside the pixel data")
    while true:
      let top = int(data[offset])
      inc offset
      if top == 255: break
      if offset > data.len - 2:
        raise newException(ValueError, "truncated DOOM patch post header")
      let length = int(data[offset])
      offset += 2 # Length and the unused leading byte.
      if top + length > result.height:
        raise newException(ValueError, "DOOM patch post exceeds its image height")
      if offset > data.len - length - 1:
        raise newException(ValueError, "truncated DOOM patch post pixels")
      result.columns[columnIndex].posts.add DoomPatchPost(top: top,
        pixels: @data[offset ..< offset + length])
      offset += length + 1 # Pixels and the unused trailing byte.

proc decodeDoomPatch*(patch: DoomPatch,
    palette: openArray[VextRgb]): VextIndexedImage =
  if palette.len != DoomPaletteColours:
    raise newException(ValueError, "DOOM patch requires a 256-colour palette")
  result = VextIndexedImage(width: patch.width, height: patch.height,
    palette: @palette, pixels: newSeq[uint8](patch.width * patch.height),
    alpha: newSeq[uint8](patch.width * patch.height))
  for x, column in patch.columns:
    for post in column.posts:
      for row, pixel in post.pixels:
        let target = (post.top + row) * patch.width + x
        result.pixels[target] = pixel
        result.alpha[target] = 255

proc composeDoomTexture*(texture: DoomTexture,
    patches: openArray[DoomPatch],
    palette: openArray[VextRgb]): VextIndexedImage =
  if patches.len != texture.patches.len:
    raise newException(ValueError,
      "DOOM texture patch data does not match its composition recipe")
  if palette.len != DoomPaletteColours:
    raise newException(ValueError, "DOOM texture requires a 256-colour palette")
  result = VextIndexedImage(width: texture.width, height: texture.height,
    palette: @palette, pixels: newSeq[uint8](texture.width * texture.height),
    alpha: newSeq[uint8](texture.width * texture.height))
  for placementIndex, patch in patches:
    let placement = texture.patches[placementIndex]
    for sourceX, column in patch.columns:
      let targetX = placement.originX + sourceX
      if targetX < 0 or targetX >= texture.width: continue
      for post in column.posts:
        for row, pixel in post.pixels:
          let targetY = placement.originY + post.top + row
          if targetY < 0 or targetY >= texture.height: continue
          let target = targetY * texture.width + targetX
          result.pixels[target] = pixel
          result.alpha[target] = 255

proc isDoomPatch*(data: openArray[byte]): bool =
  try:
    discard parseDoomPatch(data)
    true
  except ValueError:
    false
