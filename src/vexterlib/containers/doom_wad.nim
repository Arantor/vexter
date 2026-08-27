## Structural validation and image extraction for classic DOOM IWAD/PWAD files.

import std/[os, strutils]
import ../archetypes/[palette, raster]

const
  DoomWadTypeId* = "doom.wad"
  DoomWadPaletteTypeId* = "doom.palette"
  DoomWadFlatTypeId* = "doom.flat"
  DoomWadPatchTypeId* = "doom.patch"
  DoomWadLumpTypeId* = "doom.lump"
  DoomPaletteColours* = 256
  DoomPaletteBytes* = DoomPaletteColours * 3
  DoomPaletteCount* = 14
  DoomFlatSize* = 64 * 64
  MaximumDoomPatchPixels* = 64 * 1024 * 1024

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

proc isDoomPatch*(data: openArray[byte]): bool =
  try:
    discard parseDoomPatch(data)
    true
  except ValueError:
    false
