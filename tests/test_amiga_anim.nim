{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}
import std/[sequtils, strutils, unittest]
import vexterlib

const TourFixturePath = "tests/fixtures/amiga.anim/TheTour.anim"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc rgbDigest(animation: VextIndexedAnimation): string =
  var rgb = newStringOfCap(animation.width * animation.height *
    animation.frames.len * 3)
  for frame in animation.frames:
    for paletteIndex in frame.image.pixels:
      let colour = frame.image.palette[int(paletteIndex)]
      rgb.add char(colour.r)
      rgb.add char(colour.g)
      rgb.add char(colour.b)
  $secureHash(rgb)

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

proc bmhd(planes = 1): seq[byte] =
  @[0'u8, 16, 0, 2, 0, 0, 0, 0, byte(planes), 0, 0, 0,
    0, 0, 1, 1, 0, 16, 0, 2]

proc anhd(operation: int, bits = 0, interleave = 1): seq[byte] =
  result = newSeq[byte](40)
  result[0] = byte(operation)
  result[2] = 0
  result[3] = 16
  result[4] = 0
  result[5] = 2
  result[17] = 6 # six jiffies = 100 ms
  result[18] = byte(interleave)
  result[20] = byte(bits shr 24)
  result[21] = byte(bits shr 16)
  result[22] = byte(bits shr 8)
  result[23] = byte(bits)

proc pointerTable(first: int, ninth = 0): seq[byte] =
  result = newSeq[byte](64)
  result[0] = byte(first shr 24)
  result[1] = byte(first shr 16)
  result[2] = byte(first shr 8)
  result[3] = byte(first)
  result[32] = byte(ninth shr 24)
  result[33] = byte(ninth shr 16)
  result[34] = byte(ninth shr 8)
  result[35] = byte(ninth)

