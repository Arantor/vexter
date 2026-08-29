import std/[sequtils, strutils, unittest]
import vexterlib

proc asString(data: openArray[byte]): string =
  for value in data: result.add char(value)

suite "GIMP Palette export":
  test "opaque palettes use standard GPL and round-trip exactly":
    let palette = VextPalette(colours: @[
      VextRgba(r: 1, g: 2, b: 3, a: 255),
      VextRgba(r: 254, g: 128, b: 0, a: 255)])
    let artifact = exportGpl(palette, "Example", "example.gpl").artifacts[0]
    let contents = artifact.data.asString
    check artifact.suggestedFilename == "example.gpl"
    check artifact.mediaType == "application/x-gimp-palette"
    check contents == "GIMP Palette\nName: Example\n1\t2\t3\n254\t128\t0\n"
    check "Channels:" notin contents
    check parseGimpPalette(artifact.data).palette == palette

  test "any alpha selects Aseprite RGBA GPL and round-trips alpha":
    let palette = VextPalette(colours: @[
      VextRgba(r: 10, g: 20, b: 30, a: 40),
      VextRgba(r: 50, g: 60, b: 70, a: 255)])
    let tree = VextResourceTree(roots: @[VextResourceNode(
      path: "/palette", kind: vrnkPalette, palette: palette)])
    let resource = tree.roots[0]
    check resource.gplExportUsesAlpha
    check resource.exportFormatsFor.anyIt(it.id == "gpl")
    let exported = exportResource(tree, VextExportRequest(
      resourcePath: "/palette", outputFormat: "gpl",
      suggestedName: "Alpha palette"))
    let artifact = exported.artifacts.artifacts[0]
    check artifact.data.asString.startsWith(
      "GIMP Palette\nName: Alpha palette\nChannels: RGBA\n")
    check parseGimpPalette(artifact.data).palette == palette

  test "indexed rasters offer opaque GPL palette export":
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/image",
      kind: vrnkRaster, raster: VextRaster(kind: vrkIndexedImage,
        image: VextIndexedImage(width: 1, height: 1,
          palette: @[VextRgb(r: 1, g: 2, b: 3)], pixels: @[0'u8],
          alpha: @[0'u8])))])
    check not tree.roots[0].gplExportUsesAlpha
    let exported = exportResource(tree, VextExportRequest(
      outputFormat: "gpl", suggestedName: "indexed"))
    check "Channels:" notin exported.artifacts.artifacts[0].data.asString
