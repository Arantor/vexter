import std/unittest
import vexterlib

proc word(data: var seq[byte], value: int) =
  data.add byte(value); data.add byte(value shr 8)

proc dword(data: var seq[byte], value: uint32) =
  data.add byte(value); data.add byte(value shr 8)
  data.add byte(value shr 16); data.add byte(value shr 24)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

proc bytes(value: string): seq[byte] =
  for character in value: result.add byte(character)

type Entry = tuple[name: string, data: seq[byte]]

proc storedZip(entries: openArray[Entry]): seq[byte] =
  var central: seq[byte]
  for entry in entries:
    let localOffset = result.len
    let checksum = crc32(entry.data)
    result.dword(0x04034b50'u32)
    result.word(20); result.word(0x800); result.word(0)
    result.word(0); result.word(0); result.dword(checksum)
    result.dword(uint32(entry.data.len)); result.dword(uint32(entry.data.len))
    result.word(entry.name.len); result.word(0)
    for value in entry.name: result.add byte(value)
    result.add entry.data
    central.dword(0x02014b50'u32)
    central.word(20); central.word(20); central.word(0x800); central.word(0)
    central.word(0); central.word(0); central.dword(checksum)
    central.dword(uint32(entry.data.len)); central.dword(uint32(entry.data.len))
    central.word(entry.name.len); central.word(0); central.word(0)
    central.word(0); central.word(0); central.dword(0)
    central.dword(uint32(localOffset))
    for value in entry.name: central.add byte(value)
  let centralOffset = result.len
  result.add central
  result.dword(0x06054b50'u32)
  result.word(0); result.word(0); result.word(entries.len); result.word(entries.len)
  result.dword(uint32(central.len)); result.dword(uint32(centralOffset))
  result.word(0)

proc imagePng(width = 2, height = 1): seq[byte] =
  let image = VextTrueColourImage(width: width, height: height,
    pixels: newSeq[VextRgb](width * height))
  exportPng(image).artifacts[0].data

proc openRasterFixture(markerFirst = true, includeStack = true): seq[byte] =
  let png = imagePng()
  let thumbnail = imagePng(1, 1)
  let stack = "<image version=\"0.0.6\" w=\"2\" h=\"1\" xres=\"72\" " &
    "yres=\"72\"><stack name=\"root\" isolation=\"isolate\">" &
    "<layer name=\"Top\" src=\"data/layer0.png\" x=\"1\" " &
    "opacity=\"0.5\" visibility=\"visible\" selected=\"true\" " &
    "composite-op=\"svg:multiply\"/></stack></image>"
  var entries: seq[Entry]
  if not markerFirst: entries.add ("ordinary.txt", "x".bytes)
  entries.add ("mimetype", OpenRasterMimeType.bytes)
  if includeStack: entries.add ("stack.xml", stack.bytes)
  entries.add ("data/layer0.png", png)
  entries.add ("Thumbnails/thumbnail.png", thumbnail)
  entries.add ("mergedimage.png", png)
  storedZip(entries)

suite "OpenRaster packages":
  test "ZIP refinement exposes canonical, thumbnail, and layer rasters":
    let data = openRasterFixture()
    let candidates = detectFormats("painting.bin", data)
    check candidates.len == 2
    check candidates[0].typeId == OpenRasterTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].derivation.stages.len == 2
    check candidates[0].derivation.stages[0].typeId == ZipArchiveTypeId
    check candidates[1].typeId == ZipArchiveTypeId

    let inspection = inspectSource("painting.bin", data)
    check inspection.selectedFormat.typeId == OpenRasterTypeId
    check inspection.resources.roots.len == 3
    check inspection.resources.findRasterResource("/image").raster.width == 2
    check inspection.resources.findRasterResource("/thumbnail").raster.width == 1
    let layer = inspection.resources.findRasterResource("/layers/0")
    check not layer.isNil
    check layer.typeId == OpenRasterLayerTypeId
    check layer.raster.width == 2

  test "forcing ZIP preserves generic carrier inspection":
    let data = openRasterFixture()
    let generic = inspectSource("painting.ora", data, ZipArchiveTypeId)
    check generic.selectedFormat.typeId == ZipArchiveTypeId
    check generic.selectedFormat.derivation.stages.len == 1
    check generic.resources.roots[0].path == "/archive"
    let semantic = inspectSource("painting.zip", data, OpenRasterTypeId)
    check semantic.selectedFormat.typeId == OpenRasterTypeId

  test "physical MIME placement and required members are validated":
    let reordered = openRasterFixture(markerFirst = false)
    check detectFormats("painting.ora", reordered)[0].typeId == ZipArchiveTypeId
    expect ValueError:
      discard inspectSource("painting.ora", reordered, OpenRasterTypeId)
    expect ValueError:
      discard detectFormats("painting.ora", openRasterFixture(includeStack = false))
