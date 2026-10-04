import std/[strutils, unittest]
import vexterlib

proc bytes(value: string): seq[byte] =
  for character in value:
    result.add byte(character)

proc pdfData(version: string): seq[byte] =
  bytes("%PDF-" & version & "\nsynthetic detection fixture")

suite "PDF detection-only support":
  test "recognizes the supplied core versions from the byte-zero header":
    for version in ["1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6",
        "1.7", "2.0"]:
      let candidates = detectFormats("document.PDF", pdfData(version))
      require candidates.len == 1
      check candidates[0].typeId == PdfTypeId
      check candidates[0].support == vfsDetectionOnly
      check candidates[0].confidence == vdcCertain
      check candidates[0].evidence.len == 2
      check version in candidates[0].evidence[0].description
      check candidates[0].derivation.stages[0].typeId == PdfTypeId

  test "the extension supports but does not determine recognition":
    let withoutExtension = detectFormats("document.bin", pdfData("1.7"))
    require withoutExtension.len == 1
    check withoutExtension[0].typeId == PdfTypeId
    check withoutExtension[0].evidence.len == 1

    check detectFormats("document.pdf", bytes("ordinary data")).len == 0

  test "rejects unsupported versions and malformed or displaced headers":
    for value in ["%PDF-1.8\n", "%PDF-1.\n", "%PDF-2.1\n", "%PDF-3.0\n",
        "x%PDF-1.7\n", "%Pdf-1.7\n"]:
      check detectFormats("document.pdf", bytes(value)).len == 0

  test "bounded source detection does not materialize the complete file":
    let data = pdfData("2.0") & newSeq[byte](4096)
    var reads: seq[tuple[offset, amount: int]]
    let source = newByteSource(data.len,
      proc(offset, amount: int): seq[byte] =
        reads.add (offset, amount)
        data[offset ..< offset + amount])
    let input = newDetectionInput("large.pdf", source, PdfHeaderLength,
      leadingBytes = PdfHeaderLength)
    let candidates = input.detectFormats()
    require candidates.len == 1
    check candidates[0].typeId == PdfTypeId
    check reads == @[(0, PdfHeaderLength)]

  test "incremental inspection keeps the opaque payload lazy":
    let data = pdfData("1.7") & newSeq[byte](4096)
    var reads: seq[tuple[offset, amount: int]]
    let source = newByteSource(data.len,
      proc(offset, amount: int): seq[byte] =
        reads.add (offset, amount)
        data[offset ..< offset + amount])
    let session = openInspectionSession("large.pdf",
      newSourceCollection(source))
    defer: session.close()
    check session.selectedFormat.typeId == PdfTypeId
    check session.selectedFormat.support == vfsDetectionOnly
    check reads == @[(0, 11)]
    let roots = session.rootDescriptors
    require roots.len == 1
    check roots[0].path == "/file"
    check roots[0].validatedThrough == vvlEvidence
    let tree = session.resourceTree()
    check reads == @[(0, 11)]
    check tree.roots[0].resourceBytes == data
    check reads == @[(0, 11), (0, data.len)]

  test "forced PDF selection still validates the identifying evidence":
    let inspection = inspectSource("document.pdf", pdfData("1.4"), PdfTypeId)
    check inspection.selectedFormat.typeId == PdfTypeId
    check inspection.selectedFormat.support == vfsDetectionOnly
    require inspection.resources.roots.len == 1
    let resource = inspection.resources.roots[0]
    check resource.path == "/file"
    check resource.typeId == PdfTypeId
    check resource.kind == vrnkOpaque
    check resource.rawDataAvailable
    check resource.resourceBytes == pdfData("1.4")
    check resource.defaultExportFormat == "bin"

    expect ValueError:
      discard inspectSource("document.pdf", bytes("not a PDF"), PdfTypeId)
