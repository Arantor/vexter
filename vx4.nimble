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
  exec "nim c -r --path:src tests/test_zx_spectrum_tap.nim"
  exec "nim c -r --path:src tests/test_amos_bank.nim"
  exec "nim c -r --path:src tests/test_amos_bank_set.nim"
  exec "nim c -r --path:src tests/test_amos_program.nim"
  exec "nim c -r --path:src tests/test_amos_sprite_icon_bank.nim"
  exec "nim c -r --path:src tests/test_operations.nim"
  exec "nim c -r --path:src tests/test_cli.nim"
