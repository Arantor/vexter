import std/[json, options, strutils, unittest]
import vexterlib

proc bytesString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

suite "flow-document archetype":
  test "plain text preserves flow controls but drops formatting and controls":
    let document = VextFlowDocument(blocks: @[
      VextDocumentBlock(kind: vdbkParagraph, content: @[
        VextDocumentInline(kind: vdikText, text: "First"),
        VextDocumentInline(kind: vdikTab),
        VextDocumentInline(kind: vdikText, text: "line"),
        VextDocumentInline(kind: vdikLineBreak),
        VextDocumentInline(kind: vdikText, text: "continued"),
        VextDocumentInline(kind: vdikRetainedControl,
          control: VextDocumentControl(name: "wordstar.test"))]),
      VextDocumentBlock(kind: vdbkParagraph, content: @[
        VextDocumentInline(kind: vdikText, text: "Second")]),
      VextDocumentBlock(kind: vdbkPageBreak),
      VextDocumentBlock(kind: vdbkParagraph, content: @[
        VextDocumentInline(kind: vdikText, text: "Third")])])
    check document.plainText == "First\tline\ncontinued\n\nSecond\n\fThird"

  test "Markdown exports supported styling and reports projection losses":
    let document = VextFlowDocument(blocks: @[
      VextDocumentBlock(kind: vdbkParagraph,
        paragraphStyle: VextParagraphStyle(
          leftIndentMillipoints: some(12000)),
        content: @[
          VextDocumentInline(kind: vdikText, text: "A *literal* "),
          VextDocumentInline(kind: vdikText,
            text: "Periods. Hyphens-and (parentheses)! "),
          VextDocumentInline(kind: vdikText, text: "bold",
            style: VextCharacterStyle(bold: true)),
          VextDocumentInline(kind: vdikTab),
          VextDocumentInline(kind: vdikText, text: "underlined",
            style: VextCharacterStyle(underline: true)),
          VextDocumentInline(kind: vdikLineBreak),
          VextDocumentInline(kind: vdikRetainedControl,
            control: VextDocumentControl(name: "wp--field>"))]),
      VextDocumentBlock(kind: vdbkPageBreak)])
    let exported = exportMarkdown(document, "sample.md")
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].suggestedFilename == "sample.md"
    check exported.artifacts.artifacts[0].mediaType ==
      "text/markdown; charset=utf-8"
    let text = exported.artifacts.artifacts[0].data.bytesString
    check text.contains("A \\*literal\\* Periods. Hyphens-and (parentheses)! **bold**")
    check text.contains("<!-- retained control: wp- -field&gt; -->")
    check text.contains("<!-- page break -->")
    check exported.warnings.len == 5

  test "Markdown collapses repeated soft layout spaces":
    let document = VextFlowDocument(blocks: @[
      VextDocumentBlock(kind: vdbkParagraph, content: @[
        VextDocumentInline(kind: vdikSoftSpace),
        VextDocumentInline(kind: vdikSoftSpace),
        VextDocumentInline(kind: vdikText, text: "Indented"),
        VextDocumentInline(kind: vdikSoftSpace),
        VextDocumentInline(kind: vdikSoftSpace),
        VextDocumentInline(kind: vdikText, text: "text")])])
    let exported = exportMarkdown(document)
    check exported.artifacts.artifacts[0].data.bytesString ==
      "Indented text\n"

  test "document resources participate in discovery and metadata export":
    let resource = VextResourceNode(path: "/document", typeId: "test.document",
      kind: vrnkDocument, document: VextFlowDocument(blocks: @[
        VextDocumentBlock(kind: vdbkParagraph, content: @[
          VextDocumentInline(kind: vdikText, text: "Hello")])]))
    check resource.defaultExportFormat == "md"
    check resource.exportFormatsFor[0].id == "md"

    let exported = exportResource(VextResourceTree(roots: @[resource]),
      VextExportRequest(suggestedName: "document"))
    check exported.outputFormat == "md"
    check exported.artifacts.artifacts[0].data.bytesString == "Hello\n"

    let metadata = exportMetadataJson(resource).artifacts[0].data.bytesString
      .parseJson
    check metadata["kind"].getStr == "document"
    check metadata["resource"]["archetype"].getStr == "VextFlowDocument"
    check metadata["resource"]["paragraphs"].getInt == 1
    check metadata["resource"]["textRuns"].getInt == 1

  test "invalid source ranges and retained controls are rejected":
    expect ValueError:
      VextFlowDocument(blocks: @[VextDocumentBlock(kind: vdbkPageBreak,
        source: VextSourceRange(present: true, offset: -1, length: 1))])
        .validate
    expect ValueError:
      VextFlowDocument(blocks: @[VextDocumentBlock(kind: vdbkRetainedControl)])
        .validate
