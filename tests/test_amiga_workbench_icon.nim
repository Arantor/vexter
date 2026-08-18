import std/unittest
import vexterlib

proc addBe16(data: var seq[byte], value: int) =
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc addBe32(data: var seq[byte], value: int) =
  data.add byte((value shr 24) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc syntheticIcon(): seq[byte] =
  result = newSeq[byte](AmigaWorkbenchIconHeaderSize)
  result[0] = 0xe3
  result[1] = 0x10
  result[3] = 1
  result[13] = 2
  result[15] = 1
  result[25] = 1
  result[29] = 1
  result[48] = 4
  result[53] = 1
  result[57] = 1
  result[77] = 16
  for selected in 0 .. 1:
    result.addBe16(0)
    result.addBe16(0)
    result.addBe16(2)
    result.addBe16(1)
    result.addBe16(2)
    result.addBe32(1)
    result.add 3'u8
    result.add 0'u8
    result.addBe32(0)
    result.add(if selected == 0: 0x40'u8 else: 0x80'u8)
    result.add 0'u8
    result.add(if selected == 0: 0x00'u8 else: 0x40'u8)
    result.add 0'u8
  result.addBe32(4)
  for value in "Run\0": result.add byte(value)
  var toolTypeData: seq[byte]
  toolTypeData.addBe32(4)
  for value in "A=B\0": toolTypeData.add byte(value)
  toolTypeData.addBe32(7)
  for value in "NOTE=x\0": toolTypeData.add byte(value)
  result.addBe32(12) # three pointer slots: two strings and a terminating NULL
  result.add toolTypeData

suite "Amiga Workbench icons":
  test "classic images and metadata are parsed from a synthetic DiskObject":
    let icon = parseWorkbenchIcon(syntheticIcon())
    check icon.iconType == 4
    check icon.defaultTool == "Run"
    check icon.toolTypes == @["A=B", "NOTE=x"]
    check icon.hasNormalImage
    check icon.hasSelectedImage
    let normal = decodeWorkbenchIconImage(icon.normalImage)
    check normal.width == 2
    check normal.height == 1
    check normal.pixels == @[0'u8, 1'u8]

  test "inspection exposes stable classic paths and prefers unselected":
    let inspection = inspectSource("program.info", syntheticIcon())
    check inspection.selectedFormat.typeId == AmigaWorkbenchIconTypeId
    check inspection.resources.findRasterResource("/icon/unselected") != nil
    check inspection.resources.findRasterResource("/icon/selected") != nil
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "program"))
    check exported.resourcePath == "/icon/unselected"
    check exported.outputFormat == "png"

  test "truncated and unsupported icons are rejected":
    var source = syntheticIcon()
    source.setLen(80)
    expect ValueError:
      discard parseWorkbenchIcon(source)
    source = syntheticIcon()
    source[3] = 2
    expect ValueError:
      discard parseWorkbenchIcon(source)

  test "NewIcons 7-bit images decode with transparency":
    var icon = parseWorkbenchIcon(syntheticIcon())
    proc encoded(values: openArray[byte]): string =
      var bits: seq[byte]
      for value in values:
        for bit in countdown(7, 0): bits.add byte((int(value) shr bit) and 1)
      while bits.len mod 7 != 0: bits.add 0
      for offset in countup(0, bits.high, 7):
        var value = 0
        for bit in 0 .. 6: value = (value shl 1) or int(bits[offset + bit])
        result.add char(if value <= 0x4f: value + 0x20 else: value + 0x51)
    icon.toolTypes.add "IM1=B#\"!#" & encoded([
      0'u8, 0, 0, 255, 255, 255])
    icon.toolTypes.add "IM1=@" # two one-bit pixels: 0, 1, then line padding
    let image = parseNewIcon(icon, 1)
    check image.width == 2
    check image.height == 1
    check image.pixels == @[0'u8, 1'u8]
    check image.alpha == @[0'u8, 255'u8]

  test "GlowIcons FORM exposes both palette colour and alpha":
    var source = syntheticIcon()
    var face: seq[byte]
    for value in "FACE": face.add byte(value)
    face.addBe32(6)
    face.add @[1'u8, 0, 1, 0x11, 0, 5]
    var imageChunk: seq[byte]
    for value in "IMAG": imageChunk.add byte(value)
    imageChunk.addBe32(18)
    imageChunk.add @[0'u8, 1, 3, 0, 0, 1, 0, 1, 0, 5]
    imageChunk.add @[0'u8, 1, 0, 0, 0, 255, 255, 255]
    var selectedChunk: seq[byte]
    for value in "IMAG": selectedChunk.add byte(value)
    selectedChunk.addBe32(12)
    selectedChunk.add @[0'u8, 1, 0, 1, 0, 1, 0, 1, 0, 0]
    selectedChunk.add @[0xff'u8, 0x80] # repeat colour 1 twice
    for value in "FORM": source.add byte(value)
    source.addBe32(4 + face.len + imageChunk.len + selectedChunk.len)
    for value in "ICON": source.add byte(value)
    source.add face
    source.add imageChunk
    source.add selectedChunk
    let glow = parseGlowIcon(source)
    check glow.images.len == 2
    check glow.frameless
    check glow.images[0].pixels == @[0'u8, 1'u8]
    check glow.images[0].alpha == @[0'u8, 255'u8]
    check glow.images[1].pixels == @[1'u8, 1'u8]
    let inspection = inspectSource("glow.info", source)
    check inspection.resources.findRasterResource("/glowicon/unselected") != nil
    check inspection.resources.findRasterResource("/glowicon/selected") != nil
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "glow"))
    check exported.resourcePath == "/glowicon/unselected"
