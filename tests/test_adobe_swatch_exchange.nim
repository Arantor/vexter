import std/unittest
import vexterlib

proc addBeWord(data: var seq[byte], value: int) =
  data.add byte(value shr 8 and 0xff)
  data.add byte(value and 0xff)

proc addBeDword(data: var seq[byte], value: int) =
  for shift in [24, 16, 8, 0]: data.add byte(value shr shift and 0xff)

proc addBeFloat(data: var seq[byte], value: float32) =
  data.addBeDword(int(cast[uint32](value)))

proc colourBlock(name: string, red, green, blue: float32): seq[byte] =
  var body: seq[byte]
  body.addBeWord(name.len + 1)
  for character in name:
    body.add 0
    body.add byte(character)
  body.add @[byte 0, 0]
  for character in "RGB ": body.add byte(character)
  body.addBeFloat(red)
  body.addBeFloat(green)
  body.addBeFloat(blue)
  body.addBeWord(2)
  result.addBeWord(1)
  result.addBeDword(body.len)
  result.add body

proc skippedBlock(): seq[byte] =
  result.addBeWord(0xc001)
  result.addBeDword(4)
  result.add @[byte 0, 1, 0, 0]

proc aseFile(blocks: openArray[seq[byte]]): seq[byte] =
  for character in "ASEF": result.add byte(character)
  result.addBeWord(1)
  result.addBeWord(0)
  result.addBeDword(blocks.len)
  for swatchBlock in blocks: result.add swatchBlock

proc metadataValue(resource: VextResourceNode, key: string): VextMetadataValue =
  for entry in resource.metadata:
    if entry.key == key: return entry.value

suite "Adobe Swatch Exchange palettes":
  test "ASEF RGB blocks inspect as an ordered palette":
    let inspection = inspectSource("example.ase", aseFile([
      skippedBlock(), colourBlock("red", 1.0, 0.0, 0.0),
      colourBlock("mixed", 0.5, 0.25, 0.0)]))
    check inspection.selectedFormat.typeId == AdobeSwatchExchangeTypeId
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.selectedFormat.evidence.len == 2
    let resource = inspection.resources.roots[0]
    check resource.path == AdobeSwatchExchangeResourcePath
    check resource.kind == vrnkPalette
    check resource.palette.colours == @[
      VextRgba(r: 255, g: 0, b: 0, a: 255),
      VextRgba(r: 128, g: 64, b: 0, a: 255)]
    check resource.metadataValue("blocks").integerValue == 3
    check resource.metadataValue("rgb-colours").integerValue == 2
    check resource.defaultExportFormat == "palette-swatch"

  test "malformed versions, lengths, names, and RGB values are rejected":
    var badVersion = aseFile([colourBlock("x", 0.0, 0.0, 0.0)])
    badVersion[5] = 2
    expect ValueError: discard parseAdobeSwatchExchange(badVersion)
    var badLength = aseFile([colourBlock("x", 0.0, 0.0, 0.0)])
    badLength[17] = 255
    expect ValueError: discard parseAdobeSwatchExchange(badLength)
    var badName = colourBlock("x", 0.0, 0.0, 0.0)
    badName[11] = 1
    expect ValueError: discard parseAdobeSwatchExchange(aseFile([badName]))
    expect ValueError:
      discard parseAdobeSwatchExchange(aseFile([
        colourBlock("x", 1.1, 0.0, 0.0)]))
