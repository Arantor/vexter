import std/[options, unittest]
import vexterlib

proc bytesString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc ws7Document(body: openArray[byte]): seq[byte] =
  result = newSeq[byte](256)
  result[0] = 0x1d
  result[1] = 0x7d
  result[3] = 0
  result[4] = 0x70
  for index, value in "LASERJET": result[5 + index] = byte(value)
  result[16] = 0
  result[17] = 1 # style-library pointer at the 256-byte file end
  result[125] = 0x7d
  result[127] = 0x1d
  for index, value in body: result[128 + index] = value
  for index in 128 + body.len ..< result.len: result[index] = 0x1a

suite "WordStar documents":
  test "headerless streams preserve flow and effective toggle styles":
    let data = @[byte('H'), byte('i') or 0x80, 0xa0, byte('t'), byte('h'),
      byte('e'), byte('r'), byte('e'), 0x8d, 0x0a, 0x02, byte('B'), 0x82,
      0x0d, 0x8a, byte('.'), byte('p'), byte('a'), 0x0d, 0x0a,
      byte('A'), byte('f'), byte('t'), byte('e'), byte('r'), 0x1a, 0x1a]
    let source = parseWordStar(data)
    check not source.hasHeader
    check source.hardReturns == 1
    check source.softReturns == 1
    check source.softSpaces == 1
    check source.formattingControls == 2
    check source.dotCommands == 1
    check source.eofPaddingBytes == 2
    check source.document.blocks.len == 3
    check source.document.blocks[0].kind == vdbkParagraph
    check source.document.blocks[0].content[^1].kind == vdikText
    check source.document.blocks[0].content[^1].text == "B"
    check source.document.blocks[0].content[^1].style.bold
    check source.document.blocks[1].kind == vdbkPageBreak
    check source.document.plainText == "Hi thereB\n\fAfter"

  test "version-seven headers identify certainly and bound body parsing":
    let data = ws7Document(@[byte('O'), byte('k'), 0x0d, 0x0a, 0x1a])
    let source = parseWordStar(data)
    check source.hasHeader
    check source.versionName == "7.0"
    check source.driverName == "LASERJET"
    check source.styleLibraryOffset == 256
    check source.document.plainText == "Ok"
    let detected = detectFormats("sample.bin", data)
    check detected[0].typeId == WordStarTypeId
    check detected[0].confidence == vdcCertain

  test "inspection exposes a document with Markdown export":
    let data = ws7Document(@[byte('A'), 0x02, byte('B'), 0x02, 0x0d, 0x0a,
      0x1a])
    let inspected = inspectSource("sample.ws7", data)
    check inspected.resources.roots.len == 1
    let resource = inspected.resources.roots[0]
    check resource.kind == vrnkDocument
    check resource.defaultExportFormat == "md"
    let exported = exportResource(inspected.resources,
      VextExportRequest(suggestedName: "sample"))
    var markdown = newString(exported.artifacts.artifacts[0].data.len)
    for index, value in exported.artifacts.artifacts[0].data:
      markdown[index] = char(value)
    check markdown == "A**B**\n"

  test "dot lines may contain symmetrical sequences with control bytes":
    let sequence = @[0x1d'u8, 0x04, 0x00, 0x0b, 0x04, 0x00, 0x1d]
    let data = ws7Document(@[byte('.'), byte('p'), byte('a')] & sequence &
      @[0x0d'u8, 0x0a, byte('X'), 0x1a])
    let source = parseWordStar(data)
    check source.dotCommands == 1
    check source.document.blocks[0].kind == vdbkPageBreak
    check source.document.plainText == "\fX"

  test "dot commands accept directly attached numeric parameters":
    let data = @[byte('.'), byte('l'), byte('m'), byte('1'), byte('0'),
      0x0d'u8, 0x0a, byte('T'), byte('e'), byte('x'), byte('t'),
      0x0d, 0x0a, 0x1a]
    let source = parseWordStar(data)
    check source.dotCommands == 1
    check source.retainedControls == 1
    check source.document.blocks[0].blockControl.argument == "10"
    check source.document.blocks[0].blockControl.interpreted
    check source.document.plainText == "Text"

  test "layout dot commands establish following paragraph state":
    let data = @[byte('.'), byte('l'), byte('m'), byte('1'), byte('0'),
      0x0d'u8, 0x0a, byte('.'), byte('r'), byte('m'), byte('5'), byte('5'),
      0x0d, 0x0a, byte('.'), byte('o'), byte('j'), byte(' '), byte('o'),
      byte('n'), 0x0d, 0x0a, byte('.'), byte('u'), byte('j'), byte(' '),
      byte('o'), byte('n'), 0x0d, 0x0a, byte('T'), byte('e'), byte('x'),
      byte('t'), 0x0d, 0x0a, 0x1a]
    let source = parseWordStar(data)
    let paragraph = source.document.blocks[^1]
    check paragraph.kind == vdbkParagraph
    check paragraph.paragraphStyle.leftMarginColumns.get == 10
    check paragraph.paragraphStyle.rightMarginColumns.get == 55
    check paragraph.paragraphStyle.alignment == vpaJustified
    check paragraph.paragraphStyle.justificationMethod == vjmMicrospacing
    let exported = exportMarkdown(source.document)
    check exported.artifacts.artifacts[0].data.bytesString == "Text\n"
    check "Markdown omits WordStar dot commands after applying supported layout effects." in
      exported.warnings

  test "plain text and malformed sequence lookalikes are rejected":
    expect ValueError:
      discard parseWordStar(@[byte('p'), byte('l'), byte('a'), byte('i'),
        byte('n'), 0x0d, 0x0a])
    expect ValueError:
      discard parseWordStar(ws7Document(@[0x1d'u8, 0x10, 0x00, 0x02,
        0x1a]))
