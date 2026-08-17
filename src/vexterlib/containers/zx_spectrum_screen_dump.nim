## Container rules for standalone ZX Spectrum screen dumps.

import std/[os, strutils]
import ../resources/zx_spectrum_screen

const ZxSpectrumScreenDumpTypeId* = ZxSpectrumScreenTypeId

proc isZxSpectrumScreenDump*(data: openArray[byte]): bool =
  data.len == ZxSpectrumScreenSize

proc hasZxSpectrumScreenDumpExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".scr"

proc extractZxSpectrumScreenDump*(data: openArray[byte]): seq[byte] =
  if not isZxSpectrumScreenDump(data):
    raise newException(ValueError,
      "ZX Spectrum screen dump must contain exactly 6912 bytes")
  @data
