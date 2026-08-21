import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value shr 8)
  data.add byte(value)

proc addDword(data: var seq[byte], value: int) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc chunk(id: string, payload: openArray[byte]): seq[byte] =
  for value in id: result.add byte(value)
  result.addDword(payload.len)
  result.add payload
  if payload.len mod 2 != 0: result.add 0

proc form(chunks: openArray[seq[byte]]): seq[byte] =
  for value in "FORM": result.add byte(value)
  var payload: seq[byte]
  for value in "PBM ": payload.add byte(value)
  for value in chunks: payload.add value
  result.addDword(payload.len)
  result.add payload

proc header(width, height, compression: int, masking = 0,
    transparent = 0, planes = 8): seq[byte] =
  result.addWord(width)
  result.addWord(height)
  result.addWord(0)
  result.addWord(0)
  result.add byte(planes)
  result.add byte(masking)
  result.add byte(compression)
  result.add 0
  result.addWord(transparent)
  result.add 1
  result.add 1
  result.addWord(width)
  result.addWord(height)

suite "IFF PBM images":
  test "raw chunky rows are word-aligned and palette indexed":
    let data = form(@[
      chunk("BMHD", header(3, 2, 0)),
      chunk("CMAP", @[0'u8, 0, 0, 10, 20, 30, 40, 50, 60]),
      chunk("BODY", @[1'u8, 2, 0, 0xaa, 2, 1, 2, 0xbb])])
    let inspection = inspectSource("chunky.lbm", data)
    check inspection.selectedFormat.typeId == AmigaPbmTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    let resource = inspection.resources.rasterResources[0]
    check resource.path == AmigaPbmImageResourcePath
    check resource.typeId == AmigaPbmImageTypeId
    check resource.raster.image.pixels == @[1'u8, 2, 0, 2, 1, 2]
    check resource.raster.image.palette[1] == VextRgb(r: 10, g: 20, b: 30)
    check resource.raster.image.palette.len == 256
    check resource.defaultExportFormat == "png"

  test "ByteRun1 is bounded per chunky row and transparency uses an index":
    let data = form(@[
      chunk("BMHD", header(3, 2, 1, masking = 2, transparent = 2)),
      chunk("CMAP", @[0'u8, 0, 0, 255, 0, 0, 0, 255, 0]),
      chunk("BODY", @[3'u8, 1, 2, 2, 0, 0xfd, 2])])
    let image = inspectSource("compressed.pbm", data).resources.
      rasterResources[0].raster.image
    check image.pixels == @[1'u8, 2, 2, 2, 2, 2]
    check image.alpha == @[255'u8, 0, 0, 0, 0, 0]

  test "provisional header constraints and row framing are explicit":
    expect ValueError:
      discard parseAmigaPbm(form(@[
        chunk("BMHD", header(1, 1, 0, planes = 1)),
        chunk("BODY", @[0'u8, 0])]))
    expect ValueError:
      discard parseAmigaPbm(form(@[
        chunk("BMHD", header(1, 1, 2)),
        chunk("BODY", @[0'u8, 0])]))
    expect ValueError:
      discard parseAmigaPbm(form(@[
        chunk("BMHD", header(1, 1, 0, masking = 1)),
        chunk("BODY", @[0'u8, 0])]))
    expect ValueError:
      discard decodeAmigaPbm(parseAmigaPbm(form(@[
        chunk("BMHD", header(3, 1, 0)),
        chunk("BODY", @[1'u8, 2, 3])])).image)
    expect ValueError:
      discard decodeAmigaPbm(parseAmigaPbm(form(@[
        chunk("BMHD", header(2, 1, 1)),
        chunk("BODY", @[0xfd'u8, 1])])).image)
