## Parsing and decompression for AMOS Pac.Pic. bank payloads.

const
  AmosPackedPictureBankType* = "Pac.Pic."
  AmosPackedPictureScreenHeaderSize* = 90
  AmosPackedPictureHeaderSize* = 24
  AmosPackedPictureMagic* = 0x06071963'u32

type
  AmosPackedPicture* = object
    hasScreenHeader*: bool
    screenWidth*, screenHeight*: int
    screenX*, screenY*: int
    displayWidth*, displayHeight*: int
    hardwareOffsetX*, hardwareOffsetY*: int
    bplcon0*: int
    colourCount*: int
    paletteWords*: seq[uint16]
    xOffsetBytes*, yOffset*: int
    widthBytes*, lumps*, lumpHeight*, planes*: int
    planeData*: seq[byte]

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc isScreenMagic(value: uint32): bool =
  value == 0x12031990'u32 or value == 0x00031990'u32 or
    value == 0x12030090'u32

proc parseAmosPackedPicture*(data: openArray[byte]): AmosPackedPicture =
  if data.len < AmosPackedPictureHeaderSize:
    raise newException(ValueError, "truncated AMOS packed picture")

  var pictureOffset = 0
  if beDword(data, 0).isScreenMagic:
    if data.len < AmosPackedPictureScreenHeaderSize + AmosPackedPictureHeaderSize:
      raise newException(ValueError, "truncated AMOS packed-picture screen header")
    result.hasScreenHeader = true
    result.screenWidth = beWord(data, 4)
    result.screenHeight = beWord(data, 6)
    result.screenX = beWord(data, 8)
    result.screenY = beWord(data, 10)
    result.displayWidth = beWord(data, 12)
    result.displayHeight = beWord(data, 14)
    result.hardwareOffsetX = beWord(data, 16)
    result.hardwareOffsetY = beWord(data, 18)
    result.bplcon0 = beWord(data, 20)
    result.colourCount = beWord(data, 22)
    result.planes = beWord(data, 24)
    for index in 0 ..< 32:
      result.paletteWords.add uint16(beWord(data, 26 + index * 2))
    pictureOffset = AmosPackedPictureScreenHeaderSize

  if beDword(data, pictureOffset) != AmosPackedPictureMagic:
    raise newException(ValueError, "invalid AMOS packed-picture header")
  result.xOffsetBytes = beWord(data, pictureOffset + 4)
  result.yOffset = beWord(data, pictureOffset + 6)
  result.widthBytes = beWord(data, pictureOffset + 8)
  result.lumps = beWord(data, pictureOffset + 10)
  result.lumpHeight = beWord(data, pictureOffset + 12)
  let picturePlanes = beWord(data, pictureOffset + 14)
  if result.hasScreenHeader and result.planes != picturePlanes:
    raise newException(ValueError, "AMOS packed-picture plane counts disagree")
  result.planes = picturePlanes
  if result.widthBytes <= 0 or result.lumps <= 0 or result.lumpHeight <= 0 or
      result.planes < 1 or result.planes > 6:
    raise newException(ValueError, "invalid AMOS packed-picture geometry")

  let
    rleOffset = int(beDword(data, pictureOffset + 16))
    pointsOffset = int(beDword(data, pictureOffset + 20))
    picStart = pictureOffset + AmosPackedPictureHeaderSize
    rleStart = pictureOffset + rleOffset
    pointsStart = pictureOffset + pointsOffset
  if rleOffset < AmosPackedPictureHeaderSize or pointsOffset < AmosPackedPictureHeaderSize or
      picStart >= data.len or rleStart >= data.len or pointsStart >= data.len:
    raise newException(ValueError, "invalid AMOS packed-picture stream offsets")

  var picPos = picStart
  let picEnd = min(rleStart, pointsStart)
  var rlePos = rleStart
  var pointsPos = pointsStart
  var picByte = data[picPos]
  inc picPos
  var rleByte = data[rlePos]
  inc rlePos
  if (data[pointsPos] and 0x80) != 0:
    if rlePos >= data.len:
      raise newException(ValueError, "truncated AMOS packed-picture RLE stream")
    rleByte = data[rlePos]
    inc rlePos
  var rbit = 7
  var rrbit = 6
  let height = result.lumps * result.lumpHeight
  result.planeData = newSeq[byte](result.planes * result.widthBytes * height)

  for plane in 0 ..< result.planes:
    for lump in 0 ..< result.lumps:
      for column in 0 ..< result.widthBytes:
        for row in 0 ..< result.lumpHeight:
          if (rleByte and byte(1 shl rbit)) != 0:
            if picPos >= picEnd:
              raise newException(ValueError, "truncated AMOS packed-picture data stream")
            picByte = data[picPos]
            inc picPos
          result.planeData[(plane * height + lump * result.lumpHeight + row) *
            result.widthBytes + column] = picByte
          dec rbit
          if rbit < 0:
            rbit = 7
            if pointsPos >= data.len:
              raise newException(ValueError, "truncated AMOS packed-picture points stream")
            if (data[pointsPos] and byte(1 shl rrbit)) != 0:
              if rlePos >= data.len:
                raise newException(ValueError, "truncated AMOS packed-picture RLE stream")
              rleByte = data[rlePos]
              inc rlePos
            dec rrbit
            if rrbit < 0:
              rrbit = 7
              inc pointsPos
