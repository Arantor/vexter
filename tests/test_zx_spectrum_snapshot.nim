{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/unittest
import vexterlib

const
  SnapshotFixturePath = "tests/fixtures/zx-spectrum.snapshot/colours.sna"
  ScreenFixturePath = "tests/fixtures/zx-spectrum.screen/colours.scr"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc rgbDigest(image: VextIndexedImage): string =
  var rgb = newStringOfCap(image.width * image.height * 3)
  for paletteIndex in image.pixels:
    let colour = image.palette[int(paletteIndex)]
    rgb.add char(colour.r)
    rgb.add char(colour.g)
    rgb.add char(colour.b)
  $secureHash(rgb)

suite "48K ZX Spectrum SNA snapshot":
  test "registration uses stable type and probable evidence":
    let snapshot = readBytes(SnapshotFixturePath)
    let candidates = detectFormats("COLOURS.SNA", snapshot)

    check ZxSpectrumSnapshotTypeId == "zx-spectrum.snapshot"
    check ZxSpectrumSnapshot48Size == 49179
    check ZxSpectrumSnapshotHeaderSize == 27
    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumSnapshotTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 2

  test "screen memory is identical to the raw screen fixture":
    let extracted = extractZxSpectrumSnapshotScreen(
      readBytes(SnapshotFixturePath))
    check extracted == readBytes(ScreenFixturePath)

  test "screen resource follows the indexed animation pathway":
    let animation = decodeScreenResource(ZxSpectrumSnapshotTypeId,
      readBytes(SnapshotFixturePath))

    check animation.width == 256
    check animation.height == 192
    check animation.frames.len == 2
    check rgbDigest(animation.frames[0].image) ==
      "D015DC2D86191595A79AD76A67CB81D05890DD63"
    check rgbDigest(animation.frames[1].image) ==
      "BEADAF8502A6EA42BCDE702E8278DE3523EE7E95"

  test "invalid snapshot lengths are rejected":
    expect ValueError:
      discard extractZxSpectrumSnapshotScreen(
        newSeq[byte](ZxSpectrumSnapshot48Size - 1))
