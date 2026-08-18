## Structural parsing for GIF87a and GIF89a image streams.

import std/[os, strutils]

const GifTypeId* = "gif"

type
  GifExtension* = object
    label*: int
    dataLength*: int

  GifFrameSource* = object
    x*, y*, width*, height*: int
    interlaced*: bool
    palette*: seq[byte]
    lzwMinimumCodeSize*: int
    compressedData*: seq[byte]
    delayMs*: int
    disposal*: int
    transparentIndex*: int

  GifImageSource* = object
    version*: string
    width*, height*: int
    backgroundIndex*: int
    pixelAspectRatio*: int
    globalPalette*: seq[byte]
    frames*: seq[GifFrameSource]
    extensions*: seq[GifExtension]

proc leWord(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc readSubBlocks(data: openArray[byte], offset: var int,
    retained: var seq[byte]): int =
  while true:
    if offset >= data.len:
      raise newException(ValueError, "truncated GIF data sub-block")
    let count = int(data[offset]); inc offset
    if count == 0: break
    if count > data.len - offset:
      raise newException(ValueError, "truncated GIF data sub-block")
    retained.add data.toOpenArray(offset, offset + count - 1)
    result += count
    offset += count

proc readPalette(data: openArray[byte], offset: var int,
    count: int): seq[byte] =
  let length = count * 3
  if length > data.len - offset:
    raise newException(ValueError, "truncated GIF colour table")
  result.add data.toOpenArray(offset, offset + length - 1)
  offset += length

proc parseGif*(data: openArray[byte]): GifImageSource =
  if data.len < 14:
    raise newException(ValueError, "GIF stream is too short")
  for index in 0 ..< 6: result.version.add char(data[index])
  if result.version notin ["GIF87a", "GIF89a"]:
    raise newException(ValueError, "invalid GIF87a/GIF89a signature")
  result.width = leWord(data, 6)
  result.height = leWord(data, 8)
  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "GIF logical screen dimensions must be positive")
  let packed = data[10]
  result.backgroundIndex = int(data[11])
  result.pixelAspectRatio = int(data[12])
  var offset = 13
  if (packed and 0x80) != 0:
    result.globalPalette = readPalette(data, offset,
      1 shl (int(packed and 7) + 1))

  var delayMs = 0
  var disposal = 0
  var transparentIndex = -1
  var hasPendingControl = false
  var trailer = false
  while offset < data.len:
    let introducer = data[offset]; inc offset
    case introducer
    of 0x2c:
      if data.len - offset < 9:
        raise newException(ValueError, "truncated GIF image descriptor")
      var frame = GifFrameSource(x: leWord(data, offset),
        y: leWord(data, offset + 2), width: leWord(data, offset + 4),
        height: leWord(data, offset + 6), transparentIndex: transparentIndex,
        delayMs: delayMs, disposal: disposal)
      let imagePacked = data[offset + 8]
      offset += 9
      frame.interlaced = (imagePacked and 0x40) != 0
      if frame.width <= 0 or frame.height <= 0 or frame.x < 0 or frame.y < 0 or
          frame.width > result.width - frame.x or
          frame.height > result.height - frame.y:
        raise newException(ValueError, "GIF frame lies outside the logical screen")
      if (imagePacked and 0x80) != 0:
        frame.palette = readPalette(data, offset,
          1 shl (int(imagePacked and 7) + 1))
      else:
        frame.palette = result.globalPalette
      if frame.palette.len == 0:
        raise newException(ValueError, "GIF frame has no colour table")
      if offset >= data.len:
        raise newException(ValueError, "truncated GIF image data")
      frame.lzwMinimumCodeSize = int(data[offset]); inc offset
      if frame.lzwMinimumCodeSize < 2 or frame.lzwMinimumCodeSize > 8:
        raise newException(ValueError, "invalid GIF LZW minimum code size")
      discard readSubBlocks(data, offset, frame.compressedData)
      if frame.compressedData.len == 0:
        raise newException(ValueError, "GIF frame contains no image data")
      result.frames.add frame
      delayMs = 0; disposal = 0; transparentIndex = -1
      hasPendingControl = false
    of 0x21:
      if offset >= data.len:
        raise newException(ValueError, "truncated GIF extension")
      let label = int(data[offset]); inc offset
      if label == 0xf9:
        if hasPendingControl or data.len - offset < 6 or data[offset] != 4 or
            data[offset + 5] != 0:
          raise newException(ValueError, "invalid GIF graphic control extension")
        let control = data[offset + 1]
        disposal = int((control shr 2) and 7)
        if disposal > 3:
          raise newException(ValueError, "unsupported GIF disposal method")
        delayMs = leWord(data, offset + 2) * 10
        transparentIndex = if (control and 1) != 0: int(data[offset + 4]) else: -1
        offset += 6
        hasPendingControl = true
        result.extensions.add GifExtension(label: label, dataLength: 4)
      else:
        var extensionData: seq[byte]
        let length = readSubBlocks(data, offset, extensionData)
        result.extensions.add GifExtension(label: label, dataLength: length)
        if label == 0x01 and hasPendingControl:
          # A graphic control applies to the next rendering block. Plain Text
          # is retained as metadata but not rendered, so it consumes control.
          delayMs = 0; disposal = 0; transparentIndex = -1
          hasPendingControl = false
    of 0x3b:
      trailer = true
      if offset != data.len:
        raise newException(ValueError, "GIF has data after its trailer")
      break
    else:
      raise newException(ValueError, "invalid GIF block introducer")
  if not trailer or result.frames.len == 0:
    raise newException(ValueError, "GIF is missing an image or trailer")

proc isGif*(data: openArray[byte]): bool =
  try: discard parseGif(data); true
  except ValueError: false

proc hasGifExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".gif"
