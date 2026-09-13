import std/unittest
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte(value shr 8 and 0xff)

proc addDword(data: var seq[byte], value: int) =
  for shift in [0, 8, 16, 24]: data.add byte(value shr shift and 0xff)

proc setDword(data: var seq[byte], offset, value: int) =
  for index, shift in [0, 8, 16, 24]:
    data[offset + index] = byte(value shr shift and 0xff)

proc newPaletteChunk(size, first, last: int,
    colours: openArray[VextRgba]): seq[byte] =
  result.addDword(0)
  result.addWord(0x2019)
  result.addDword(size)
  result.addDword(first)
  result.addDword(last)
  for unused in 0 ..< 8: result.add 0
  for colour in colours:
    result.addWord(0)
    result.add @[colour.r, colour.g, colour.b, colour.a]
  result.setDword(0, result.len)

proc oldPaletteChunk(): seq[byte] =
  result.addDword(0)
  result.addWord(0x0004)
  result.addWord(1)
  result.add 0
  result.add 2
  result.add @[byte 200, 201, 202, 210, 211, 212]
  result.setDword(0, result.len)

proc unknownChunk(): seq[byte] =
  result.addDword(6)
  result.addWord(0x1234)

proc layerChunk(name: string, flags = 1, layerType = 0, childLevel = 0,
    blendMode = 0, opacity = 255): seq[byte] =
  result.addDword(0)
  result.addWord(0x2004)
  result.addWord(flags)
  result.addWord(layerType)
  result.addWord(childLevel)
  result.addWord(0)
  result.addWord(0)
  result.addWord(blendMode)
  result.add byte(opacity)
  result.add @[0'u8, 0, 0]
  result.addWord(name.len)
  for value in name: result.add byte(value)
  result.setDword(0, result.len)

proc zlibStored(data: openArray[byte]): seq[byte] =
  result = @[0x78'u8, 0x01, 0x01]
  result.addWord(data.len)
  result.addWord(data.len xor 0xffff)
  result.add data
  var a = 1
  var b = 0
  for value in data:
    a = (a + int(value)) mod 65521
    b = (b + a) mod 65521
  let checksum = (b shl 16) or a
  for shift in [24, 16, 8, 0]: result.add byte(checksum shr shift and 0xff)

proc celChunk(layer, x, y: int, pixels: openArray[byte], width, height: int,
    opacity = 255, compressed = false, zIndex = 0): seq[byte] =
  result.addDword(0)
  result.addWord(0x2005)
  result.addWord(layer)
  result.addWord(x and 0xffff)
  result.addWord(y and 0xffff)
  result.add byte(opacity)
  result.addWord(if compressed: 2 else: 0)
  result.addWord(zIndex and 0xffff)
  result.add @[0'u8, 0, 0, 0, 0]
  result.addWord(width)
  result.addWord(height)
  if compressed: result.add zlibStored(pixels) else: result.add pixels
  result.setDword(0, result.len)

proc linkedCelChunk(layer, frame: int; x = 0, y = 0, opacity = 255): seq[byte] =
  result.addDword(0)
  result.addWord(0x2005)
  result.addWord(layer)
  result.addWord(x and 0xffff)
  result.addWord(y and 0xffff)
  result.add byte(opacity)
  result.addWord(1)
  result.addWord(0)
  result.add @[0'u8, 0, 0, 0, 0]
  result.addWord(frame)
  result.setDword(0, result.len)

proc frame(chunks: openArray[seq[byte]], duration: int): seq[byte] =
  result.addDword(0)
  result.addWord(0xf1fa)
  result.addWord(chunks.len)
  result.addWord(duration)
  result.addWord(0)
  result.addDword(chunks.len)
  for chunk in chunks: result.add chunk
  result.setDword(0, result.len)

proc aseFrames(frames: openArray[seq[byte]], width, height, depth: int,
    flags = 1, transparent = 0, speed = 100): seq[byte] =
  result = newSeq[byte](128)
  result[4] = 0xe0
  result[5] = 0xa5
  result[6] = byte(frames.len)
  result[7] = byte(frames.len shr 8)
  result[8] = byte(width)
  result[9] = byte(width shr 8)
  result[10] = byte(height)
  result[11] = byte(height shr 8)
  result[12] = byte(depth)
  result[14] = byte(flags)
  result[18] = byte(speed)
  result[19] = byte(speed shr 8)
  result[28] = byte(transparent)
  for value in frames: result.add value
  result.setDword(0, result.len)

proc aseFile(chunks: openArray[seq[byte]], depth = 8): seq[byte] =
  result = newSeq[byte](128)
  result[4] = 0xe0
  result[5] = 0xa5
  result[6] = 1
  result[8] = 1
  result[10] = 1
  result[12] = byte(depth)
  result[18] = 100
  result[28] = 3
  result[32] = 4
  let frameStart = result.len
  result.addDword(0)
  result.addWord(0xf1fa)
  result.addWord(chunks.len)
  result.addWord(75)
  result.addWord(0)
  result.addDword(chunks.len)
  for chunk in chunks: result.add chunk
  result.setDword(frameStart, result.len - frameStart)
  result.setDword(0, result.len)

proc metadataValue(resource: VextResourceNode, key: string): VextMetadataValue =
  for entry in resource.metadata:
    if entry.key == key: return entry.value

suite "Aseprite files":
  test "new palette chunks preserve RGBA and ranged updates":
    let initial = newPaletteChunk(3, 0, 2, [
      VextRgba(r: 1, g: 2, b: 3, a: 4),
      VextRgba(r: 5, g: 6, b: 7, a: 8),
      VextRgba(r: 9, g: 10, b: 11, a: 12)])
    let update = newPaletteChunk(3, 1, 1, [
      VextRgba(r: 20, g: 21, b: 22, a: 23)])
    let inspection = inspectSource("palette.aseprite",
      aseFile([unknownChunk(), initial, update]))
    check inspection.selectedFormat.typeId == AsepriteTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == AsepritePaletteResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 1, g: 2, b: 3, a: 4),
      VextRgba(r: 20, g: 21, b: 22, a: 23),
      VextRgba(r: 9, g: 10, b: 11, a: 12)]
    check resource.metadataValue("frames").integerValue == 1
    check resource.metadataValue("chunks").integerValue == 3
    check resource.metadataValue("palette-chunks").integerValue == 2
    check resource.defaultExportFormat == "palette-swatch"

  test "new palette takes precedence over compatibility old palette":
    let modern = newPaletteChunk(1, 0, 0,
      [VextRgba(r: 1, g: 2, b: 3, a: 4)])
    let source = parseAseprite(aseFile([oldPaletteChunk(), modern]))
    check source.palette.colours == @[
      VextRgba(r: 1, g: 2, b: 3, a: 4)]

  test "old palette is available when no new chunk exists":
    let source = parseAseprite(aseFile([oldPaletteChunk()]))
    check source.palette.colours.len == 256
    check source.palette.colours[0] ==
      VextRgba(r: 200, g: 201, b: 202, a: 255)
    check source.palette.colours[1] ==
      VextRgba(r: 210, g: 211, b: 212, a: 255)

  test "structural errors are rejected":
    var wrongSize = aseFile([unknownChunk()])
    wrongSize[0] = 1
    expect ValueError: discard parseAseprite(wrongSize)
    expect ValueError: discard parseAseprite(aseFile([unknownChunk()], 24))
    var badChunk = unknownChunk()
    badChunk.setDword(0, 100)
    expect ValueError: discard parseAseprite(aseFile([badChunk]))

  test "raw and compressed RGBA cels composite with frame durations":
    let data = aseFrames([
      frame([layerChunk("bottom"), layerChunk("top", opacity = 128),
        celChunk(0, 0, 0, [255'u8, 0, 0, 255], 1, 1),
        celChunk(1, 0, 0, [0'u8, 0, 255, 255], 1, 1,
          compressed = true)], 40),
      frame([linkedCelChunk(0, 0), linkedCelChunk(1, 0)], 90)], 1, 1, 32)
    let inspection = inspectSource("layers.aseprite", data)
    let resource = inspection.resources.roots[0]
    check resource.path == AsepriteSpriteResourcePath
    check resource.kind == vrnkRaster
    check resource.raster.kind == vrkTrueColourAnimation
    let animation = resource.raster.trueColourAnimation
    check animation.frames.len == 2
    check animation.frames[0].durationMs == 40
    check animation.frames[1].durationMs == 90
    check animation.frames[0].image.rgbaAt(0, 0) ==
      VextRgba(r: 127, g: 0, b: 128, a: 255)
    check animation.frames[1].image.rgbaAt(0, 0) ==
      VextRgba(r: 127, g: 0, b: 128, a: 255)

  test "indexed cels use frame palettes and transparent index":
    let data = aseFrames([
      frame([layerChunk("pixels"), newPaletteChunk(2, 0, 1, [
        VextRgba(r: 1, g: 2, b: 3, a: 255),
        VextRgba(r: 10, g: 20, b: 30, a: 255)]),
        celChunk(0, 0, 0, [0'u8, 1], 2, 1)], 0)], 2, 1, 8,
      transparent = 0, speed = 75)
    let raster = inspectSource("indexed.ase", data).resources.roots[0].raster
    check raster.kind == vrkTrueColourImage
    check raster.trueColourImage.rgbaAt(0, 0).a == 0
    check raster.trueColourImage.rgbaAt(1, 0) ==
      VextRgba(r: 10, g: 20, b: 30, a: 255)

  test "grayscale cels expand value and preserve alpha":
    let data = aseFrames([frame([layerChunk("gray"),
      celChunk(0, 0, 0, [42'u8, 128], 1, 1)], 25)], 1, 1, 16)
    let image = inspectSource("gray.ase", data).resources.roots[0].raster.trueColourImage
    check image.rgbaAt(0, 0) == VextRgba(r: 42, g: 42, b: 42, a: 128)

  test "hidden parent groups hide their child image layers":
    let data = aseFrames([frame([
      layerChunk("hidden", flags = 0, layerType = 1),
      layerChunk("child", childLevel = 1),
      celChunk(1, 0, 0, [255'u8, 255, 255, 255], 1, 1)], 10)], 1, 1, 32)
    let image = inspectSource("hidden.ase", data).resources.roots[0].raster.trueColourImage
    check image.rgbaAt(0, 0).a == 0
