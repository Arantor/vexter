## Evidence helpers for detection-only Adobe PDF documents.

import std/strutils

const
  PdfTypeId* = "adobe.pdf"
  PdfHeaderLength* = 8

proc pdfVersion*(data: openArray[byte]): string =
  ## Returns the recognized core version from a PDF header at byte zero.
  if data.len < PdfHeaderLength or
      data[0] != byte('%') or data[1] != byte('P') or
      data[2] != byte('D') or data[3] != byte('F') or
      data[4] != byte('-') or data[6] != byte('.'):
    return
  let recognized =
    (data[5] == byte('1') and data[7] in byte('0') .. byte('7')) or
    (data[5] == byte('2') and data[7] == byte('0'))
  if recognized:
    result = $char(data[5]) & "." & $char(data[7])

proc isPdf*(data: openArray[byte]): bool =
  data.pdfVersion.len > 0

proc hasPdfExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".pdf")
