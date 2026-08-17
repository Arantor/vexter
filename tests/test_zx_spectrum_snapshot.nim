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

suite "ZX Spectrum SNA snapshot":
  test "registration uses stable type and probable evidence":
    let snapshot = readBytes(SnapshotFixturePath)
    let candidates = detectFormats("COLOURS.SNA", snapshot)

    check ZxSpectrumSnapshotTypeId == "zx-spectrum.snapshot"
    check ZxSpectrumSnapshot48Size == 49179
    check ZxSpectrumSnapshot128Size == 131103
    check ZxSpectrumSnapshot128ExtendedSize == 147487
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
    let raster = decodeScreenResource(ZxSpectrumSnapshotTypeId,
      readBytes(SnapshotFixturePath))

    check raster.kind == vrkIndexedAnimation
    let animation = raster.animation
    check raster.width == 256
    check raster.height == 192
    check animation.frames.len == 2
    check rgbDigest(animation.frames[0].image) ==
      "D015DC2D86191595A79AD76A67CB81D05890DD63"
    check rgbDigest(animation.frames[1].image) ==
      "BEADAF8502A6EA42BCDE702E8278DE3523EE7E95"

  test "invalid snapshot lengths are rejected":
    expect ValueError:
      discard extractZxSpectrumSnapshotScreen(
        newSeq[byte](ZxSpectrumSnapshot48Size - 1))

  test "both 128K layouts are detected and expose screen memory at offset 27":
    for size in [ZxSpectrumSnapshot128Size,
        ZxSpectrumSnapshot128ExtendedSize]:
      var snapshot = newSeq[byte](size)
      for index in 0 ..< ZxSpectrumScreenSize:
        snapshot[ZxSpectrumSnapshotHeaderSize + index] = byte(index mod 256)

      let candidates = detectFormats("synthetic.SNA", snapshot)
      check candidates.len == 1
      check candidates[0].typeId == ZxSpectrumSnapshotTypeId
      check candidates[0].confidence == vdcProbable
      check candidates[0].evidence.len == 2

      let screen = extractZxSpectrumSnapshotScreen(snapshot)
      check screen.len == ZxSpectrumScreenSize
      for index, value in screen:
        check value == byte(index mod 256)

  test "listing snapshot exposes a non-animated indexed image":
    let
      snapshot = readBytes(
        "tests/fixtures/zx-spectrum.snapshot/colours-listing.sna")
      screen = readBytes(
        "tests/fixtures/zx-spectrum.screen/colours-listing.scr")
      raster = decodeScreenResource(ZxSpectrumSnapshotTypeId, snapshot)
    check extractZxSpectrumSnapshotScreen(snapshot) == screen
    check raster.kind == vrkIndexedImage
    check raster.image.width == 256
    check raster.image.height == 192
