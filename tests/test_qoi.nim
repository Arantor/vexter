import std/unittest
import vexterlib

proc putDword(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc qoi(width, height, channels, colourSpace: int,
    chunks: openArray[byte]): seq[byte] =
  result = @QoiMagic
  result.putDword(uint32(width))
  result.putDword(uint32(height))
  result.add byte(channels)
  result.add byte(colourSpace)
  result.add chunks
  result.add QoiEndMarker

suite "QOI images":
  test "every QOI opcode decodes with index, wraparound, run, and alpha semantics":
    let data = qoi(7, 1, 4, 0, @[
      0xfe'u8, 10, 20, 30,       # RGB
      0x76,                       # DIFF: +1, -1, 0
      0xa5, 0x6b,                 # LUMA: dg +5, dr-dg -2, db-dg +3
      0xff, 1, 2, 3, 4,           # RGBA
      0x09,                       # INDEX: first RGB pixel
      0xc1])                      # RUN: two copies
    let inspection = inspectSource("opcodes.qoi", data)
    check inspection.selectedFormat.typeId == QoiTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.resources.roots[0].path == QoiImageResourcePath
    check inspection.resources.roots[0].typeId == QoiImageTypeId
    let image = inspection.resources.rasterResources[0].raster.trueColourImage
    check image.width == 7
    check image.height == 1
    check image.pixels == @[
      VextRgb(r: 10, g: 20, b: 30),
      VextRgb(r: 11, g: 19, b: 30),
      VextRgb(r: 14, g: 24, b: 38),
      VextRgb(r: 1, g: 2, b: 3),
      VextRgb(r: 10, g: 20, b: 30),
      VextRgb(r: 10, g: 20, b: 30),
      VextRgb(r: 10, g: 20, b: 30)]
    check image.alpha == @[255'u8, 255, 255, 4, 255, 255, 255]
    check inspection.resources.roots[0].defaultExportFormat == "png"
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "opcodes"))
    check exported.outputFormat == "png"
    check exported.artifacts.artifacts[0].mediaType == "image/png"
    let roundTrip = decodePng(parsePng(exported.artifacts.artifacts[0].data)).
      trueColourImage
    check roundTrip.pixels == image.pixels
    check roundTrip.alpha == image.alpha

  test "channel differences wrap modulo 256 and opaque images omit alpha":
    let source = parseQoi(qoi(2, 1, 3, 1, @[
      0xfe'u8, 0, 255, 1,
      0x49])) # DIFF: -2, 0, -1 -> 254, 255, 0
    let image = decodeQoi(source).trueColourImage
    check image.pixels[1] == VextRgb(r: 254, g: 255, b: 0)
    check image.alpha.len == 0
    check source.colourSpace == 1

  test "headers, chunks, pixel coverage, and exact end marker are validated":
    var badMagic = qoi(1, 1, 3, 0, @[0xc0'u8])
    badMagic[0] = byte('x')
    expect ValueError: discard parseQoi(badMagic)
    expect ValueError: discard parseQoi(qoi(0, 1, 3, 0, @[0xc0'u8]))
    expect ValueError: discard parseQoi(qoi(1, 1, 2, 0, @[0xc0'u8]))
    expect ValueError: discard parseQoi(qoi(1, 1, 3, 2, @[0xc0'u8]))
    expect ValueError: discard parseQoi(qoi(2, 1, 3, 0, @[0xc0'u8]))
    expect ValueError: discard parseQoi(qoi(1, 1, 3, 0, @[0xc1'u8]))
    expect ValueError: discard parseQoi(qoi(1, 1, 3, 0, @[0x80'u8]))
    expect ValueError: discard parseQoi(qoi(1, 1, 3, 0,
      @[0xc0'u8, 0xc0]))
    var badMarker = qoi(1, 1, 3, 0, @[0xc0'u8])
    badMarker[^1] = 0
    expect ValueError: discard parseQoi(badMarker)
