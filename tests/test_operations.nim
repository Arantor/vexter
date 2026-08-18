import std/unittest
import vexterlib

suite "vexterlib operations":
  test "inspection returns a decoded resource tree":
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))

    check inspection.selectedFormat.typeId == ZxSpectrumScreenDumpTypeId
    check inspection.candidates.len == 1
    check inspection.resources.roots.len == 1
    let resources = inspection.resources.rasterResources
    check resources.len == 1
    check resources[0].path == ZxSpectrumScreenResourcePath
    check resources[0].typeId == ZxSpectrumScreenTypeId
    check resources[0].raster.kind == vrkIndexedImage

  test "forced formats are validated by the library":
    expect ValueError:
      discard inspectSource("short.scr", newSeq[byte](1),
        ZxSpectrumScreenDumpTypeId)
    expect ValueError:
      discard inspectSource("unknown.bin", newSeq[byte](1), "unknown")

  test "export selects resources and chooses a natural output format":
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "display"))

    check exported.resourcePath == ZxSpectrumScreenResourcePath
    check exported.outputFormat == "png"
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].suggestedFilename == "display.png"
    expect ValueError:
      discard exportResource(inspection.resources,
        VextExportRequest(resourcePath: "/missing"))

  test "GIF-capable indexed rasters also export as APNG without changing defaults":
    var screen = newSeq[byte](ZxSpectrumScreenSize)
    screen[6144] = 0x80 # FLASH makes the natural raster an indexed animation.
    let inspection = inspectSource("flash.scr", screen)
    let defaultExport = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "flash"))
    let apngExport = exportResource(inspection.resources,
      VextExportRequest(outputFormat: "apng", suggestedName: "flash"))
    check defaultExport.outputFormat == "gif"
    check defaultExport.artifacts.artifacts[0].mediaType == "image/gif"
    check apngExport.outputFormat == "apng"
    check apngExport.artifacts.artifacts[0].mediaType == "image/apng"
    let parsed = parsePng(apngExport.artifacts.artifacts[0].data)
    var animationControl = false
    for chunk in parsed.chunks:
      if chunk.kind == "acTL": animationControl = true
    check animationControl
    let decoded = decodePng(parsed).trueColourImage
    let natural = inspection.resources.rasterResources[0].raster.animation.
      frames[0].image
    check decoded.width == natural.width
    check decoded.height == natural.height
    check decoded.colourAt(0, 0) == natural.colourAt(0, 0)

  test "indexed APNG permits frame palettes to differ and preserves alpha":
    let animation = VextIndexedAnimation(width: 1, height: 1, frames: @[
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 1, height: 1,
        palette: @[VextRgb(r: 255, g: 0, b: 0)], pixels: @[0'u8],
        alpha: @[128'u8]), durationMs: 10),
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 1, height: 1,
        palette: @[VextRgb(r: 0, g: 0, b: 255)], pixels: @[0'u8]),
        durationMs: 20)])
    let artifact = exportApng(animation).artifacts[0]
    let first = decodePng(parsePng(artifact.data)).trueColourImage
    check first.rgbaAt(0, 0) == VextRgba(r: 255, g: 0, b: 0, a: 128)
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/animation",
      typeId: "test.animation", kind: vrnkRaster,
      raster: VextRaster(kind: vrkIndexedAnimation, animation: animation))])
    let natural = exportResource(tree, VextExportRequest(suggestedName: "test"))
    check natural.outputFormat == "apng"
    check natural.artifacts.artifacts[0].mediaType == "image/apng"

  test "resource traversal preserves tree order and exact lookup":
    let raster = decodeZxSpectrumScreen(newSeq[byte](ZxSpectrumScreenSize))
    let tree = VextResourceTree(roots: @[VextResourceNode(
      path: "/screens",
      kind: vrnkGroup,
      children: @[
        VextResourceNode(path: "/screens/1", typeId: ZxSpectrumScreenTypeId,
          kind: vrnkRaster, raster: raster),
        VextResourceNode(path: "/screens/2", typeId: ZxSpectrumScreenTypeId,
          kind: vrnkRaster, raster: raster)
      ])])

    check tree.rasterResources.len == 2
    check tree.rasterResources[0].path == "/screens/1"
    check tree.rasterResources[1].path == "/screens/2"
    check tree.findRasterResource("/screens/2").path == "/screens/2"
    check tree.findRasterResource("/screens").isNil
