## Recovery-oriented parsing of Windows Write 0x31BE and 0x32BE documents.
## The layout is inferred from developer-supplied Windows 3.1 documents;
## unknown trailing structures are bounded but deliberately not interpreted.

import std/[os, strutils, unicode]
import ../archetypes/document
import ./bmp

const
  WindowsWriteTypeId* = "windows.write"
  WindowsWriteResourcePath* = "/document"
  WindowsWriteMaximumBytes* = 64 * 1024 * 1024
  HeaderSize = 128
  PageSize = 128
  SectionPageFields = [18, 20, 22, 24, 26, 28, 96]
  Cp1252Extension = [
    0x20ac, 0xfffd, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
    0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0xfffd, 0x017d, 0xfffd,
    0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
    0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0xfffd, 0x017e, 0x0178]

type
  WindowsWriteEmbeddedImage* = object
    objectOffset*, objectLength*: int
    bmpOffset*, bmpLength*: int
    resourcePath*, altText*, suggestedFilename*: string
    image*: BmpImageSource

  WindowsWriteSource* = object
    document*: VextFlowDocument
    signatureByte*: byte
    textOffset*, textEnd*: int
    sectionPages*: array[SectionPageFields.len, int]
    lineBreaks*, tabs*, extendedCharacters*: int
    embeddedImages*: seq[WindowsWriteEmbeddedImage]

