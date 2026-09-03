import std/unittest
import vexterlib/gui_preview

suite "GUI raster preview policy":
  test "fit preserves aspect ratio and caps enlargement at five times":
    check previewFitSize(16, 16, 1000, 800) == (80, 80)
    check previewFitSize(320, 200, 640, 480) == (640, 400)
    check previewFitSize(1600, 1200, 800, 700) == (800, 600)
    check previewFitSize(3, 2, 7, 100) == (7, 4)

  test "invalid dimensions do not produce a drawable preview":
    check previewFitSize(0, 10, 100, 100) == (0, 0)
    check previewFitSize(10, 10, 0, 100) == (0, 0)

  test "indexed enlargement is nearest while reductions are filtered":
    check previewResampling(true, 16, 16, 80, 80) == vprNearest
    check previewResampling(true, 1600, 1200, 800, 600) == vprFiltered
    check previewResampling(true, 1600, 1200, 1600, 600) == vprFiltered

  test "true-colour previews use filtering in either direction":
    check previewResampling(false, 16, 16, 80, 80) == vprFiltered
    check previewResampling(false, 1600, 1200, 800, 600) == vprFiltered

suite "GUI raw-resource hexdump preview":
  test "sixteen-byte rows have aligned hexadecimal and ASCII columns":
    var data: seq[byte]
    for value in 0 .. 19: data.add byte(value + 30)
    check formatHexdump(data) ==
      "00000000  1E 1F 20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D  " &
      ".. !\"#$%&'()*+,-\r\n" &
      "00000010  2E 2F 30 31                                      " &
      "./01"

  test "only bytes 32 through 126 are rendered as ASCII":
    check formatHexdump(@[31'u8, 32, 65, 126, 127, 255]) ==
      "00000000  1F 20 41 7E 7F FF                              " &
      "  . A~.."

  test "availability is limited to small raw opaque resources":
    check canShowHexdump(true, true, 0)
    check canShowHexdump(true, true, MaximumHexdumpPreviewBytes)
    check not canShowHexdump(true, true, MaximumHexdumpPreviewBytes + 1)
    check not canShowHexdump(false, true, 16)
    check not canShowHexdump(true, false, 16)
    expect ValueError:
      discard formatHexdump(newSeq[byte](MaximumHexdumpPreviewBytes + 1))
