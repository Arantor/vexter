import std/unittest
import vexterlib

proc fixture(): seq[byte] =
  result = newSeq[byte](ZxSpectrumGigascreenSize)
  for index in 0 ..< 6144:
    result[index] = 0xff
  for index in 0 ..< 768:
    result[6144 + index] = 0x01 # normal blue ink
    result[6912 + index] = 0x42 # bright red ink

suite "ZX Gigascreen":
  test "type and resource identifiers are stable":
    check ZxSpectrumGigascreenTypeId == "zx-spectrum.gigascreen"
    check ZxSpectrumGigascreenResourcePath == "/screen"
    check ZxSpectrumGigascreenPaletteAPath == "/screen/palette-a"
    check ZxSpectrumGigascreenPaletteBPath == "/screen/palette-b"
    check ZxSpectrumGigascreenAveragedPath == "/screen/averaged"

  test "sample exposes both attribute sets and their pixel average":
    let
      source = fixture()
      candidates = detectFormats("sample.scr", source)
      decoded = decodeZxSpectrumGigascreen(source)
      inspection = inspectSource("sample.scr", source)
    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumGigascreenTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 3
    check decoded.paletteA.width == 256
    check decoded.paletteB.height == 192
    check decoded.averaged.pixels.len == 256 * 192
    check decoded.paletteA.colourAt(0, 0) == VextRgb(r: 0, g: 0, b: 205)
    check decoded.paletteB.colourAt(0, 0) == VextRgb(r: 255, g: 0, b: 0)
    check decoded.averaged.colourAt(0, 0) == VextRgb(r: 127, g: 0, b: 102)
    check decoded.averaged.colourAt(255, 191) ==
      VextRgb(r: 127, g: 0, b: 102)
    check inspection.resources.roots.len == 1
    check inspection.resources.roots[0].kind == vrnkGroup
    check inspection.resources.roots[0].children.len == 3
    check inspection.resources.findRasterResource(
      ZxSpectrumGigascreenAveragedPath).raster.kind == vrkTrueColourImage

  test "detection requires SCR extension and rejects DOS executables":
    let source = fixture()
    check detectFormats("image.bin", source).len == 0
    var executable = source
    executable[0] = byte('M')
    executable[1] = byte('Z')
    check detectFormats("image.scr", executable).len == 0
    expect ValueError:
      discard parseZxSpectrumGigascreen(executable)

  test "invalid byte lengths are rejected":
    expect ValueError:
      discard decodeZxSpectrumGigascreen(
        newSeq[byte](ZxSpectrumGigascreenSize - 1))
