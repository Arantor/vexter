## Container rules for standalone ZX Spectrum screen dumps.

import std/[os, strutils]
import ../resources/zx_spectrum_screen
import ./zx_spectrum_plus3dos

const
  ZxSpectrumScreenDumpTypeId* = ZxSpectrumScreenTypeId
  ZxSpectrumHeaderedScreenSize* = Plus3DosHeaderSize + ZxSpectrumScreenSize
  ZxSpectrumCodeBasicType* = 3'u8
  ZxSpectrumScreenLoadAddress* = 16384'u16

proc isHeaderedZxSpectrumScreenDump*(data: openArray[byte]): bool =
  if data.len != ZxSpectrumHeaderedScreenSize: return false
  try:
    let header = parsePlus3DosHeader(data)
    header.basicType == ZxSpectrumCodeBasicType and
      header.basicFileLength == ZxSpectrumScreenSize.uint16 and
      header.basicParameter1 == ZxSpectrumScreenLoadAddress
  except ValueError:
    false

proc isZxSpectrumScreenDump*(data: openArray[byte]): bool =
  data.len == ZxSpectrumScreenSize or data.isHeaderedZxSpectrumScreenDump

proc hasZxSpectrumScreenDumpExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".scr"

proc extractZxSpectrumScreenDump*(data: openArray[byte]): seq[byte] =
  if not isZxSpectrumScreenDump(data):
    raise newException(ValueError,
      "ZX Spectrum screen dump must contain 6912 raw bytes or a valid 7040-byte +3DOS screen")
  if data.len == ZxSpectrumScreenSize:
    result = @data
  else:
    result = @(data.toOpenArray(Plus3DosHeaderSize, data.high))
