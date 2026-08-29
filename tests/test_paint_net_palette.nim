import std/[json, unittest]
import vexterlib

proc bytes(value: string): seq[byte] =
  for character in value: result.add byte(character)

proc metadataValue(resource: VextResourceNode, key: string): string =
  for entry in resource.metadata:
    if entry.key == key and entry.value.kind == vmvkString:
      return entry.value.stringValue

proc hasMetadata(resource: VextResourceNode, key: string): bool =
  for entry in resource.metadata:
    if entry.key == key: return true

suite "Paint.NET palettes":
  test "magic, comments, mixed-case ARGB, and advisory count inspect as a palette":
    let data = bytes(";paint.net Palette File\r\n" &
      ";Downloaded from Lospec.com/palette-list\r\n" &
      ";Palette Name: Example\r\n" &
      ";Description: A small palette\r\n" &
      ";Colors: 99\r\n" &
      "8040a0Ff\r\n" &
      "FF010203\r\n")
    let inspection = inspectSource("example.txt", data)
    check inspection.selectedFormat.typeId == PaintNetPaletteTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == PaintNetPaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 0x40, g: 0xa0, b: 0xff, a: 0x80),
      VextRgba(r: 1, g: 2, b: 3, a: 0xff)]
    check resource.metadataValue("name") == "Example"
    check resource.metadataValue("description") == "A small palette"
    check resource.metadata[0].value.integerValue == 2
    check resource.metadata[1].value.integerValue == 99
    check resource.defaultExportFormat == "palette-swatch"

    let swatch = renderPaletteSwatch(resource.palette)
    check swatch.colourAt(8, 8) == VextRgb(r: 0x40, g: 0xa0, b: 0xff)
    check swatch.alphaAt(8, 8) == 0x80
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "example"))
    check exported.outputFormat == "palette-swatch"
    check exported.artifacts.artifacts[0].mediaType == "image/png"

    let metadata = exportResource(inspection.resources,
      VextExportRequest(outputFormat: "metadata-json",
        suggestedName: "example"))
    var jsonText = ""
    for value in metadata.artifacts.artifacts[0].data:
      jsonText.add char(value)
    let document = parseJson(jsonText)
    check document["resource"]["colours"][0]["a"].getInt == 0x80

  test "optional empty metadata and malformed advisory counts are omitted":
    let source = parsePaintNetPalette(bytes(";paint.net Palette File\n" &
      ";Palette Name:\n;Description:   \n;Colors: many\nFFabcdef\n"))
    check source.name.len == 0
    check source.description.len == 0
    check source.declaredColourCount == -1
    check source.palette.colours[0].a == 255
    let resource = inspectSource("palette", bytes(
      ";paint.net Palette File\n;Description:\nFFabcdef\n")).resources.roots[0]
    check not resource.hasMetadata("name")
    check not resource.hasMetadata("description")
    check not resource.hasMetadata("declared-colours")

  test "colours are required and malformed data is rejected":
    expect ValueError:
      discard parsePaintNetPalette(bytes(";not paint.net\nFFFFFFFF\n"))
    expect ValueError:
      discard parsePaintNetPalette(bytes(";paint.net Palette File\n"))
    expect ValueError:
      discard parsePaintNetPalette(bytes(
        ";paint.net Palette File\nFFFFFFF\n"))
    expect ValueError:
      discard parsePaintNetPalette(bytes(
        ";paint.net Palette File\nFFFFFFFG\n"))
    expect ValueError:
      discard parsePaintNetPalette(bytes(
        ";paint.net Palette File\nnot-a-comment\n"))
