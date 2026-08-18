import std/unittest
import vexterlib

proc addLong(data: var seq[byte], value: int) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.addLong(payload.len)
  result.add payload
  if payload.len mod 2 != 0: result.add 0'u8

proc form(formType: string, chunks: openArray[seq[byte]]): seq[byte] =
  for value in "FORM": result.add byte(value)
  var payload: seq[byte]
  for value in formType: payload.add byte(value)
  for value in chunks: payload.add value
  result.addLong(payload.len)
  result.add payload

proc bmhd(compression = 0): seq[byte] =
  @[0'u8, 16, 0, 2, 0, 0, 0, 0, 2, 0, byte(compression), 0,
    0, 0, 10, 11, 0, 16, 0, 2]

proc palette(): seq[byte] =
  @[0'u8, 0, 0, 0xf0, 0, 0, 0, 0xf0, 0, 0, 0, 0xf0]

suite "Amiga IFF ACBM":
  test "ABIT stores complete planes contiguously":
    # Two rows from plane zero, followed by two rows from plane one.
    let data = form("ACBM", [
      chunk("BMHD", bmhd()),
      chunk("CMAP", palette()),
      chunk("ABIT", @[
        0x80'u8, 0, 0x40, 0,
        0x20, 0, 0x10, 0])])
    let
      parsed = parseAmigaAcbm(data)
      candidates = detectFormats("planes.acbm", data)
      resource = inspectSource("planes.acbm", data).resources.rasterResources[0]
      image = resource.raster.image
    check parsed.image.planarLayout == aplPlaneContiguous
    check candidates.len == 1
    check candidates[0].typeId == AmigaAcbmTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check resource.path == AmigaIlbmImageResourcePath
    check image.width == 16
    check image.height == 2
    check image.pixelAt(0, 0) == 1
    check image.pixelAt(2, 0) == 2
    check image.pixelAt(1, 1) == 1
    check image.pixelAt(3, 1) == 2

  test "ByteRun1 is bounded per row within each contiguous plane":
    let data = form("ACBM", [
      chunk("BMHD", bmhd(compression = 1)),
      chunk("CMAP", palette()),
      chunk("ABIT", @[
        1'u8, 0x80, 0, 1, 0x40, 0,
        1, 0x20, 0, 1, 0x10, 0])])
    let image = decodeAmigaIlbmImage(parseAmigaAcbm(data).image)
    check image.pixelAt(0, 0) == 1
    check image.pixelAt(2, 0) == 2
    check image.pixelAt(1, 1) == 1
    check image.pixelAt(3, 1) == 2

  test "ACBM requires one ABIT after BMHD and exact image data":
    let bodyInstead = form("ACBM", [
      chunk("BMHD", bmhd()),
      chunk("BODY", newSeq[byte](8))])
    check not isAmigaAcbm(bodyInstead)

    let trailing = form("ACBM", [
      chunk("BMHD", bmhd()),
      chunk("CMAP", palette()),
      chunk("ABIT", newSeq[byte](10))])
    expect ValueError:
      discard inspectSource("trailing.acbm", trailing)
