import std/unittest
import vexterlib

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

suite "ZX Spectrum Next Layer 2 images":
  test "320x256 pixels are rotated from column-major storage":
    var data = newSeq[byte](ZxSpectrumNextImageSize)
    data[0] = 0x92
    data[1] = 7
    data[256] = 9
    let source = parseZxSpectrumNextImage(data)
    let image = decodeZxSpectrumNextImage(source,
      synthesizedZxSpectrumNextPalette())
    check image.width == 320
    check image.height == 256
    check image.pixelAt(0, 0) == 0x92
    check image.pixelAt(0, 1) == 7
    check image.pixelAt(1, 0) == 9
    check image.colourAt(0, 0) == VextRgb(r: 0x92, g: 0x92, b: 0xb6)

  test "16-colour companion selects 640x256 nibble decoding":
    var data = newSeq[byte](ZxSpectrumNextImageSize)
    data[0] = 0x12
    data[1] = 0x34
    data[256] = 0x56
    var paletteData = newSeq[byte](ZxSpectrumNextRgb333SmallSize)
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      check path == "wide.nxp"
      paletteData
    let inspection = inspectSource("wide.nxi", data,
      companionResolver = resolver)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 640
    check image.height == 256
    check image.pixelAt(0, 0) == 1
    check image.pixelAt(1, 0) == 2
    check image.pixelAt(0, 1) == 3
    check image.pixelAt(1, 1) == 4
    check image.pixelAt(2, 0) == 5
    check image.pixelAt(3, 0) == 6

  test "49152-byte images use 256x192 row-major storage":
    var data = newSeq[byte](ZxSpectrumNextSmallImageSize)
    data[0] = 4
    data[1] = 5
    data[256] = 6
    let inspection = inspectSource("small.nxi", data)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 256
    check image.height == 192
    check image.pixelAt(0, 0) == 4
    check image.pixelAt(1, 0) == 5
    check image.pixelAt(0, 1) == 6
    check inspection.resources.roots[0].metadata[4].value.stringValue ==
      "row-major"

  test "49152-byte SL2 images use row-major data without companion lookup":
    var data = newSeq[byte](ZxSpectrumNextSmallImageSize)
    data[0] = 4
    data[1] = 5
    data[256] = 6
    var companionRequested = false
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      companionRequested = true
      newSeq[byte](ZxSpectrumNextRgb333SmallSize)
    let inspection = inspectSource("small.SL2", data,
      companionResolver = resolver)
    let image = inspection.resources.rasterResources[0].raster.image
    check inspection.selectedFormat.typeId == ZxSpectrumNextImageTypeId
    check image.width == 256
    check image.height == 192
    check image.pixelAt(0, 0) == 4
    check image.pixelAt(1, 0) == 5
    check image.pixelAt(0, 1) == 6
    check image.palette.len == 256
    check not companionRequested
    check inspection.resources.roots[0].metadata[3].value.stringValue ==
      "synthesized RGB332"

  test "49664-byte images use their embedded RGB333 palette":
    var data = newSeq[byte](ZxSpectrumNextSmallEmbeddedPaletteSize)
    for index in 0 ..< ZxSpectrumNextFullPaletteColours:
      data[index * 2] = byte(index)
      data[index * 2 + 1] = byte(index and 1)
    data[ZxSpectrumNextEmbeddedPaletteSize] = 0x92
    data[ZxSpectrumNextEmbeddedPaletteSize + 1] = 7
    var companionRequested = false
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      companionRequested = true
      newSeq[byte](ZxSpectrumNextRgb333SmallSize)
    let inspection = inspectSource("embedded.nxi", data,
      companionResolver = resolver)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 256
    check image.height == 192
    check image.pixelAt(0, 0) == 0x92
    check image.pixelAt(1, 0) == 7
    check image.palette.len == 256
    check not companionRequested
    check inspection.resources.roots[0].metadata[3].value.stringValue ==
      "embedded RGB333"

  test "matching 256-colour companion decodes the supplied image":
    let paletteData = readBytes("specnext/dm.nxp")
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      check path == "dm.nxp"
      paletteData
    let inspection = inspectSource("dm.nxi", readBytes("specnext/dm.nxi"),
      companionResolver = resolver)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 320
    check image.height == 256
    check image.palette.len == 256
    check inspection.resources.roots[0].metadata[3].value.stringValue ==
      "dm.nxp"

  test "inspection sessions forward source-collection companions":
    let imageData = newSeq[byte](ZxSpectrumNextImageSize)
    let paletteData = newSeq[byte](ZxSpectrumNextRgb333SmallSize)
    let sourceResolver: VextCompanionSourceResolver =
      proc(path: string): VextByteSource =
        check path == "session.nxp"
        memoryByteSource(paletteData)
    let sources = newSourceCollection(memoryByteSource(imageData),
      sourceResolver)
    let session = openInspectionSession("session.nxi", sources)
    defer: session.close()
    check session.resourceTree.rasterResources[0].raster.image.width == 640

  test "missing or invalid companion falls back to synthesized RGB332":
    let missing: VextCompanionResolver = proc(path: string): seq[byte] = @[]
    let absent = inspectSource("plain.nxi",
      newSeq[byte](ZxSpectrumNextImageSize), companionResolver = missing)
    check absent.resources.rasterResources[0].raster.image.width == 320
    check absent.resources.roots[0].metadata[3].value.stringValue ==
      "synthesized RGB332"

    let invalid: VextCompanionResolver = proc(path: string): seq[byte] =
      @[1'u8, 2, 3]
    let recovered = inspectSource("plain.nxi",
      newSeq[byte](ZxSpectrumNextImageSize), companionResolver = invalid)
    check recovered.resources.rasterResources[0].raster.image.width == 320
    check recovered.warnings.len == 1

  test "automatic detection requires size and extension":
    let data = newSeq[byte](ZxSpectrumNextImageSize)
    let detected = detectFormats("layer.NXI", data)
    check detected[0].typeId == ZxSpectrumNextImageTypeId
    check detected[0].confidence == vdcProbable
    check detectFormats("layer.bin", data).len == 0
    check detectFormats("layer.nxi", newSeq[byte](data.len - 1)).len == 0
    check detectFormats("small.nxi",
      newSeq[byte](ZxSpectrumNextSmallImageSize))[0].typeId ==
      ZxSpectrumNextImageTypeId
    check detectFormats("small.sl2",
      newSeq[byte](ZxSpectrumNextSmallImageSize))[0].typeId ==
      ZxSpectrumNextImageTypeId
    check detectFormats("headered.sl2", newSeq[byte](49280)).len == 0
    check detectFormats("large.sl2", data).len == 0
    let forced = inspectSource("layer.bin", data,
      inputFormat = ZxSpectrumNextImageTypeId)
    check forced.resources.rasterResources[0].raster.image.width == 320
