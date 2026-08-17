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
