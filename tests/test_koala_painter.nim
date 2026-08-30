import std/unittest
import vexterlib

const AuthenticFixtureDirectory =
  "tests/fixtures/commodore64.koala-painter/"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

proc koalaImage(): seq[byte] =
  result = newSeq[byte](KoalaPainterFileSize)
  result[0] = 0x00
  result[1] = 0x60
  result[KoalaBitmapOffset] = 0x1b # selectors 00, 01, 10, 11
  result[KoalaScreenRamOffset] = 0x25
  result[KoalaColourRamOffset] = 0x0e
  result[KoalaBackgroundOffset] = 0x07

suite "Commodore 64 KoalaPainter images":
  test "authentic D64-extracted images match their PNG controls":
    for name in ["garfield", "ghost"]:
      let
        koalaPath = AuthenticFixtureDirectory & name & ".koa"
        pngPath = AuthenticFixtureDirectory & name & ".png"
        koalaInspection = inspectSource(koalaPath, readBytes(koalaPath))
        pngInspection = inspectSource(pngPath, readBytes(pngPath))
        koala = koalaInspection.resources.rasterResources[0].raster.image
        control = pngInspection.resources.rasterResources[0].raster.image
      check koalaInspection.selectedFormat.typeId == KoalaPainterTypeId
      check koalaInspection.selectedFormat.confidence == vdcProbable
      check koala.width == 320
      check koala.height == 200
      check control.width == koala.width
      check control.height == koala.height
      for y in 0 ..< koala.height:
        for x in 0 ..< koala.width:
          check koala.colourAt(x, y) == control.colourAt(x, y)
          check control.alphaAt(x, y) == 255

  test "multicolour cells decode to doubled pixels in VIC-II index order":
    let inspection = inspectSource("selectors.koa", koalaImage())
    check inspection.selectedFormat.typeId == KoalaPainterTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    check inspection.resources.roots[0].path == KoalaPainterImageResourcePath
    check inspection.resources.roots[0].typeId == KoalaPainterImageTypeId
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 320
    check image.height == 200
    check image.pixels[0 .. 7] == @[7'u8, 7, 2, 2, 5, 5, 14, 14]
    check image.palette == @ColodorePalette
    check image.palette[2] == VextRgb(r: 0x81, g: 0x33, b: 0x38)
    check image.palette[14] == VextRgb(r: 0x70, g: 0x6d, b: 0xeb)
    check inspection.resources.roots[0].defaultExportFormat == "png"

  test "structural evidence works without an extension":
    let inspection = inspectSource("BUBBLE", koalaImage())
    check inspection.selectedFormat.typeId == KoalaPainterTypeId
    check inspection.selectedFormat.confidence == vdcPossible

  test "short input is rejected while addresses, background high bits, and tails survive":
    var data = koalaImage()
    expect ValueError: discard parseKoalaPainter(data[0 ..< data.high])
    data = koalaImage()
    data[1] = 0x44
    data[KoalaBackgroundOffset] = 0xf1
    data.add @[0xaa'u8, 0xbb]
    let source = parseKoalaPainter(data)
    check source.loadAddress == 0x4400
    check source.backgroundByte == 0xf1
    check source.backgroundColour == 1
    check source.trailingByteCount == 2

  test "exact .koala is probable while a tolerated tail is possible":
    var exact = koalaImage()
    exact[1] = 0x44
    check inspectSource("paralax.koala", exact).selectedFormat.confidence ==
      vdcProbable
    exact.add newSeq[byte](15)
    check inspectSource("parallax.koala", exact).selectedFormat.confidence ==
      vdcPossible
