import std/unittest
import vexterlib

proc putWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)

proc header(width, height, bits, planes, bytesPerLine: int): seq[byte] =
  result = newSeq[byte](128)
  result[0] = 0x0a
  result[1] = 5
  result[2] = 1
  result[3] = byte(bits)
  result.putWord(8, width - 1)
  result.putWord(10, height - 1)
  result.putWord(12, 72)
  result.putWord(14, 72)
  result[65] = byte(planes)
  result.putWord(66, bytesPerLine)
  result.putWord(68, 1)

suite "PCX images":
  test "one-bit planar pixels use the header palette and ignore row padding":
    var data = header(3, 1, 1, 2, 2)
    data[16 + 3] = 255
    data[16 + 7] = 255
    data[16 + 11] = 255
    data.add @[0x40'u8, 0, 0x20, 0]
    let inspection = inspectSource("planes.PCX", data)
    let image = inspection.resources.rasterResources[0].raster.image
    check inspection.selectedFormat.typeId == PcxTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    check image.width == 3
    check image.palette.len == 4
    check image.pixelAt(0, 0) == 0
    check image.pixelAt(1, 0) == 1
    check image.pixelAt(2, 0) == 2

  test "eight-bit indexed pixels use the trailing palette":
    var data = header(2, 1, 8, 1, 2)
    data.add @[1'u8, 2, 0x0c]
    var palette = newSeq[byte](768)
    palette[3] = 10; palette[4] = 20; palette[5] = 30
    palette[6] = 40; palette[7] = 50; palette[8] = 60
    data.add palette
    let image = decodePcx(parsePcx(data)).image
    check image.colourAt(0, 0) == VextRgb(r: 10, g: 20, b: 30)
    check image.colourAt(1, 0) == VextRgb(r: 40, g: 50, b: 60)

  test "three-plane PCX produces true colour in either channel order":
    var data = header(2, 1, 8, 3, 2)
    data.add @[10'u8, 11, 20, 21, 30, 31]
    let source = parsePcx(data)
    let rgb = decodePcx(source).trueColourImage
    let bgr = decodePcx(source, pcoBgr).trueColourImage
    check rgb.colourAt(0, 0) == VextRgb(r: 10, g: 20, b: 30)
    check bgr.colourAt(0, 0) == VextRgb(r: 30, g: 20, b: 10)

  test "RLE expands within a scanline and malformed data is rejected":
    var data = header(4, 1, 8, 1, 4)
    data.add @[0xc4'u8, 7, 0x0c]
    data.add newSeq[byte](768)
    check decodePcx(parsePcx(data)).image.pixels == @[7'u8, 7, 7, 7]

    var crossing = header(2, 2, 8, 1, 2)
    crossing.add @[0xc4'u8, 1, 0x0c]
    crossing.add newSeq[byte](768)
    expect ValueError:
      discard decodePcx(parsePcx(crossing))

    var missingPalette = header(2, 1, 8, 1, 2)
    missingPalette.add @[1'u8, 2]
    expect ValueError:
      discard decodePcx(parsePcx(missingPalette))
