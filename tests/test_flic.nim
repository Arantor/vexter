import std/unittest
import vexterlib

proc setWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)

proc setDword(data: var seq[byte], offset: int, value: uint32) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)
  data[offset + 2] = byte(value shr 16)
  data[offset + 3] = byte(value shr 24)

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc subchunk(kind: int, payload: openArray[byte]): seq[byte] =
  result = newSeq[byte](6)
  result.setWord(4, kind)
  result.add payload
  if result.len mod 2 != 0: result.add 0
  result.setDword(0, uint32(result.len))

proc frame(chunks: openArray[seq[byte]], delay = 0): seq[byte] =
  result = newSeq[byte](16)
  result.setWord(4, FlicFrameChunk)
  result.setWord(6, chunks.len)
  result.setWord(8, delay)
  for chunk in chunks: result.add chunk
  result.setDword(0, uint32(result.len))

proc prefix(chunks: openArray[seq[byte]]): seq[byte] =
  result = newSeq[byte](16)
  result.setWord(4, FlicPrefixChunk)
  result.setWord(6, chunks.len)
  for chunk in chunks: result.add chunk
  result.setDword(0, uint32(result.len))

proc huffmanTable(entries: openArray[(int, int, int)]): seq[byte] =
  result = newSeq[byte](16)
  result.setWord(4, FlicHuffmanTableChunk)
  result.setWord(6, 16)
  result.setWord(8, entries.len)
  for (code, length, value) in entries:
    result.addWord(code)
    result.add byte(length)
    result.add byte(value)
  result.setDword(0, uint32(result.len))

proc flic(magic, width, height, depth, frames, speed: int,
    chunks: openArray[seq[byte]], creator = 0, extensionFlags = 0): seq[byte] =
  result = newSeq[byte](128)
  result.setWord(4, magic)
  result.setWord(6, frames)
  result.setWord(8, width)
  result.setWord(10, height)
  result.setWord(12, depth)
  result.setWord(14, 3)
  result.setDword(16, uint32(speed))
  result.setDword(22, uint32(creator))
  result.setWord(38, extensionFlags)
  for chunk in chunks: result.add chunk
  result.setDword(0, uint32(result.len))

