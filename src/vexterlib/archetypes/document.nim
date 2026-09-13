## Logical, flow-oriented documents recovered from word processors and similar
## sources. Source-specific control streams belong in importers; this archetype
## retains their interpreted effect and any controls that could not be decoded.

import std/[options, unicode]

type
  VextSourceRange* = object
    ## Byte range in the original resource. `present` distinguishes an unknown
    ## range from the valid empty range at offset zero.
    present*: bool
    offset*, length*: int

  VextDocumentControl* = object
    ## Stable importer-defined name, a human-readable explanation, and the
    ## original control bytes when they are available.
    name*: string
    description*: string
    argument*: string
    interpreted*: bool
    rawData*: seq[byte]

  VextTextPosition* = enum
    vtpNormal
    vtpSuperscript
    vtpSubscript

  VextCharacterStyle* = object
    ## Effective formatting for one run. Empty font name and zero size mean
    ## that the source did not establish those properties.
    bold*, italic*, underline*, strikeout*: bool
    position*: VextTextPosition
    fontName*: string
    fontSizeMillipoints*: int

  VextParagraphAlignment* = enum
    vpaUnspecified
    vpaLeft
    vpaRight
    vpaCentred
    vpaJustified

  VextTabAlignment* = enum
    vtaLeft
    vtaRight
    vtaCentred
    vtaDecimal

  VextJustificationMethod* = enum
    vjmUnspecified
    vjmWordSpacing
    vjmMicrospacing
    vjmDeviceDefined

  VextTabStop* = object
    positionMillipoints*: int
    alignment*: VextTabAlignment
    leader*: string

  VextParagraphStyle* = object
    alignment*: VextParagraphAlignment
    leftIndentMillipoints*, rightIndentMillipoints*: Option[int]
    ## Character-cell margins are retained separately when the source does not
    ## establish enough physical information to convert them safely.
    leftMarginColumns*, rightMarginColumns*: Option[int]
    firstLineIndentMillipoints*: Option[int]
    spaceBeforeMillipoints*, spaceAfterMillipoints*: Option[int]
    lineSpacingMillipoints*: Option[int]
    justificationMethod*: VextJustificationMethod
    keepWithNext*: bool
    tabStops*: seq[VextTabStop]

  VextDocumentInlineKind* = enum
    vdikText
    vdikTab
    vdikLineBreak
    vdikSoftLineBreak
    vdikSoftSpace
    vdikBindingSpace
    vdikDiscretionaryHyphen
    vdikRetainedControl

  VextDocumentInline* = object
    source*: VextSourceRange
    case kind*: VextDocumentInlineKind
    of vdikText:
      text*: string
      style*: VextCharacterStyle
    of vdikRetainedControl:
      control*: VextDocumentControl
    of vdikDiscretionaryHyphen:
      active*: bool
    of vdikTab, vdikLineBreak, vdikSoftLineBreak, vdikSoftSpace,
        vdikBindingSpace:
      discard

  VextDocumentBlockKind* = enum
    vdbkParagraph
    vdbkPageBreak
    vdbkRetainedControl

  VextDocumentBlock* = object
    source*: VextSourceRange
    case kind*: VextDocumentBlockKind
    of vdbkParagraph:
      paragraphStyle*: VextParagraphStyle
      content*: seq[VextDocumentInline]
    of vdbkRetainedControl:
      blockControl*: VextDocumentControl
    of vdbkPageBreak:
      discard

  VextFlowDocument* = object
    blocks*: seq[VextDocumentBlock]

proc validateSource(source: VextSourceRange) =
  if source.present and (source.offset < 0 or source.length < 0 or
      source.offset > high(int) - source.length):
    raise newException(ValueError, "document source range is invalid")

proc validateControl(control: VextDocumentControl) =
  if control.name.len == 0:
    raise newException(ValueError, "retained document control has no name")

proc validate*(document: VextFlowDocument) =
  for documentBlock in document.blocks:
    documentBlock.source.validateSource
    case documentBlock.kind
    of vdbkParagraph:
      for tabStop in documentBlock.paragraphStyle.tabStops:
        if tabStop.positionMillipoints < 0:
          raise newException(ValueError,
            "document tab-stop position cannot be negative")
      if documentBlock.paragraphStyle.leftMarginColumns.get(0) < 0 or
          documentBlock.paragraphStyle.rightMarginColumns.get(0) < 0:
        raise newException(ValueError,
          "document character-cell margin cannot be negative")
      for item in documentBlock.content:
        item.source.validateSource
        case item.kind
        of vdikText:
          if item.text.validateUtf8 != -1:
            raise newException(ValueError, "document text is not valid UTF-8")
          if item.style.fontSizeMillipoints < 0:
            raise newException(ValueError,
              "document font size cannot be negative")
        of vdikRetainedControl: item.control.validateControl
        else: discard
    of vdbkRetainedControl: documentBlock.blockControl.validateControl
    of vdbkPageBreak: discard

proc plainText*(document: VextFlowDocument): string =
  ## A deliberately formatting-free presentation suitable for previews.
  document.validate
  var previousWasParagraph = false
  for documentBlock in document.blocks:
    case documentBlock.kind
    of vdbkParagraph:
      if result.len > 0 and previousWasParagraph: result.add "\n\n"
      for item in documentBlock.content:
        case item.kind
        of vdikText: result.add item.text
        of vdikTab: result.add '\t'
        of vdikLineBreak: result.add '\n'
        of vdikSoftLineBreak: discard
        of vdikSoftSpace, vdikBindingSpace: result.add ' '
        of vdikDiscretionaryHyphen: discard
        of vdikRetainedControl: discard
      previousWasParagraph = true
    of vdbkPageBreak:
      if result.len > 0 and result[^1] != '\n': result.add '\n'
      result.add '\f'
      previousWasParagraph = false
    of vdbkRetainedControl:
      previousWasParagraph = false
