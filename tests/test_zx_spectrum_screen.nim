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

proc updatePlus3Checksum(data: var seq[byte]) =
  var checksum = 0
  for index in 0 .. 126: checksum = (checksum + int(data[index])) and 0xff
  data[127] = byte(checksum)

proc headeredScreen(screen: openArray[byte]): seq[byte] =
  result = newSeq[byte](ZxSpectrumHeaderedScreenSize)
  for index, value in Plus3DosSignature: result[index] = byte(value)
  result[8] = Plus3DosSoftEof
  result[9] = 1
  let total = uint32(result.len)
  for index in 0 .. 3: result[11 + index] = byte(total shr (index * 8))
  result[15] = ZxSpectrumCodeBasicType
  result[16] = byte(ZxSpectrumScreenSize)
  result[17] = byte(ZxSpectrumScreenSize shr 8)
  result[18] = byte(ZxSpectrumScreenLoadAddress)
  result[19] = byte(ZxSpectrumScreenLoadAddress shr 8)
  result.updatePlus3Checksum()
  for index, value in screen:
    result[Plus3DosHeaderSize + index] = value

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
    let raster = decodeZxSpectrumScreen(fixture)

    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumScreenTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 2

    check raster.kind == vrkIndexedAnimation
    let animation = raster.animation
    check raster.width == 256
    check raster.height == 192
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

  test "+3DOS headered screens validate and expose the ordinary payload":
    let screen = readBytes(FixturePath)
    let data = headeredScreen(screen)
    check data.len == 7040
    check isHeaderedZxSpectrumScreenDump(data)
    check extractZxSpectrumScreenDump(data) == screen
    let candidates = detectFormats("colours.SCR", data)
    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumScreenTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 2
    let raster = inspectSource("colours.SCR", data).resources.
      rasterResources[0].raster
    check raster.width == 256
    check raster.height == 192

  test "+3DOS screen BASIC type, length, and load address are required":
    let valid = headeredScreen(newSeq[byte](ZxSpectrumScreenSize))
    for offset in [15, 16, 17, 18, 19]:
      var damaged = valid
      damaged[offset] = damaged[offset] xor 1
      damaged.updatePlus3Checksum()
      check not isHeaderedZxSpectrumScreenDump(damaged)
      check detectFormats("damaged.scr", damaged).len == 0

  test "a non-FLASH screen produces an indexed image":
    var screen = newSeq[byte](ZxSpectrumScreenSize)
    let raster = decodeZxSpectrumScreen(screen)
    check raster.kind == vrkIndexedImage
    check raster.image.width == 256
    check raster.image.height == 192

  test "listing fixture produces an indexed image":
    let raster = decodeZxSpectrumScreen(readBytes(
      "tests/fixtures/zx-spectrum.screen/colours-listing.scr"))
    check raster.kind == vrkIndexedImage
    check raster.image.width == 256
    check raster.image.height == 192