suite "FLI and FLC animations":
  test "palette, BYTE_RUN, DELTA_FLC, timing, and ring-frame omission":
    var palette1: seq[byte]
    palette1.addWord(1)
    palette1.add @[0'u8, 3, 0, 0, 0, 63, 0, 0, 0, 63, 0]
    let brun = @[1'u8, 0xfd, 0, 1, 2, 1, 0xfd, 2, 1, 0]
    var palette2: seq[byte]
    palette2.addWord(1)
    palette2.add @[1'u8, 1, 63, 63, 0]
    var delta: seq[byte]
    delta.addWord(1)
    delta.addWord(0xffff)
    delta.addWord(0x8002)
    delta.addWord(0)
    let data = flic(FlicMagicFlc, 3, 2, 8, 2, 40, @[
      frame(@[subchunk(11, palette1), subchunk(15, brun)]),
      frame(@[subchunk(4, palette2), subchunk(7, delta)], delay = 25),
      frame(@[subchunk(13, @[])])])

    let inspection = inspectSource("colours.flc", data)
    check inspection.selectedFormat.typeId == FlicTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.rasterResources[0]
    check resource.path == FlicAnimationResourcePath
    check resource.typeId == FlicAnimationTypeId
    check resource.raster.kind == vrkIndexedAnimation
    let animation = resource.raster.animation
    check animation.frames.len == 2
    check animation.frames[0].durationMs == 40
    check animation.frames[1].durationMs == 25
    check animation.frames[0].image.pixels == @[0'u8, 1, 2, 2, 1, 0]
    check animation.frames[1].image.pixels == @[0'u8, 1, 2, 2, 1, 2]
    check animation.frames[0].image.palette[1] == VextRgb(r: 255, g: 0, b: 0)
    check animation.frames[1].image.palette[1] == VextRgb(r: 63, g: 63, b: 0)
    check resource.defaultExportFormat == "gif"

  test "DELTA_FLI supports literal, repeat, and zero-length skip packets":
    let copy = @[0'u8, 0, 0, 0, 0, 0]
    var delta: seq[byte]
    delta.addWord(0)
    delta.addWord(1)
    delta.add 3
    delta.add @[1'u8, 2, 9, 8, 0, 0, 1, 0xfe, 7]
    let animation = decodeFlic(parseFlic(flic(FlicMagicFlc, 6, 1, 8, 2, 10, @[
      frame(@[subchunk(16, copy)]), frame(@[subchunk(12, delta)])]))).animation
    check animation.frames[1].image.pixels == @[0'u8, 9, 8, 0, 7, 7]

  test "DTA copy, pixel RLE, and pixel delta produce true-colour frames":
    let first = @[0x00'u8, 0xf8, 0xe0, 0x07]
    let brun = @[1'u8, 2, 0x1f, 0x00]
    var delta: seq[byte]
    delta.addWord(1)
    delta.addWord(1)
    delta.add @[1'u8, 1, 0xe0, 0x07]
    let animation = decodeFlic(parseFlic(flic(FlicMagicDta, 2, 1, 16, 3, 12, @[
      frame(@[subchunk(26, first)]),
      frame(@[subchunk(25, brun)]),
      frame(@[subchunk(27, delta)])]))).trueColourAnimation
    check animation.frames[0].image.pixels == @[
      VextRgb(r: 248, g: 0, b: 0), VextRgb(r: 0, g: 252, b: 0)]
    check animation.frames[1].image.pixels == @[
      VextRgb(r: 0, g: 0, b: 248), VextRgb(r: 0, g: 0, b: 248)]
    check animation.frames[2].image.pixels == @[
      VextRgb(r: 0, g: 0, b: 248), VextRgb(r: 0, g: 252, b: 0)]

  test "24-bit DTA and 15-bit FLX copy layouts are decoded":
    let dta = decodeFlic(parseFlic(flic(FlicMagicDta, 1, 1, 24, 1, 1,
      @[frame(@[subchunk(26, @[3'u8, 2, 1])])]))).trueColourAnimation
    check dta.frames[0].image.pixels[0] == VextRgb(r: 1, g: 2, b: 3)
    let flx = decodeFlic(parseFlic(flic(FlicMagicFlc, 1, 1, 15, 1, 1,
      @[frame(@[subchunk(16, @[0x00'u8, 0x7c])])]))).trueColourAnimation
    check flx.frames[0].image.pixels[0] == VextRgb(r: 248, g: 0, b: 0)

  test "CEL prefix metadata and FLI tick timing are retained":
    var cel = newSeq[byte](58)
    cel.setWord(0, 0xfffe)
    cel.setWord(2, 3)
    let celChunk = subchunk(3, cel)
    let pixels = newSeq[byte](320 * 200)
    let source = parseFlic(flic(FlicMagicFli, 320, 200, 8, 1, 5, @[
      prefix(@[celChunk]), frame(@[subchunk(16, pixels)])]))
    check source.prefixChunks.len == 1
    check source.prefixChunks[0].kind == 3
    check source.celCenterX == -2
    check source.celCenterY == 3
    let decoded = decodeFlic(source).animation.frames[0]
    check decoded.durationMs == 71
    check decoded.image.alpha[0] == 0

  test "EGI Huffman and BWT-Huffman blocks expand before FLIC RLE":
    let plain = decodeFlic(parseFlic(flic(FlicMagicCompressed, 3, 1, 8, 1, 1,
      @[huffmanTable([(0x0000, 1, 1), (0x8000, 2, 3), (0xc000, 2, 5)]),
        frame(@[subchunk(15, @[1'u8, 0, 3, 0, 0x58])])],
      creator = 0x45474900, extensionFlags = 0x08))).animation
    check plain.frames[0].image.pixels == @[5'u8, 5, 5]

    let bwt = decodeFlic(parseFlic(flic(FlicMagicCompressed, 3, 1, 8, 1, 1,
      @[huffmanTable([(0x0000, 1, 3), (0x8000, 1, 5)]),
        frame(@[subchunk(15, @[1'u8, 0, 3, 0, 2, 0, 0x40])])],
      creator = 0x45474900, extensionFlags = 0x10))).animation
    check bwt.frames[0].image.pixels == @[5'u8, 5, 5]

  test "EGI frame shift copies source scanlines and extends edge pixels":
    let copy = @[1'u8, 2, 3, 4, 5, 6]
    let shift = @[0'u8, 0, 0, 0, 0xfe, 1, 0, 0xfe, 1, 0xff]
    let animation = decodeFlic(parseFlic(flic(FlicMagicFrameShift, 3, 2, 8,
      2, 1, @[frame(@[subchunk(16, copy)]),
        frame(@[subchunk(42, shift)])]))).animation
    check animation.frames[1].image.pixels == @[4'u8, 4, 5, 5, 6, 6]

  test "EGI compression families retain 16- and 24-bit pixel layouts":
    let compressed16 = decodeFlic(parseFlic(flic(FlicMagicCompressed, 2, 1,
      16, 1, 1, @[huffmanTable([(0x0000, 1, 0)]),
        frame(@[subchunk(26, @[0x00'u8, 0xf8, 0xe0, 0x07])])],
      creator = 0x45474900, extensionFlags = 0x08))).trueColourAnimation
    check compressed16.frames[0].image.pixels == @[
      VextRgb(r: 248, g: 0, b: 0), VextRgb(r: 0, g: 252, b: 0)]

    let copy24 = @[3'u8, 2, 1, 6, 5, 4, 9, 8, 7, 12, 11, 10]
    let shift = @[0'u8, 0, 0, 0, 0xfe, 1, 0, 0xfe, 1, 0xff]
    let shifted24 = decodeFlic(parseFlic(flic(FlicMagicFrameShift, 2, 2,
      24, 2, 1, @[frame(@[subchunk(26, copy24)]),
        frame(@[subchunk(42, shift)])]))).trueColourAnimation
    check shifted24.frames[1].image.pixels == @[
      VextRgb(r: 7, g: 8, b: 9), VextRgb(r: 7, g: 8, b: 9),
      VextRgb(r: 10, g: 11, b: 12), VextRgb(r: 10, g: 11, b: 12)]

  test "invalid sizes, counts, and codec boundaries are rejected":
    var badSize = flic(FlicMagicFlc, 1, 1, 8, 1, 1,
      @[frame(@[subchunk(16, @[0'u8])])])
    badSize.setDword(0, uint32(badSize.len - 1))
    expect ValueError: discard parseFlic(badSize)

    expect ValueError:
      discard parseFlic(flic(FlicMagicFlc, 1, 1, 8, 2, 1,
        @[frame(@[subchunk(16, @[0'u8])])]))

    let overrun = flic(FlicMagicFlc, 1, 1, 8, 1, 1,
      @[frame(@[subchunk(15, @[1'u8, 2, 0])])])
    expect ValueError: discard decodeFlic(parseFlic(overrun))
