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
