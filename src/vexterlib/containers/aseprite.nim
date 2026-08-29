## Aseprite .ase/.aseprite structural and palette parsing.

import std/[strutils, unicode]
import ../archetypes/[palette, raster]

const
  AsepriteTypeId* = "aseprite.sprite"
  AsepritePaletteResourcePath* = "/palette"
  AsepriteMagic* = 0xa5e0
  AsepriteFrameMagic* = 0xf1fa
  MaximumAsepritePaletteColours* = 65536

type
  AsepritePaletteChange = object
    chunkType: int
    newSize: int
    firstIndex: int
    colours: seq[VextRgba]

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

proc word(data: openArray[byte], offset: int): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated Aseprite WORD")
  int(data[offset]) or int(data[offset + 1]) shl 8

proc dword(data: openArray[byte], offset: int): uint32 =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "truncated Aseprite DWORD")
  uint32(data[offset]) or uint32(data[offset + 1]) shl 8 or
    uint32(data[offset + 2]) shl 16 or uint32(data[offset + 3]) shl 24

proc checkedInt(value: uint32, description: string): int =
  if uint64(value) > uint64(high(int)):
    raise newException(ValueError, description & " exceeds host limits")
  int(value)

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

proc applyChanges(changes: seq[AsepritePaletteChange], preferNew: bool): VextPalette =
  var colours: seq[VextRgba]
  for change in changes:
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

  var changes: seq[AsepritePaletteChange]
  var hasNewPalette = false
  var offset = 128
  for frameIndex in 0 ..< result.frames:
    if offset + 16 > data.len:
      raise newException(ValueError, "truncated Aseprite frame header")
    let frameSize = checkedInt(dword(data, offset), "Aseprite frame size")
    if frameSize < 16 or frameSize > data.len - offset or
        word(data, offset + 4) != AsepriteFrameMagic:
      raise newException(ValueError, "invalid Aseprite frame header")
    let oldChunkCount = word(data, offset + 6)
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
        changes.add parseNewPalette(data, chunkStart, chunkLimit)
        hasNewPalette = true
        inc result.paletteChunkCount
      of 0x0004, 0x0011:
        changes.add parseOldPalette(data, chunkStart, chunkLimit, chunkType)
        inc result.paletteChunkCount
      else: discard
      inc result.chunkCount
      chunkOffset = chunkLimit
    if chunkOffset != frameLimit:
      raise newException(ValueError, "Aseprite frame size does not match its chunks")
    offset = frameLimit
  if offset != data.len:
    raise newException(ValueError, "unexpected data after Aseprite frames")
  result.palette = applyChanges(changes, hasNewPalette)

proc isAseprite*(data: openArray[byte]): bool =
  try:
    discard parseAseprite(data)
    true
  except ValueError:
    false

proc hasAsepriteExtension*(filename: string): bool =
  let lower = filename.toLowerAscii
  lower.endsWith(".ase") or lower.endsWith(".aseprite")
