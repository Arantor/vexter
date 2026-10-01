import std/unittest
import vexterlib

proc plus3DosSl2(): seq[byte] =
  result = newSeq[byte](ZxSpectrumNextSmallPlus3DosSize)
  for index, value in Plus3DosSignature: result[index] = byte(value)
  result[8] = Plus3DosSoftEof
  result[9] = 1
  result[10] = 0
  let total = uint32(result.len)
  for index in 0 .. 3: result[11 + index] = byte(total shr (index * 8))
  result[15] = 3
  result[16] = 0
  result[17] = 0xc0
  result[18] = 0
  result[19] = 0x40
  var checksum = 0
  for index in 0 .. 126: checksum = (checksum + int(result[index])) and 0xff
  result[127] = byte(checksum)

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

  test "49280-byte SL2 images validate and strip a +3DOS header":
    var data = plus3DosSl2()
    data[Plus3DosHeaderSize] = 4
    data[Plus3DosHeaderSize + 1] = 5
    data[Plus3DosHeaderSize + 256] = 6
    let inspection = inspectSource("headered.sl2", data)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 256
    check image.height == 192
    check image.pixelAt(0, 0) == 4
    check image.pixelAt(1, 0) == 5
    check image.pixelAt(0, 1) == 6
    check inspection.selectedFormat.evidence.len == 3
    check inspection.resources.roots[0].metadata[5].key == "plus3dos.issue"
    check inspection.resources.roots[0].metadata[5].value.integerValue == 1
    check inspection.resources.roots[0].metadata[7].value.integerValue ==
      ZxSpectrumNextSmallPlus3DosSize

  test "+3DOS signature, length, reserved bytes, and checksum are required":
    let valid = plus3DosSl2()
    check isPlus3DosHeader(valid)
    check parsePlus3DosHeader(valid).basicType == 3
    for damagedOffset in [0, 8, 11, 23, 127]:
      var damaged = valid
      damaged[damagedOffset] = damaged[damagedOffset] xor 1
      check not isPlus3DosHeader(damaged)
      check detectFormats("damaged.sl2", damaged).len == 0

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

  test "matching 256-colour companion selects 320x256 decoding":
    var paletteData = newSeq[byte](ZxSpectrumNextRgb333Size)
    for index in 0 ..< ZxSpectrumNextFullPaletteColours:
      paletteData[index * 2] = byte(index)
      paletteData[index * 2 + 1] = byte(index and 1)
    let resolver: VextCompanionResolver = proc(path: string): seq[byte] =
      check path == "image.nxp"
      paletteData
    let inspection = inspectSource("image.nxi",
      newSeq[byte](ZxSpectrumNextImageSize),
      companionResolver = resolver)
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 320
    check image.height == 256
    check image.palette.len == 256
    check inspection.resources.roots[0].metadata[3].value.stringValue ==
      "image.nxp"

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
    check detectFormats("headered.sl2", plus3DosSl2())[0].typeId ==
      ZxSpectrumNextImageTypeId
    check detectFormats("large.sl2", data).len == 0
    let forced = inspectSource("layer.bin", data,
      inputFormat = ZxSpectrumNextImageTypeId)
    check forced.resources.rasterResources[0].raster.image.width == 320