proc initialForm(planes = 1, camg = 0): seq[byte] =
  var cmap = @[0'u8, 0, 0, 0xff, 0xff, 0xff]
  if planes == 6:
    cmap = newSeq[byte](16 * 3)
  var chunks = @[
    chunk("BMHD", bmhd(planes)),
    chunk("CMAP", cmap)]
  if camg != 0:
    chunks.add chunk("CAMG", @[
      byte(camg shr 24), byte(camg shr 16), byte(camg shr 8), byte(camg)])
  chunks.add chunk("BODY", newSeq[byte](planes * 2 * 2))
  form("ILBM", chunks)

proc animWithDelta(operation: int, delta: seq[byte], bits = 0,
    planes = 1, camg = 0): seq[byte] =
  form("ANIM", [initialForm(planes, camg),
    form("ILBM", [chunk("ANHD", anhd(operation, bits)),
      chunk("DLTA", delta)])])

proc method5Delta(): seq[byte] =
  result = pointerTable(64)
  result.add @[1'u8, 0x81, 0x80, 0] # literal row zero, then empty column

proc method7Delta(): seq[byte] =
  result = pointerTable(64, 66)
  result.add @[1'u8, 0x81, 0x80, 0x00]

proc method8Delta(): seq[byte] =
  result = pointerTable(64)
  result.add @[0'u8, 1, 0x80, 1, 0x80, 0]

proc ham6Delta(): seq[byte] =
  result = newSeq[byte](64)
  var offset = 64
  for plane in [0, 1, 2, 3, 5]:
    result[plane * 4] = byte(offset shr 24)
    result[plane * 4 + 1] = byte(offset shr 16)
    result[plane * 4 + 2] = byte(offset shr 8)
    result[plane * 4 + 3] = byte(offset)
    result.add @[1'u8, 0x81, 0x80, 0]
    offset += 4

suite "Amiga IFF ANIM":
  test "TheTour method-5 fixture matches every normalized GIF frame":
    let
      data = readBytes(TourFixturePath)
      parsed = parseAmigaAnim(data)
      inspection = inspectSource(TourFixturePath, data)
      raster = inspection.resources.rasterResources[0].raster
    check parsed.frames.len == 33
    check parsed.frames.allIt(it.header.operation == 5)
    check raster.kind == vrkIndexedAnimation
    check raster.width == 320
    check raster.height == 200
    check raster.animation.frames.len == 34
    check rgbDigest(raster.animation) ==
      "FA30299DE1C943A21CE8076586454EB1696E9AAE"
    check raster.animation.frames[32].image.pixels ==
      raster.animation.frames[0].image.pixels
    check raster.animation.frames[33].image.pixels ==
      raster.animation.frames[1].image.pixels

  test "methods 5, 7, and 8 reconstruct indexed animation frames":
    let cases = [(5, method5Delta()), (7, method7Delta()),
      (8, method8Delta())]
    for item in cases:
      let
        data = animWithDelta(item[0], item[1])
        candidates = detectFormats("sample.anim", data)
        inspection = inspectSource("sample.anim", data)
        raster = inspection.resources.rasterResources[0].raster
      check candidates.len == 1
      check candidates[0].typeId == AmigaAnimTypeId
      check candidates[0].confidence == vdcCertain
      check raster.kind == vrkIndexedAnimation
      check raster.animation.frames.len == 2
      check raster.animation.frames[0].image.pixelAt(0, 0) == 0
      check raster.animation.frames[1].image.pixelAt(0, 0) == 1
      check raster.animation.frames[1].durationMs == 100
      let exported = exportResource(inspection.resources,
        VextExportRequest(suggestedName: "sample"))
      check exported.outputFormat == "gif"
      check exported.artifacts.artifacts[0].data[0 .. 5] ==
        @[byte('G'), byte('I'), byte('F'), byte('8'), byte('9'), byte('a')]

  test "method 5 supports animation-brush XOR semantics":
    let raster = decodeAmigaAnim(parseAmigaAnim(
      animWithDelta(5, method5Delta(), bits = 4))).animation
    check raster.frames[0].image.pixelAt(0, 0) == 0
    check raster.frames[1].image.pixelAt(0, 0) == 1

  test "true-colour animations export as APNG":
    let animation = VextTrueColourAnimation(
      width: 1, height: 1,
      frames: @[
        VextTrueColourAnimationFrame(
          image: VextTrueColourImage(width: 1, height: 1,
            pixels: @[VextRgb(r: 255, g: 0, b: 0)]), durationMs: 100),
        VextTrueColourAnimationFrame(
          image: VextTrueColourImage(width: 1, height: 1,
            pixels: @[VextRgb(r: 0, g: 0, b: 255)]), durationMs: 200)])
    let artifact = exportApng(animation).artifacts[0]
    var encoded = newString(artifact.data.len)
    for index, value in artifact.data: encoded[index] = char(value)
    check artifact.mediaType == "image/apng"
    check "acTL" in encoded
    check "fcTL" in encoded
    check "fdAT" in encoded

  test "HAM ANIM decoding routes through true-colour APNG":
    let
      data = animWithDelta(5, ham6Delta(), planes = 6, camg = 0x0800)
      inspection = inspectSource("ham.anim", data)
      raster = inspection.resources.rasterResources[0].raster
      exported = exportResource(inspection.resources,
        VextExportRequest(suggestedName: "ham"))
    check raster.kind == vrkTrueColourAnimation
    check raster.trueColourAnimation.frames.len == 2
    check raster.trueColourAnimation.frames[1].image.colourAt(0, 0) ==
      VextRgb(r: 255, g: 0, b: 0)
    check exported.outputFormat == "apng"
    check exported.artifacts.artifacts[0].mediaType == "image/apng"

  test "documented-but-unimplemented methods remain identifiable":
    let data = animWithDelta(6, method5Delta())
    check detectFormats("stereo.anim", data)[0].typeId == AmigaAnimTypeId
    expect ValueError:
      discard inspectSource("stereo.anim", data)

  test "malformed nested forms and delta pointers are rejected":
    check not isAmigaAnim(form("ANIM", []))
    var badDelta = method5Delta()
    badDelta[3] = 63
    expect ValueError:
      discard inspectSource("bad.anim", animWithDelta(5, badDelta))
