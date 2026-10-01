import std/unittest
import vexterlib

proc putLe16(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)

proc putLe32(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value)
  data[offset + 1] = byte(value shr 8)
  data[offset + 2] = byte(value shr 16)
  data[offset + 3] = byte(value shr 24)

proc writeDocument(body: openArray[byte], signature = byte(0x31)): seq[byte] =
  let textEnd = 128 + body.len
  let sectionPage = (textEnd + 127) div 128
  let finalPage = sectionPage + 1
  result = newSeq[byte](finalPage * 128)
  result[0] = signature
  result[1] = 0xbe
  result[5] = 0xab
  putLe32(result, 14, textEnd)
  for offset in [18, 20, 22, 24, 26, 28]:
    putLe16(result, offset, sectionPage)
  putLe16(result, 96, finalPage)
  for index, value in body:
    result[128 + index] = value

proc bytesString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc onePixelBmp(): seq[byte] =
  result = newSeq[byte](58)
  result[0] = byte('B')
  result[1] = byte('M')
  putLe32(result, 2, result.len)
  putLe32(result, 10, 54)
  putLe32(result, 14, 40)
  putLe32(result, 18, 1)
  putLe32(result, 22, 1)
  putLe16(result, 26, 1)
  putLe16(result, 28, 24)
  putLe32(result, 34, 4)
  result[54] = 0x20
  result[55] = 0x40
  result[56] = 0x60

proc paintbrushObject(bmpOffset = 83, trailerLength = 34): seq[byte] =
  let bmp = onePixelBmp()
  result = newSeq[byte](bmpOffset + bmp.len + trailerLength)
  result[0] = 0xe4
  putLe32(result, 16, result.len - 40)
  for index, character in "PBrush\0":
    result[52 + index] = byte(character)
  for index, value in bmp:
    result[bmpOffset + index] = value

suite "Windows Write documents":
  test "0x31BE documents recover Windows-1252 text and flow":
    let data = writeDocument(@[byte('F'), byte('i'), byte('r'), byte('s'),
      byte('t'), 0x09, byte('x'), 0x96, byte('y'), 0x0d, 0x0a,
      byte('S'), byte('e'), byte('c'), byte('o'), byte('n'), byte('d')])
    let source = parseWindowsWrite(data)
    check source.textOffset == 128
    check source.textEnd == 145
    check source.sectionPages[0] == 2
    check source.sectionPages[^1] == 3
    check source.lineBreaks == 1
    check source.tabs == 1
    check source.extendedCharacters == 1
    check source.document.plainText == "First\tx–y\nSecond"

  test "detection and inspection expose Markdown export":
    let data = writeDocument(@[byte('O'), byte('n'), byte('e'), 0x0d, 0x0a,
      byte('T'), byte('w'), byte('o')])
    let detected = detectFormats("sample.wri", data)
    check detected[0].typeId == WindowsWriteTypeId
    check detected[0].confidence == vdcProbable
    check detected[0].evidence.len == 2
    let inspected = inspectSource("sample.wri", data)
    let document = inspected.resources.roots[0]
    check document.path == WindowsWriteResourcePath
    check document.kind == vrnkDocument
    check document.defaultExportFormat == "md"
    let exported = exportResource(inspected.resources,
      VextExportRequest(suggestedName: "sample"))
    check exported.artifacts.artifacts[0].data.bytesString == "One  \nTwo\n"

  test "0x32BE Paintbrush objects become raster children and Markdown PNGs":
    var body = @[byte('B'), byte('e'), byte('f'), byte('o'), byte('r'),
      byte('e'), 0x0d, 0x0a]
    body.add paintbrushObject()
    body.add @[byte(0x0d), byte(0x0a), byte('A'), byte('f'), byte('t'),
      byte('e'), byte('r')]
    let data = writeDocument(body, 0x32)
    let source = parseWindowsWrite(data)
    check source.signatureByte == 0x32
    check source.embeddedImages.len == 1
    check source.embeddedImages[0].image.width == 1
    check source.embeddedImages[0].image.height == 1
    check source.document.plainText ==
      "Before\n[Image: Embedded Paintbrush image]\nAfter"

    let detected = detectFormats("embedded.wri", data)
    check detected[0].evidence.len == 3
    let inspected = inspectSource("embedded.wri", data)
    let document = inspected.resources.roots[0]
    check document.children.len == 1
    check document.children[0].path == "/document/image/1"
    check document.children[0].kind == vrnkRaster
    let exported = exportResource(inspected.resources,
      VextExportRequest(resourcePath: WindowsWriteResourcePath,
        suggestedName: "embedded"))
    check exported.artifacts.artifacts.len == 2
    check exported.artifacts.artifacts[0].suggestedFilename == "embedded.md"
    check exported.artifacts.artifacts[0].data.bytesString ==
      "Before  \n![Embedded Paintbrush image](image-1.png)  \nAfter\n"
    check exported.artifacts.artifacts[1].suggestedFilename == "image-1.png"
    check exported.artifacts.artifacts[1].data[0 .. 7] ==
      @[byte(0x89), byte('P'), byte('N'), byte('G'), 0x0d, 0x0a, 0x1a, 0x0a]

  test "0x32BE accepts both observed Paintbrush envelope layouts":
    for layout in [(83, 34), (71, 66)]:
      var body = @[byte('A')]
      body.add paintbrushObject(layout[0], layout[1])
      body.add byte('B')
      let source = parseWindowsWrite(writeDocument(body, 0x32))
      check source.embeddedImages.len == 1
      check source.embeddedImages[0].bmpOffset == 128 + 1 + layout[0]
      check source.document.plainText ==
        "A[Image: Embedded Paintbrush image]B"

  test "unsupported variants and malformed boundaries are rejected":
    var data = writeDocument(@[byte('O'), byte('k')])
    data[0] = 0x33
    expect ValueError:
      discard parseWindowsWrite(data)
    data = writeDocument(@[byte('O'), byte('k')])
    putLe32(data, 14, 257)
    expect ValueError:
      discard parseWindowsWrite(data)
    data = writeDocument(@[byte('O'), 0x01, byte('k')])
    expect ValueError:
      discard parseWindowsWrite(data)
