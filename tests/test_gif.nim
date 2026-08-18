import std/unittest
import vexterlib

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

proc oneFrame(image: VextIndexedImage): VextIndexedAnimation =
  VextIndexedAnimation(width: image.width, height: image.height,
    frames: @[VextIndexedAnimationFrame(image: image, durationMs: 0)])

proc imageDescriptor(data: openArray[byte]): int =
  for index in 13 ..< data.len:
    if data[index] == 0x2c: return index
  -1

suite "GIF images":
  test "GIF87a static images remain one-frame animations and default to GIF":
    let image = VextIndexedImage(width: 1, height: 1,
      palette: @[VextRgb(), VextRgb(r: 255, g: 255, b: 255)], pixels: @[1'u8])
    let exported = exportGif(oneFrame(image)).artifacts[0].data
    let descriptor = imageDescriptor(exported)
    var data = exported[0 .. 12]
    for index, value in "GIF87a": data[index] = byte(value)
    data.add exported.toOpenArray(descriptor, exported.high)
    let inspection = inspectSource("still.gif", data)
    let raster = inspection.resources.rasterResources[0].raster
    check inspection.selectedFormat.typeId == GifTypeId
    check parseGif(data).version == "GIF87a"
    check raster.kind == vrkIndexedAnimation
    check raster.animation.frames.len == 1
    check raster.animation.frames[0].image.colourAt(0, 0) ==
      VextRgb(r: 255, g: 255, b: 255)
    check exportResource(inspection.resources,
      VextExportRequest(suggestedName: "still")).outputFormat == "gif"

  test "GIF89a local palettes and transparency survive import and re-export":
    let animation = VextIndexedAnimation(width: 2, height: 1, frames: @[
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 2, height: 1,
        palette: @[VextRgb(r: 255, g: 0, b: 0)], pixels: @[0'u8, 0],
        alpha: @[255'u8, 0]), durationMs: 100),
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 2, height: 1,
        palette: @[VextRgb(r: 0, g: 0, b: 255)], pixels: @[0'u8, 0]),
        durationMs: 200)])
    let data = exportGif(animation).artifacts[0].data
    let decoded = decodeGif(parseGif(data)).animation
    check decoded.frames.len == 2
    check decoded.frames[0].durationMs == 100
    check decoded.frames[0].image.colourAt(0, 0) == VextRgb(r: 255, g: 0, b: 0)
    check decoded.frames[0].image.alphaAt(1, 0) == 0
    check decoded.frames[1].image.colourAt(0, 0) == VextRgb(r: 0, g: 0, b: 255)
    check exportGif(decoded).artifacts[0].mediaType == "image/gif"
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/image",
      typeId: GifImageTypeId, kind: vrnkRaster,
      raster: VextRaster(kind: vrkIndexedAnimation, animation: decoded))])
    check exportResource(tree, VextExportRequest(suggestedName: "again")).
      outputFormat == "gif"

  test "interlaced rows are restored to natural order":
    let storedOrder = VextIndexedImage(width: 1, height: 4,
      palette: @[VextRgb(r: 0), VextRgb(r: 1), VextRgb(r: 2), VextRgb(r: 3)],
      pixels: @[0'u8, 2, 1, 3])
    var data = exportGif(oneFrame(storedOrder)).artifacts[0].data
    let descriptor = imageDescriptor(data)
    data[descriptor + 9] = data[descriptor + 9] or 0x40
    let image = decodeGif(parseGif(data)).animation.frames[0].image
    check image.pixels == @[0'u8, 1, 2, 3]

  test "existing independently encoded GIF controls complete the pipeline":
    for path in ["tests/fixtures/zx-spectrum.screen/colours.gif",
        "tests/fixtures/amos.sprite-bank/DRAGON.gif",
        "tests/fixtures/amiga.anim/TheTour.gif"]:
      let inspection = inspectSource(path, readBytes(path))
      check inspection.resources.rasterResources[0].raster.kind ==
        vrkIndexedAnimation
      check inspection.resources.rasterResources[0].raster.animation.frames.len > 0

  test "truncation and invalid LZW data are rejected during inspection":
    let image = VextIndexedImage(width: 1, height: 1,
      palette: @[VextRgb()], pixels: @[0'u8])
    var data = exportGif(oneFrame(image)).artifacts[0].data
    data.setLen(data.len - 1)
    check not isGif(data)

    var bad = exportGif(oneFrame(image)).artifacts[0].data
    bad[^3] = 0xff
    expect ValueError: discard inspectSource("bad.gif", bad)
