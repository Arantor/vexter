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

proc bmhd(planes = 1, width = 16): seq[byte] =
  @[byte(width shr 8), byte(width), 0, 2, 0, 0, 0, 0,
    byte(planes), 0, 0, 0, 0, 0, 1, 1,
    byte(width shr 8), byte(width), 0, 2]

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

proc initialForm(planes = 1, camg = 0, width = 16,
    extraChunks: seq[seq[byte]] = @[]): seq[byte] =
  var cmap = @[0'u8, 0, 0, 0xff, 0xff, 0xff]
  if planes == 6:
    cmap = newSeq[byte](16 * 3)
  var chunks = @[
    chunk("BMHD", bmhd(planes, width)),
    chunk("CMAP", cmap)]
  if camg != 0:
    chunks.add chunk("CAMG", @[
      byte(camg shr 24), byte(camg shr 16), byte(camg shr 8), byte(camg)])
  chunks.add extraChunks
  chunks.add chunk("BODY", newSeq[byte](planes * ((width + 15) div 16) * 4))
  form("ILBM", chunks)

proc dpan(frameCount, framesPerSecond: int): seq[byte] =
  chunk("DPAN", @[0'u8, 3, byte(frameCount shr 8), byte(frameCount),
    byte(framesPerSecond), 0, 0, 0])

proc crng(rate, flags, low, high: int): seq[byte] =
  chunk("CRNG", @[0'u8, 0, byte(rate shr 8), byte(rate),
    byte(flags shr 8), byte(flags), byte(low), byte(high)])

proc ccrt(direction, low, high, milliseconds: int): seq[byte] =
  let micros = milliseconds * 1000
  chunk("CCRT", @[byte(direction shr 8), byte(direction), byte(low), byte(high),
    0, 0, 0, 0, byte(micros shr 24), byte(micros shr 16),
    byte(micros shr 8), byte(micros), 0, 0])

proc animWithDelta(operation: int, delta: seq[byte], bits = 0,
    planes = 1, camg = 0, width = 16): seq[byte] =
  form("ANIM", [initialForm(planes, camg, width),
    form("ILBM", [chunk("ANHD", anhd(operation, bits)),
      chunk("DLTA", delta)])])

proc animWithXorBody(): seq[byte] =
  var header = anhd(1)
  header[1] = 1 # plane zero
  header[2] = 0
  header[3] = 1
  header[4] = 0
  header[5] = 1
  header[6] = 0
  header[7] = 1 # x = 1
  header[8] = 0
  header[9] = 1 # y = 1
  form("ANIM", [initialForm(),
    form("ILBM", [chunk("ANHD", header),
      chunk("BODY", @[0x80'u8, 0])])])

proc method5Delta(): seq[byte] =
  result = pointerTable(64)
  result.add @[1'u8, 0x81, 0x80, 0] # literal row zero, then empty column

proc method2Delta(): seq[byte] =
  result = newSeq[byte](32)
  result[3] = 32
  result.add @[0'u8, 0, 0x80, 0, 0, 0, 0xff, 0xff]

proc method3Delta(): seq[byte] =
  result = newSeq[byte](32)
  result[3] = 32
  result.add @[0'u8, 0, 0x80, 0, 0xff, 0xff]

proc method3RunDelta(): seq[byte] =
  result = newSeq[byte](32)
  result[3] = 32
  # Establish word zero, then -2 starts a run one word beyond that cursor.
  result.add @[0'u8, 0, 0x80, 0,
    0xff, 0xfe, 0, 1, 0x40, 0, 0xff, 0xff]

proc method4ShortDelta(repeatVertical = false): seq[byte] =
  result = pointerTable(32, 33) # method-4 pointers count 16-bit words
  result.add @[0x80'u8, 0]
  result.add @[0'u8, 0,
    byte(if repeatVertical: 0xff else: 0),
    byte(if repeatVertical: 0xfe else: 1),
    0xff, 0xff]

proc method4SharedDelta(): seq[byte] =
  result = method4ShortDelta(true)
  result[39] = 33 # repeat the info pointer for unchanged plane one

proc method4LongXorDelta(): seq[byte] =
  result = pointerTable(32, 34)
  result.add @[0x80'u8, 0, 0, 0]
  result.add @[0'u8, 0, 0, 0, 0, 0, 0, 1,
    0xff, 0xff, 0xff, 0xff]

proc method7Delta(): seq[byte] =
  result = pointerTable(64, 66)
  result.add @[1'u8, 0x81, 0x80, 0x00]

proc method7PaddedLongDelta(): seq[byte] =
  result = pointerTable(64, 66)
  result.add @[1'u8, 0x81, 0x80, 0x00, 0xaa, 0x55]

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
    check parsed.hasDpan
    check parsed.dpanVersion == 3
    check parsed.logicalFrameCount == 32
    check parsed.framesPerSecond == 10
    check raster.kind == vrkIndexedAnimation
    check raster.width == 320
    check raster.height == 200
    check raster.animation.frames.len == 32
    check rgbDigest(raster.animation) ==
      "246809A42660BFF4F4F1A0E27F1ED4D08D2BDFCB"

  test "methods 1 through 5, 7, and 8 reconstruct indexed animation frames":
    let cases = [(2, method2Delta()), (3, method3Delta()),
      (5, method5Delta()), (7, method7Delta()),
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

    let runImage = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
      3, method3RunDelta()))).animation.frames[1].image
    check runImage.pixelAt(0, 0) == 1
    check runImage.pixelAt(1, 1) == 1

    let xorImage = decodeAmigaAnim(parseAmigaAnim(
      animWithXorBody())).animation.frames[1].image
    check xorImage.pixelAt(1, 1) == 1

    let method4Image = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
      4, method4ShortDelta()))).animation.frames[1].image
    check method4Image.pixelAt(0, 0) == 1

  test "method 4 supports RLC, vertical, long-data, long-info, and XOR options":
    let repeated = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
      4, method4SharedDelta(), bits = 0x1c,
      planes = 2))).animation.frames[1].image
    check repeated.pixelAt(0, 0) == 1
    check repeated.pixelAt(0, 1) == 1

    let longXor = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
      4, method4LongXorDelta(), bits = 0x23, width = 32))).animation.frames[1].image
    check longXor.pixelAt(0, 0) == 1

  test "method 5 supports animation-brush XOR semantics":
    let raster = decodeAmigaAnim(parseAmigaAnim(
      animWithDelta(5, method5Delta(), bits = 4))).animation
    check raster.frames[0].image.pixelAt(0, 0) == 0
    check raster.frames[1].image.pixelAt(0, 0) == 1

  test "ANIM jiffies follow explicit PAL and NTSC monitor timing":
    let
      ntsc = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
        5, method5Delta(), camg = 0x00011000))).animation
      pal = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
        5, method5Delta(), camg = 0x00021000))).animation
    check ntsc.frames[1].durationMs == 100
    check pal.frames[1].durationMs == 120

  test "DPAN controls logical frame count and playback rate":
    let deltaForm = form("ILBM", [chunk("ANHD", anhd(5)),
      chunk("DLTA", method5Delta())])
    let data = form("ANIM", [
      initialForm(extraChunks = @[dpan(2, 10)]),
      deltaForm, deltaForm, deltaForm])
    let
      parsed = parseAmigaAnim(data)
      animation = decodeAmigaAnim(parsed).animation
    check parsed.hasDpan
    check parsed.dpanVersion == 3
    check parsed.logicalFrameCount == 2
    check parsed.framesPerSecond == 10
    check animation.frames.len == 2
    check animation.frames[0].durationMs == 100
    check animation.frames[1].durationMs == 100

    expect ValueError:
      discard parseAmigaAnim(form("ANIM", [
        initialForm(extraChunks = @[dpan(2, 0)]), deltaForm]))
    var unsupportedDpan = dpan(2, 10)
    unsupportedDpan[9] = 4
    expect ValueError:
      discard parseAmigaAnim(form("ANIM", [
        initialForm(extraChunks = @[unsupportedDpan]), deltaForm]))

  test "CRNG and CCRT retain up to six effective colour ranges":
    let deltaForm = form("ILBM", [chunk("ANHD", anhd(5)),
      chunk("DLTA", method5Delta())])
    var ranges = @[ccrt(-1, 0, 1, 500)]
    for unused in 0 ..< 6:
      ranges.add crng(273, 1, 0, 1)
    ranges.add crng(273, 1, 1, 1) # Empty range is ignored.
    let parsed = parseAmigaAnim(form("ANIM", [
      initialForm(extraChunks = ranges), deltaForm]))
    let animation = decodeAmigaAnim(parsed).animation
    check parsed.initial.image.colourCycles.len == 8
    check animation.colourCycles.len == 6
    check animation.colourCycles[0].direction == -1
    check animation.colourCycles[0].stepDurationMs == 500
    var constantPalette = parsed.initial.image
    constantPalette.colourMap = newSeq[byte](constantPalette.colourMap.len)
    check decodeAmigaIlbmImage(constantPalette).colourCycles.len == 0

  test "method 7 clips a padded final longword to the ILBM row":
    let image = decodeAmigaAnim(parseAmigaAnim(animWithDelta(
      7, method7PaddedLongDelta(), bits = 1))).animation.frames[1].image
    check image.pixelAt(0, 0) == 1
    check image.pixelAt(1, 0) == 0

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
    expect ValueError:
      discard decodeAmigaAnim(parseAmigaAnim(animWithDelta(
        4, method4ShortDelta(), bits = 0x40)))
