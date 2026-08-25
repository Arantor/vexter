## Structural parsing for Commodore 64 KoalaPainter images.

import std/[os, strutils]

const
  KoalaPainterTypeId* = "commodore64.koala-painter"
  KoalaPainterFileSize* = 10003
  KoalaPainterLoadAddress* = 0x6000
  KoalaBitmapOffset* = 2
  KoalaScreenRamOffset* = KoalaBitmapOffset + 8000
  KoalaColourRamOffset* = KoalaScreenRamOffset + 1000
  KoalaBackgroundOffset* = KoalaColourRamOffset + 1000

type
  KoalaPainterSource* = object
    loadAddress*: int
    bitmap*: seq[byte]
    screenRam*: seq[byte]
    colourRam*: seq[byte]
    backgroundByte*: uint8
    backgroundColour*: uint8
    trailingByteCount*: int

proc parseKoalaPainter*(data: openArray[byte]): KoalaPainterSource =
  if data.len < KoalaPainterFileSize:
    raise newException(ValueError,
      "KoalaPainter image must contain at least 10003 bytes")
  result.loadAddress = int(data[0]) or (int(data[1]) shl 8)
  result.bitmap.add data.toOpenArray(KoalaBitmapOffset,
    KoalaScreenRamOffset - 1)
  result.screenRam.add data.toOpenArray(KoalaScreenRamOffset,
    KoalaColourRamOffset - 1)
  result.colourRam.add data.toOpenArray(KoalaColourRamOffset,
    KoalaBackgroundOffset - 1)
  result.backgroundByte = data[KoalaBackgroundOffset]
  result.backgroundColour = result.backgroundByte and 0x0f
  result.trailingByteCount = data.len - KoalaPainterFileSize

proc isKoalaPainter*(data: openArray[byte]): bool =
  try:
    discard parseKoalaPainter(data)
    true
  except ValueError:
    false

proc hasKoalaPainterExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii in [".kla", ".koa", ".koala", ".prg"]
