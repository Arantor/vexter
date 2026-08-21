import std/unittest
import vexterlib

proc bytes(value: string): seq[byte] =
  for item in value: result.add byte(item)

suite "NetPBM images":
  test "plain PBM, PGM, and PPM accept comments and scale visual samples":
    let pbm = inspectSource("plain.pbm", bytes(
      "P1\n# adjacent pixels are valid\n3 1\n010 \nignored"))
    let bitmap = pbm.resources.rasterResources[0].raster.image
    check pbm.selectedFormat.typeId == NetpbmTypeId
    check pbm.selectedFormat.confidence == vdcCertain
    check bitmap.pixels == @[0'u8, 1, 0]
    check bitmap.palette == @[
      VextRgb(r: 255, g: 255, b: 255), VextRgb()]

    let pgm = decodeNetpbm(parseNetpbm(bytes(
      "P2 # header comment\n2 1\n15\n0 15\n")).images[0]).trueColourImage
    check pgm.pixels == @[VextRgb(), VextRgb(r: 255, g: 255, b: 255)]

    let ppm = decodeNetpbm(parseNetpbm(bytes(
      "P3\n2 1\n10\n10 0 5  0 10 0\n")).images[0]).trueColourImage
    check ppm.pixels == @[
      VextRgb(r: 255, g: 0, b: 128),
      VextRgb(r: 0, g: 255, b: 0)]

  test "raw PBM rows, 16-bit PGM, and binary PPM preserve raster bytes":
    var pbm = bytes("P4\n3 2\n")
    pbm.add @[0xa0'u8, 0x40] # 101, then 010; low five bits are row padding.
    let bitmap = decodeNetpbm(parseNetpbm(pbm).images[0]).image
    check bitmap.pixels == @[1'u8, 0, 1, 0, 1, 0]

    var pgm = bytes("P5\n2 1\n65535\n")
    pgm.add @[0'u8, 0, 0xff, 0xff]
    let gray = decodeNetpbm(parseNetpbm(pgm).images[0]).trueColourImage
    check gray.pixels == @[VextRgb(), VextRgb(r: 255, g: 255, b: 255)]

    var ppm = bytes("P6\n1 1\n255 ")
    ppm.add @[10'u8, 32, 13] # Leading whitespace-valued samples are raster.
    let colour = decodeNetpbm(parseNetpbm(ppm).images[0]).trueColourImage
    check colour.pixels == @[VextRgb(r: 10, g: 32, b: 13)]

  test "raw NetPBM streams expose every image through numbered resources":
    var stream = bytes("P4\n1 1\n")
    stream.add 0x80'u8
    stream.add bytes("P6\n1 1\n255\n")
    stream.add @[1'u8, 2, 3]
    let inspection = inspectSource("sequence.pnm", stream)
    let resources = inspection.resources.rasterResources
    check resources.len == 2
    check resources[0].path == "/image/1"
    check resources[1].path == "/image/2"
    check resources[0].raster.image.pixelAt(0, 0) == 1
    check resources[1].raster.trueColourImage.pixels[0] ==
      VextRgb(r: 1, g: 2, b: 3)

  test "PAM visual tuple types support grayscale, RGB, alpha, and extra planes":
    var rgba = bytes("P7\n# arbitrary header order\nHEIGHT 1\nWIDTH 2\n" &
      "DEPTH 5\nMAXVAL 1000\nTUPLTYPE RGB_ALPHA\nENDHDR\n")
    rgba.add @[
      0x03'u8, 0xe8, 0, 0, 0x01, 0xf4, 0x03, 0xe8, 0x03, 0xe7,
      0, 0, 0x03, 0xe8, 0, 0, 0, 0, 0x03, 0xe6]
    let image = decodeNetpbm(parseNetpbm(rgba).images[0]).trueColourImage
    check image.pixels == @[
      VextRgb(r: 255, g: 0, b: 128), VextRgb(r: 0, g: 255, b: 0)]
    check image.alpha == @[255'u8, 0]

    var blackWhite = bytes("P7\nWIDTH 2\nHEIGHT 1\nDEPTH 1\n" &
      "MAXVAL 1\nTUPLTYPE BLACKANDWHITE\nENDHDR\n")
    blackWhite.add @[0'u8, 1]
    check decodeNetpbm(parseNetpbm(blackWhite).images[0]).trueColourImage.
      pixels == @[VextRgb(), VextRgb(r: 255, g: 255, b: 255)]

  test "invalid headers, samples, raster lengths, and PAM tuples are rejected":
    expect ValueError: discard parseNetpbm(bytes("P1 1 1\n2\n"))
    expect ValueError: discard parseNetpbm(bytes("P2\n1 1\n0\n0\n"))
    expect ValueError: discard parseNetpbm(bytes("P3\n1 1\n1\n0 0\n"))
    expect ValueError: discard parseNetpbm(bytes("P4\n9 1\n\x00"))
    expect ValueError: discard parseNetpbm(bytes("P5\n1 1\n3\n\x04"))
    expect ValueError: discard parseNetpbm(bytes("P6\n1 1\n255\n\x00\x00"))
    expect ValueError: discard parseNetpbm(bytes(
      "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 1\nBOGUS 1\nENDHDR\n\x00"))

    var unknown = bytes("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\n" &
      "MAXVAL 1\nTUPLTYPE ELEVATION\nENDHDR\n")
    unknown.add 0'u8
    expect ValueError:
      discard decodeNetpbm(parseNetpbm(unknown).images[0])
