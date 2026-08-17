version       = "0.1.0"
author        = "Vexter contributors"
description   = "Viewer and extractor for legacy file formats"
license       = "TBD"
srcDir        = "src"
bin           = @["vexter"]

task test, "Run the test suite":
  exec "nim c --path:src -o:build/vexter src/vexter.nim"
  exec "nim c -r --path:src tests/test_zx_spectrum_screen.nim"
  exec "nim c -r --path:src tests/test_zx_spectrum_snapshot.nim"
  exec "nim c -r --path:src tests/test_cli.nim"
