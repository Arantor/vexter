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
