import std/unittest
import vexterlib

proc bytes(text: string): seq[byte] =
  for value in text: result.add byte(value)

proc sauce(payload: seq[byte], flags = 0'u8, comments: seq[string] = @[]): seq[byte] =
  result = payload
  result.add 0x1a
  if comments.len > 0:
    result.add "COMNT".bytes
    for line in comments:
      for index in 0 ..< 64:
        result.add(if index < line.len: byte(line[index]) else: byte(' '))
  var record = newSeq[byte](128)
  for index, value in "SAUCE00": record[index] = byte(value)
  for index, value in "Test": record[7 + index] = byte(value)
  for index in 11 ..< 90: record[index] = byte(' ')
  record[94] = 1                    # Character
  record[95] = 1                    # ANSI
  record[96] = 80                   # TInfo1 width, little endian
  record[104] = uint8(comments.len)
  record[105] = flags
  result.add record

suite "ANSI art and SAUCE":
  test "meaningful ANSI is probable without extension or SAUCE":
    let inspection = inspectSource("unknown", "\e[31mA".bytes)
    check inspection.selectedFormat.typeId == AnsiArtTypeId
    check inspection.selectedFormat.confidence == vdcProbable
    let image = inspection.resources.rasterResources[0].raster.image
    check image.width == 720
    check image.height == 86
    check image.palette[4] == VextRgb(r: 170, g: 0, b: 0)
    check uint8(4) in image.pixels
    let square = inspectSource("unknown", "\e[31mA".bytes,
      ansiLetterSpacing = alsEight, ansiAspect = apaSquare).
      resources.rasterResources[0].raster.image
    check square.width == 640
    check square.height == 16

  test "SAUCE metadata makes ANSI certain and selects eight-pixel spacing":
    let data = sauce("\e[1;34mX".bytes, flags = 0b00000010,
      comments = @["first", "second"])
    let source = parseAnsiArt(data)
    check source.sauce.present
    check source.sauce.title == "Test"
    check source.sauce.commentLines == @["first", "second"]
    let inspection = inspectSource("art.bin", data)
    check inspection.selectedFormat.confidence == vdcCertain
    check inspection.resources.rasterResources[0].raster.image.width == 640
    let overridden = inspectSource("art.bin", data,
      ansiLetterSpacing = alsNine, ansiAspect = apaSquare).
      resources.rasterResources[0].raster.image
    check overridden.width == 720

  test "plain text, malformed escapes, and non-ANSI SAUCE are rejected":
    check not isAnsiArt("ordinary text".bytes)
    check detectFormats("ordinary.nfo", "plain CP437 art".bytes).len == 0
    check detectFormats("FILE_ID.DIZ", "\e[0mANSI description".bytes)[0].
      typeId == AnsiArtTypeId
    check not isAnsiArt("\e[31".bytes)
    var wrong = sauce("\e[31mA".bytes)
    wrong[wrong.len - 128 + 94] = 2
    check not isAnsiArt(wrong)

  test "cursor movement and erase stay within a bounded static canvas":
    let source = parseAnsiArt("A\e[2CB\e[1D\e[K\r\n\e[2;2HC".bytes)
    let image = renderAnsiArt(source)
    check image.width == 720
    check image.height > 16
    check image.pixels.len == image.width * image.height
