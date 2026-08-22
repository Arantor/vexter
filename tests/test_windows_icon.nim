import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)

proc addDword(data: var seq[byte], value: int) =
  data.add byte(value)
  data.add byte(value shr 8)
  data.add byte(value shr 16)
  data.add byte(value shr 24)

proc dib32(): seq[byte] =
  result.addDword(40)
  result.addDword(2)
  result.addDword(4) # XOR height plus equally tall AND mask
  result.addWord(1)
  result.addWord(32)
  result.addDword(0)
  result.addDword(16)
  result.addDword(0); result.addDword(0); result.addDword(0); result.addDword(0)
  # Bottom row, then top row. BGRA alpha is meaningful.
  result.add @[0'u8, 0, 255, 255, 0, 255, 0, 128,
    255, 0, 0, 255, 255, 255, 255, 255]
  # Bottom AND row masks its second pixel; top row is unmasked.
  result.add @[0x40'u8, 0, 0, 0, 0, 0, 0, 0]

proc container(kind: int, entries: seq[tuple[width, height, first, second: int,
    payload: seq[byte]]]): seq[byte] =
  result.addWord(0)
  result.addWord(kind)
  result.addWord(entries.len)
  var dataOffset = 6 + entries.len * 16
  for entry in entries:
    result.add byte(if entry.width == 256: 0 else: entry.width)
    result.add byte(if entry.height == 256: 0 else: entry.height)
    result.add 0; result.add 0
    result.addWord(entry.first); result.addWord(entry.second)
    result.addDword(entry.payload.len); result.addDword(dataOffset)
    dataOffset += entry.payload.len
  for entry in entries: result.add entry.payload

suite "Windows ICO and CUR containers":
  test "ICO DIB height, BGRA alpha, and AND mask are composed explicitly":
    let data = container(1, @[(2, 2, 1, 32, dib32())])
    let inspection = inspectSource("layered.ico", data)
    check inspection.selectedFormat.typeId == WindowsIcoTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.findRasterResource("/icon/0")
    check resource != nil
    check resource.raster.width == 2
    check resource.raster.height == 2
    let image = resource.raster.trueColourImage
    check image.rgbaAt(0, 0) == VextRgba(r: 0, g: 0, b: 255, a: 255)
    check image.rgbaAt(1, 0) == VextRgba(r: 255, g: 255, b: 255, a: 255)
    check image.rgbaAt(0, 1) == VextRgba(r: 255, g: 0, b: 0, a: 255)
    check image.rgbaAt(1, 1) == VextRgba(r: 0, g: 255, b: 0, a: 0)

  test "mixed PNG and DIB entries retain their independent dimensions":
    let png = exportPng(VextTrueColourImage(width: 1, height: 1,
      pixels: @[VextRgb(r: 9, g: 8, b: 7)])).artifacts[0].data
    let data = container(1, @[(256, 256, 1, 32, png),
      (2, 2, 1, 32, dib32())])
    let inspection = inspectSource("mixed.ico", data)
    let rasters = inspection.resources.rasterResources
    check rasters.len == 2
    check rasters[0].raster.width == 1 # directory size is metadata, not truth
    check rasters[1].raster.width == 2
    check rasters[0].metadata[5].value.stringValue == "png"

  test "CUR hotspots and unsupported entry encodings remain inspectable":
    let data = container(2, @[(16, 16, 3, 7, @[1'u8, 2, 3, 4])])
    let inspection = inspectSource("pointer.cur", data)
    check inspection.selectedFormat.typeId == WindowsCurTypeId
    let resource = inspection.resources.leafResources[0]
    check resource.kind == vrnkOpaque
    check resource.rawDataAvailable
    check resource.metadata[6].key == "hotspot.x"
    check resource.metadata[6].value.integerValue == 3
    check resource.metadata[7].value.integerValue == 7

  test "bad directory bounds and odd DIB heights are not decoded as images":
    var truncated = container(1, @[(1, 1, 1, 32, dib32())])
    truncated.setLen(truncated.len - 1)
    expect ValueError: discard parseWindowsIcon(truncated)

    var odd = dib32()
    odd[8] = 3
    let parsed = parseWindowsIcon(container(1, @[(2, 2, 1, 32, odd)]))
    check parsed.entries[0].encoding == wieUnknown
