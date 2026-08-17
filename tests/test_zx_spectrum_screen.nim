{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/unittest
import vexterlib

const FixturePath = "tests/fixtures/zx-spectrum.screen/colours.scr"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for i, value in contents:
    result[i] = byte(value)

proc rgbDigest(image: VextIndexedImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for paletteIndex in image.pixels:
    let colour = image.palette[int(paletteIndex)]
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

suite "ZX Spectrum raw screen":
  test "type and resource identifiers are stable":
    check ZxSpectrumScreenTypeId == "zx-spectrum.screen"
    check ZxSpectrumScreenResourcePath == "/screen"

  test "colours control covers ink, paper, BRIGHT, and FLASH":
    let fixture = readBytes(FixturePath)
    let candidates = detectFormats(FixturePath, fixture)
    let animation = decodeZxSpectrumScreen(fixture)

    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumScreenTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 2

    check animation.width == 256
    check animation.height == 192
    check animation.frames.len == 2
    check animation.frames[0].durationMs == 320
    check animation.frames[1].durationMs == 320
    check animation.frames[0].image.palette.len == 16
    check animation.frames[0].image.pixels.len == 256 * 192

    # These hashes are over expanded RGB canvases, not the encoded control
    # files. The first matches both colours.png and GIF frame zero; the second
    # matches the fully composited second GIF frame.
    check rgbDigest(animation.frames[0].image) ==
      "D015DC2D86191595A79AD76A67CB81D05890DD63"
    check rgbDigest(animation.frames[1].image) ==
      "BEADAF8502A6EA42BCDE702E8278DE3523EE7E95"

    # Rows 0..7 are non-FLASH and rows 8..15 are FLASH. Columns 0..7
    # are normal and columns 8..15 are BRIGHT. The filled bitmap exposes ink
    # naturally; the swapped FLASH phase exposes paper in the bottom half.
    for attributeRow in 0 ..< 16:
      for attributeColumn in 0 ..< 16:
        let
          x = attributeColumn * 8
          y = attributeRow * 8
          brightness = if attributeColumn >= 8: 8'u8 else: 0'u8
          ink = uint8(attributeRow mod 8) + brightness
          paper = uint8(attributeColumn mod 8) + brightness
        check animation.frames[0].image.pixelAt(x, y) == ink
        check animation.frames[1].image.pixelAt(x, y) ==
          (if attributeRow >= 8: paper else: ink)

    # Everything outside the filled 128 by 128 region is normal white paper.
    for frame in animation.frames:
      check frame.image.pixelAt(128, 0) == 7
      check frame.image.pixelAt(0, 128) == 7
      check frame.image.pixelAt(255, 191) == 7

    let png = exportPng(animation.frames[0].image).artifacts[0]
    let gif = exportGif(animation).artifacts[0]
    check png.mediaType == "image/png"
    check png.data[0 .. 7] == @[137'u8, 80, 78, 71, 13, 10, 26, 10]
    check gif.mediaType == "image/gif"
    check gif.data[0 .. 5] == @[byte('G'), byte('I'), byte('F'), byte('8'),
      byte('9'), byte('a')]
    check gif.data[^1] == 0x3b

  test "invalid byte lengths are rejected":
    expect ValueError:
      discard decodeZxSpectrumScreen(newSeq[byte](ZxSpectrumScreenSize - 1))

  test "a non-FLASH screen produces one frame":
    var screen = newSeq[byte](ZxSpectrumScreenSize)
    let animation = decodeZxSpectrumScreen(screen)
    check animation.frames.len == 1
