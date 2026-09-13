## Container rules for standalone ZX Gigascreen dumps.

import std/[os, strutils]
import ../resources/zx_spectrum_gigascreen
export zx_spectrum_gigascreen

proc hasZxSpectrumGigascreenExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".scr"

proc hasDosExecutableHeader*(data: openArray[byte]): bool =
  data.len >= 2 and data[0] == byte('M') and data[1] == byte('Z')

proc isZxSpectrumGigascreen*(data: openArray[byte]): bool =
  data.len == ZxSpectrumGigascreenSize and not data.hasDosExecutableHeader

proc parseZxSpectrumGigascreen*(data: openArray[byte]): ZxSpectrumGigascreen =
  if not isZxSpectrumGigascreen(data):
    raise newException(ValueError,
      "ZX Gigascreen must contain exactly 7680 bytes and not have a DOS executable header")
  decodeZxSpectrumGigascreen(data)