proc le16(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc le32(data: openArray[byte], offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16) or (int(data[offset + 3]) shl 24)

proc sourceRange(offset, length: int): VextSourceRange =
  VextSourceRange(present: true, offset: offset, length: length)

proc decodeWindows1252(value: byte): string =
  if value < 0x80:
    return $char(value)
  let codePoint = if value < 0xa0:
      Cp1252Extension[int(value) - 0x80] else: int(value)
  Rune(codePoint).toUTF8

proc addText(content: var seq[VextDocumentInline], text: string,
    offset: int) =
  if content.len > 0 and content[^1].kind == vdikText and
      content[^1].source.offset + content[^1].source.length == offset:
    content[^1].text.add text
    inc content[^1].source.length
  else:
    content.add VextDocumentInline(kind: vdikText, text: text,
      source: sourceRange(offset, 1))

proc parseWindowsWrite*(data: openArray[byte]): WindowsWriteSource =
  if data.len < HeaderSize:
    raise newException(ValueError, "truncated Windows Write header")
  if data.len > WindowsWriteMaximumBytes:
    raise newException(ValueError, "Windows Write document exceeds the size limit")
  if data[0] notin [byte(0x31), byte(0x32)] or data[1] != 0xbe or
      data[2] != 0 or data[3] != 0:
    raise newException(ValueError, "unsupported Windows Write signature")
  if data[4] != 0 or data[5] != 0xab:
    raise newException(ValueError, "unsupported Windows Write header variant")
  for offset in 6 .. 13:
    if data[offset] != 0:
      raise newException(ValueError, "invalid Windows Write reserved header field")
  if data.len mod PageSize != 0:
    raise newException(ValueError, "Windows Write file is not page-aligned")
  result.signatureByte = data[0]

  result.textOffset = HeaderSize
  result.textEnd = le32(data, 14)
  if result.textEnd < result.textOffset or result.textEnd > data.len:
    raise newException(ValueError, "invalid Windows Write text boundary")

  var previousPage = 0
  for index, fieldOffset in SectionPageFields:
    let page = le16(data, fieldOffset)
    if page < previousPage or page > data.len div PageSize:
      raise newException(ValueError, "invalid Windows Write section page boundary")
    result.sectionPages[index] = page
    previousPage = page
  if result.sectionPages[0] * PageSize < result.textEnd or
      result.sectionPages[^1] * PageSize != data.len:
    raise newException(ValueError, "Windows Write section pages do not bound the file")

  var content: seq[VextDocumentInline]
  var position = result.textOffset
  while position < result.textEnd:
    let value = data[position]
    case value
    of 0x09:
      content.add VextDocumentInline(kind: vdikTab,
        source: sourceRange(position, 1))
      inc result.tabs
      inc position
    of 0x0d:
      if position + 1 >= result.textEnd or data[position + 1] != 0x0a:
        raise newException(ValueError, "Windows Write carriage return has no line feed")
      content.add VextDocumentInline(kind: vdikLineBreak,
        source: sourceRange(position, 2))
      inc result.lineBreaks
      position += 2
    of 0xe4:
      if result.signatureByte != 0x32:
        content.addText(decodeWindows1252(value), position)
        inc result.extendedCharacters
        inc position
        continue
      # The supplied 0x32BE document wraps a complete BMP in a bounded OLE 1
      # Paintbrush object. The two supplied Sierra documents vary the short
      # descriptor between the class name and BMP, and use 34- or 66-byte
      # suffixes. Search only that bounded descriptor, never the text stream.
      if position > result.textEnd - 83 or position > high(int) - 40:
        raise newException(ValueError, "truncated Windows Write embedded object")
      let storedLength = le32(data, position + 16)
      if storedLength < 77 or storedLength > result.textEnd - position - 40:
        raise newException(ValueError, "invalid Windows Write embedded object length")
      let objectEnd = position + 40 + storedLength
      const className = "PBrush\0"
      for index, character in className:
        if data[position + 52 + index] != byte(character):
          raise newException(ValueError,
            "unsupported Windows Write embedded object class")
      var bmpOffset = -1
      var bmpLength = 0
      let descriptorEnd = min(position + 127, objectEnd - 18)
      for candidate in position + 59 .. descriptorEnd:
        if data[candidate] == byte('B') and
            data[candidate + 1] == byte('M'):
          let candidateLength = le32(data, candidate + 2)
          if candidateLength >= 18 and
              candidateLength <= objectEnd - candidate and
              objectEnd - candidate - candidateLength in [34, 66]:
            if bmpOffset >= 0:
              raise newException(ValueError,
                "ambiguous Windows Write embedded BMP boundary")
            bmpOffset = candidate
            bmpLength = candidateLength
      if bmpOffset < 0:
        raise newException(ValueError,
          "Windows Write Paintbrush object has no BMP payload")
      let imageIndex = result.embeddedImages.len + 1
      let resourcePath = WindowsWriteResourcePath & "/image/" & $imageIndex
      let suggestedFilename = "image-" & $imageIndex & ".png"
      let altText = "Embedded Paintbrush image"
      let image = parseBmp(data.toOpenArray(bmpOffset,
        bmpOffset + bmpLength - 1))
      result.embeddedImages.add WindowsWriteEmbeddedImage(
        objectOffset: position, objectLength: objectEnd - position,
        bmpOffset: bmpOffset, bmpLength: bmpLength,
        resourcePath: resourcePath, altText: altText,
        suggestedFilename: suggestedFilename, image: image)
      content.add VextDocumentInline(kind: vdikImage,
        source: sourceRange(position, objectEnd - position),
        imageResourcePath: resourcePath, imageAltText: altText,
        imageSuggestedFilename: suggestedFilename)
      position = objectEnd
    of 0x00 .. 0x08, 0x0a .. 0x0c, 0x0e .. 0x1f:
      raise newException(ValueError, "unsupported control in Windows Write text stream")
    else:
      content.addText(decodeWindows1252(value), position)
      if value >= 0x80: inc result.extendedCharacters
      inc position
  result.document.blocks.add VextDocumentBlock(kind: vdbkParagraph,
    source: sourceRange(result.textOffset, result.textEnd - result.textOffset),
    content: move(content))
  result.document.validate

proc isWindowsWrite*(data: openArray[byte]): bool =
  try:
    discard parseWindowsWrite(data)
    true
  except ValueError:
    false

proc hasWindowsWriteExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".wri"
