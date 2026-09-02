import std/unittest
import vexterlib

suite "generic RGBA8 palettes":
  test ".pal files inspect as low-confidence palettes and export swatches":
    let data = @[2'u8, 0, 0, 0,
      0x10, 0x20, 0x30, 0x40,
      0xaa, 0xbb, 0xcc, 0xff]
    let inspection = inspectSource("colours.PAL", data)
    check inspection.selectedFormat.typeId == Rgba8PaletteTypeId
    check inspection.selectedFormat.confidence == vdcPossible
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == Rgba8PaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 0x10, g: 0x20, b: 0x30, a: 0x40),
      VextRgba(r: 0xaa, g: 0xbb, b: 0xcc, a: 0xff)]
    check resource.metadata[0].key == "colours"
    check resource.metadata[0].value.integerValue == 2
    check resource.defaultExportFormat == "palette-swatch"
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "colours"))
    check exported.outputFormat == "palette-swatch"
    check exported.artifacts.artifacts[0].mediaType == "image/png"

  test "automatic detection requires the .pal extension":
    let data = @[1'u8, 0, 0, 0, 1, 2, 3, 4]
    check detectFormats("colours.bin", data).len == 0
    let forced = inspectSource("colours.bin", data,
      inputFormat = Rgba8PaletteTypeId)
    check forced.resources.roots[0].palette.colours[0] ==
      VextRgba(r: 1, g: 2, b: 3, a: 4)

  test "count, exact size, and upper bound are validated":
    check not isRgba8Palette(@[0'u8, 0, 0, 0])
    check not isRgba8Palette(@[2'u8, 0, 0, 0, 1, 2, 3, 4])
    check not isRgba8Palette(@[1'u8, 0, 0, 0, 1, 2, 3, 4, 5])
    check not isRgba8Palette(@[1'u8, 0, 1, 0])
