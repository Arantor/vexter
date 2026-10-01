import std/unittest
import vexterlib

proc bytes(value: string): seq[byte] =
  for character in value: result.add byte(character)

suite "JASC palettes":
  test "version 0100 RGB entries decode in declared order":
    let data = bytes("JASC-PAL\r\n0100\r\n3\r\n" &
      "0 36 73\r\n109 146 182\r\n255 219 0\r\n")
    let inspection = inspectSource("colours.PAL", data)
    check inspection.selectedFormat.typeId == JascPaletteTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == JascPaletteResourcePath
    check resource.palette.colours == @[
      VextRgba(r: 0, g: 36, b: 73, a: 255),
      VextRgba(r: 109, g: 146, b: 182, a: 255),
      VextRgba(r: 255, g: 219, b: 0, a: 255)]
    check resource.defaultExportFormat == "palette-swatch"

  test "magic detection does not require the PAL extension":
    let data = bytes("JASC-PAL\n0100\n1\n1 2 3\n")
    check detectFormats("colours.bin", data)[0].typeId == JascPaletteTypeId

  test "version, count, components, and trailing data are validated":
    for invalid in [
        "JASC-PAL\n0200\n1\n1 2 3\n",
        "JASC-PAL\n0100\n0\n",
        "JASC-PAL\n0100\n2\n1 2 3\n",
        "JASC-PAL\n0100\n1\n1 2\n",
        "JASC-PAL\n0100\n1\n1 2 256\n",
        "JASC-PAL\n0100\n1\n1 2 3\nextra\n"]:
      check not isJascPalette(bytes(invalid))
