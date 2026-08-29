import std/unittest
import vexterlib

proc bytes(value: string): seq[byte] =
  for character in value: result.add byte(character)

proc metadataValue(resource: VextResourceNode, key: string): VextMetadataValue =
  for entry in resource.metadata:
    if entry.key == key: return entry.value

suite "GIMP palettes":
  test "version 2 header and colour names inspect as an ordered palette":
    let inspection = inspectSource("example.gpl", bytes(
      "GIMP Palette\nName:  Example palette  \nColumns: 4\n" &
      "# ignored\n46\t34 47 2e222f\n255 128 0 orange\n"))
    check inspection.selectedFormat.typeId == GimpPaletteTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == GimpPaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 46, g: 34, b: 47, a: 255),
      VextRgba(r: 255, g: 128, b: 0, a: 255)]
    check resource.metadataValue("name").stringValue == "Example palette"
    check resource.metadataValue("version").integerValue == 2
    check resource.metadataValue("columns").integerValue == 4
    check resource.defaultExportFormat == "palette-swatch"

  test "old format is inferred as version 1":
    let resource = inspectSource("old.gpl", bytes(
      "GIMP Palette\n# old palette\n1 2 3\n")).resources.roots[0]
    check resource.metadataValue("version").integerValue == 1
    check resource.metadataValue("columns").integerValue == 0
    check resource.palette.colours[0] == VextRgba(r: 1, g: 2, b: 3, a: 255)

  test "Aseprite RGBA variant preserves alpha and marks compatibility":
    let resource = inspectSource("aseprite.gpl", bytes(
      "GIMP Palette\nName: Alpha palette\nChannels: RGBA\nColumns: 2\n" &
      "10 20 30 40 translucent name\n50 60 70 255 opaque\n"
    )).resources.roots[0]
    check resource.palette.colours == @[
      VextRgba(r: 10, g: 20, b: 30, a: 40),
      VextRgba(r: 50, g: 60, b: 70, a: 255)]
    check resource.metadataValue("variant").stringValue == "aseprite-rgba"
    check resource.metadataValue("channels").stringValue == "RGBA"
    check resource.metadataValue("version").integerValue == 2
    check resource.metadataValue("columns").integerValue == 2

  test "Aseprite marker may immediately follow magic without a name":
    let source = parseGimpPalette(bytes(
      "GIMP Palette\nChannels: RGBA\n1 2 3 4 colour\n"))
    check source.version == 1
    check source.hasAlpha
    check source.palette.colours[0].a == 4

  test "ordinary GIMP palettes discard a fourth value":
    let source = parseGimpPalette(bytes(
      "GIMP Palette\nName: RGB palette\n1 2 3 4 ignored as a name\n"))
    check not source.hasAlpha
    check source.palette.colours[0] == VextRgba(r: 1, g: 2, b: 3, a: 255)

  test "malformed headers and colour records are rejected":
    expect ValueError:
      discard parseGimpPalette(bytes("Not GIMP\n1 2 3\n"))
    expect ValueError:
      discard parseGimpPalette(bytes("GIMP Palette\nName: Example\nColumns: 256\n1 2 3\n"))
    expect ValueError:
      discard parseGimpPalette(bytes("GIMP Palette\n1 2\n"))
    expect ValueError:
      discard parseGimpPalette(bytes("GIMP Palette\n-1 2 3\n"))
    expect ValueError:
      discard parseGimpPalette(bytes("GIMP Palette\n1 2 300\n"))
    expect ValueError:
      discard parseGimpPalette(bytes("GIMP Palette\nChannels: RGBA\n1 2 3\n"))
