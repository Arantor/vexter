## Markdown projection of the logical flow-document archetype.

import std/[options, strutils]
import ../archetypes/document
import ../artifacts

type
  VextMarkdownExport* = object
    artifacts*: VextArtifactSet
    warnings*: seq[string]

proc textBytes(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for index, character in value: result[index] = byte(character)

proc addWarning(warnings: var seq[string], warning: string) =
  if warning notin warnings: warnings.add warning

proc escapedMarkdown(value: string): string =
  for character in value:
    # Escape inline Markdown delimiters. List markers, headings, punctuation,
    # and parentheses are only special in particular contexts; escaping them
    # unconditionally makes recovered prose needlessly noisy.
    if character in {'\\', '`', '*', '_', '[', ']', '<', '>', '|'}:
      result.add '\\'
    result.add character

proc safeCommentText(value: string): string =
  result = value.replace("--", "- -").replace(">", "&gt;")

proc styledText(item: VextDocumentInline,
    warnings: var seq[string]): string =
  result = item.text.escapedMarkdown
  if item.style.position != vtpNormal:
    warnings.addWarning("Markdown cannot preserve superscript or subscript text.")
  if item.style.underline:
    warnings.addWarning("Markdown cannot preserve underlined text.")
  if item.style.fontName.len > 0 or item.style.fontSizeMillipoints > 0:
    warnings.addWarning("Markdown cannot preserve font names or sizes.")
  if item.style.strikeout: result = "~~" & result & "~~"
  if item.style.italic: result = "*" & result & "*"
  if item.style.bold: result = "**" & result & "**"

proc exportMarkdown*(document: VextFlowDocument,
    suggestedFilename = "document.md"): VextMarkdownExport =
  document.validate
  var output: string
  for documentBlock in document.blocks:
    case documentBlock.kind
    of vdbkParagraph:
      let style = documentBlock.paragraphStyle
      if style.alignment notin {vpaUnspecified, vpaLeft} or
          style.leftIndentMillipoints.isSome or
          style.rightIndentMillipoints.isSome or
          style.leftMarginColumns.isSome or
          style.rightMarginColumns.isSome or
          style.firstLineIndentMillipoints.isSome or
          style.spaceBeforeMillipoints.isSome or
          style.spaceAfterMillipoints.isSome or
          style.lineSpacingMillipoints.isSome or
          style.justificationMethod != vjmUnspecified or style.keepWithNext or
          style.tabStops.len > 0:
        result.warnings.addWarning(
          "Markdown cannot preserve one or more paragraph layout properties.")
      if output.len > 0 and not output.endsWith("\n\n"): output.add "\n\n"
      for item in documentBlock.content:
        case item.kind
        of vdikText: output.add item.styledText(result.warnings)
        of vdikTab:
          output.add '\t'
          result.warnings.addWarning(
            "Markdown readers may not preserve tab characters or tab stops.")
        of vdikLineBreak: output.add "  \n"
        of vdikSoftLineBreak: discard
        of vdikSoftSpace:
          if output.len > 0 and output[^1] notin {' ', '\t', '\n'}:
            output.add ' '
          result.warnings.addWarning(
            "Markdown cannot distinguish WordStar soft layout spaces.")
        of vdikBindingSpace:
          output.add "&nbsp;"
        of vdikDiscretionaryHyphen:
          output.add "&shy;"
          result.warnings.addWarning(
            "Markdown rendering of discretionary hyphens varies by reader.")
        of vdikRetainedControl:
          output.add "<!-- retained control: " &
            item.control.name.safeCommentText & " -->"
          result.warnings.addWarning(
            "Markdown comments mark retained source controls but cannot reproduce them.")
    of vdbkPageBreak:
      if output.len > 0 and not output.endsWith("\n\n"): output.add "\n\n"
      output.add "<!-- page break -->\n\n"
      result.warnings.addWarning("Markdown cannot enforce page breaks.")
    of vdbkRetainedControl:
      if not documentBlock.blockControl.name.startsWith("wordstar.dot."):
        if output.len > 0 and not output.endsWith("\n\n"): output.add "\n\n"
        output.add "<!-- retained control: " &
          documentBlock.blockControl.name.safeCommentText & " -->\n\n"
        result.warnings.addWarning(
          "Markdown comments mark retained source controls but cannot reproduce them.")
      else:
        result.warnings.addWarning(
          "Markdown omits WordStar dot commands after applying supported layout effects.")
  if output.len > 0 and not output.endsWith("\n"): output.add '\n'
  result.artifacts.artifacts.add VextArtifact(
    suggestedFilename: suggestedFilename,
    mediaType: "text/markdown; charset=utf-8", data: textBytes(output))
