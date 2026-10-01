import std/unittest
import vexterlib

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

suite "ZX Spectrum Next palettes":
  test "RGB332 synthesizes the low blue bit":
    var data = newSeq[byte](ZxSpectrumNextRgb332Size)
    data[0] = 0b00000000
    data[1] = 0b00100101
    data[2] = 0b01001010
    data[3] = 0b11111111
    let source = parseZxSpectrumNextPalette(data)
    check source.bitsPerColour == 8
    check source.palette.colours[0] == VextRgba(r: 0, g: 0, b: 0, a: 255)
    check source.palette.colours[1] == VextRgba(r: 0x24, g: 0x24,
      b: 0x6d, a: 255)
    check source.palette.colours[2] == VextRgba(r: 0x49, g: 0x49,
      b: 0xb6, a: 255)
    check source.palette.colours[3] == VextRgba(r: 0xff, g: 0xff,
      b: 0xff, a: 255)

  test "RGB333 takes the low blue bit from the second byte":
    var data = newSeq[byte](ZxSpectrumNextRgb333Size)
    data[0] = 0b11111110
    data[1] = 0
    data[2] = 0b11111110
    data[3] = 1
    let source = parseZxSpectrumNextPalette(data)
    check source.bitsPerColour == 9
    check source.palette.colours[0].b == 0x92
    check source.palette.colours[1].b == 0xb6
    data[3] = 2
    expect ValueError:
      discard parseZxSpectrumNextPalette(data)

  test "32-byte RGB333 palettes contain 16 colours":
    var data = newSeq[byte](ZxSpectrumNextRgb333SmallSize)
    for index in 0 ..< ZxSpectrumNextSmallPaletteColours:
      data[index * 2] = byte(index shl 4)
      data[index * 2 + 1] = byte(index and 1)
    let source = parseZxSpectrumNextPalette(data)
    check source.bitsPerColour == 9
    check source.palette.colours.len == 16
    check source.palette.colours[1] ==
      VextRgba(r: 0, g: 0x92, b: 0x24, a: 255)
    let inspection = inspectSource("small.nxp", data)
    check inspection.selectedFormat.typeId == ZxSpectrumNextPaletteTypeId
    check inspection.resources.roots[0].metadata[0].value.integerValue == 16

  test ".nxp detection exposes the generic palette resource":
    let inspection = inspectSource("dm.NXP", readBytes("specnext/dm.nxp"))
    check inspection.selectedFormat.typeId == ZxSpectrumNextPaletteTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    let resource = inspection.resources.roots[0]
    check resource.path == ZxSpectrumNextPaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours.len == 256
    check resource.metadata[1].value.integerValue == 9
    check resource.defaultExportFormat == "palette-swatch"

  test "size, extension, and RGB333 low bytes are validated":
    check not isZxSpectrumNextPalette(newSeq[byte](255))
    check not isZxSpectrumNextPalette(newSeq[byte](31))
    check not isZxSpectrumNextPalette(newSeq[byte](33))
    check not isZxSpectrumNextPalette(newSeq[byte](511))
    check detectFormats("palette.bin", newSeq[byte](256)).len == 0
    check detectFormats("palette.pal", newSeq[byte](256))[0].confidence ==
      vdcPossible
    let forced = inspectSource("palette.bin", newSeq[byte](256),
      inputFormat = ZxSpectrumNextPaletteTypeId)
    check forced.resources.roots[0].palette.colours.len == 256
