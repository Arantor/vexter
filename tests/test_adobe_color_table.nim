import std/unittest
import vexterlib

suite "Adobe Color Table palettes":
  test "768 bytes decode as 256 ordered RGB8 triplets":
    var data = newSeq[byte](AdobeColorTableSize)
    for index in 0 ..< AdobeColorTableColours:
      data[index * 3] = byte(index)
      data[index * 3 + 1] = byte(255 - index)
      data[index * 3 + 2] = byte(index xor 0x55)
    let inspection = inspectSource("colours.ACT", data)
    check inspection.selectedFormat.typeId == AdobeColorTableTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    let resource = inspection.resources.roots[0]
    check resource.path == AdobeColorTableResourcePath
    check resource.palette.colours.len == 256
    check resource.palette.colours[37] ==
      VextRgba(r: 37, g: 218, b: 112, a: 255)
    check resource.defaultExportFormat == "palette-swatch"

  test "ACT colours agree with equivalent JASC text":
    var act = newSeq[byte](AdobeColorTableSize)
    var jasc = "JASC-PAL\n0100\n256\n"
    for index in 0 ..< AdobeColorTableColours:
      let red = byte(index)
      let green = byte(index div 2)
      let blue = byte(255 - index)
      act[index * 3] = red
      act[index * 3 + 1] = green
      act[index * 3 + 2] = blue
      jasc.add $red & " " & $green & " " & $blue & "\n"
    var jascBytes: seq[byte]
    for character in jasc: jascBytes.add byte(character)
    check parseAdobeColorTable(act) == parseJascPalette(jascBytes)

  test "automatic detection requires extension and exact size":
    let data = newSeq[byte](AdobeColorTableSize)
    check detectFormats("colours.bin", data).len == 0
    check detectFormats("colours.act", data)[0].typeId == AdobeColorTableTypeId
    check not isAdobeColorTable(newSeq[byte](AdobeColorTableSize - 1))
    check not isAdobeColorTable(newSeq[byte](AdobeColorTableSize + 1))
    let forced = inspectSource("colours.bin", data,
      inputFormat = AdobeColorTableTypeId)
    check forced.resources.roots[0].palette.colours.len == 256
