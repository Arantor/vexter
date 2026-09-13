import std/unittest
import vexterlib

proc member(path: string, data: seq[byte]): VextRelatedSource =
  let retained = data
  VextRelatedSource(relativePath: path, size: data.len,
    open: proc(): VextByteSource = memoryByteSource(retained))

proc leBytes(value: int): seq[byte] =
  @[byte(value and 0xff), byte((value shr 8) and 0xff)]

suite "Sierra SCI game packages":
  test "SCI0 map and uncompressed volume entries validate and remain lazy":
    # view 3 in resource.000 at offset zero, followed by the map terminator.
    let map = @[0x03'u8, 0x00, 0, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
    let volume = @[0x03'u8, 0x00, 7, 0, 3, 0, 0, 0, 1, 2, 3]
    let sources = newSourceCollection(relatedSources = @[
      member("RESOURCE.MAP", map), member("resource.000", volume)])
    let games = discoverSciGames(sources)
    check games.len == 1
    check games[0].version == srmvSci0
    check games[0].entries[0].kind == srkView
    check resourceBytes(sources, games[0], games[0].entries[0]) == @[1'u8, 2, 3]

  test "SCI1 directory table and resource header validate":
    let map = @[0x87'u8, 6, 0, 0xff, 12, 0,
      2, 0, 0, 0, 0, 0]
    let volume = @[7'u8, 2, 0, 7, 0, 3, 0, 0, 0, 1, 2, 3]
    let sources = newSourceCollection(relatedSources = @[
      member("resource.map", map), member("RESOURCE.000", volume)])
    let games = discoverSciGames(sources)
    check games.len == 1
    check games[0].version == srmvSci1
    check games[0].entries[0].kind == srkFont
    check resourceBytes(sources, games[0], games[0].entries[0]) == @[1'u8, 2, 3]

  test "Huffman decoder handles tree leaves and literal termination":
    # Root: zero selects leaf 'A'; one selects an inline literal. Bits encode
    # A, A, and literal $FF, with $FF serving as the terminator.
    let encoded = @[0xff'u8, 2, 0, 0x10, byte('A'), 0, 0x3f, 0xe0]
    check huffmanDecode(encoded, 2) == @[byte('A'), byte('A')]

  test "SCI LZW uses LSB-first adaptive codes through twelve bits":
    # clear, literal A, literal B, end, packed as four nine-bit LSB-first codes
    check sciLzwDecode(@[0'u8, 0x83, 0x08, 0x09, 0x08], 2) ==
      @[byte('A'), byte('B')]

  test "SCI cursor planes decode transparency and monochrome colours":
    var cursor = newSeq[byte](68)
    cursor[4] = 0x00; cursor[5] = 0x80
    cursor[36] = 0x00; cursor[37] = 0x80
    let image = decodeSciCursor(cursor).image
    check image.alpha[0] == 0
    check image.alpha[1] == 255
    check image.pixels[1] == 0
    cursor[2] = 3
    check sciCursorHotspot(cursor) == (8, 8)
    check sciCursorHotspot(cursor, true) == (0, 3)

  test "SCI0 appended digital samples decode as unsigned eight-bit PCM":
    var data = newSeq[byte](33)
    data[0] = 2
    data.add 0xfc
    let headerAt = data.len
    data.setLen(data.len + 44)
    data[headerAt + 14] = 0xa6
    data[headerAt + 15] = 0x0e # 3750 Hz
    data[headerAt + 32] = 3
    data.add @[0'u8, 128, 255]
    let sample = parseSci0DigitalSample(data)
    check sample.headerOffset == 34
    check sample.sampleRate == 3750
    check sample.sound.buffer.channels[0] == @[-128'i32, 0, 127]
    var directlyLocated = data
    directlyLocated[31] = 0
    directlyLocated[32] = 33
    check parseSci0DigitalSample(directlyLocated).headerOffset == 34

    let map = @[0x50'u8, 0x20, 0, 0, 0, 0,
      0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
    var volume = @[0x50'u8, 0x20]
    volume.add leBytes(data.len + 4)
    volume.add leBytes(data.len)
    volume.add @[0'u8, 0]
    volume.add data
    let sources = newSourceCollection(relatedSources = @[
      member("RESOURCE.MAP", map), member("RESOURCE.000", volume)])
    let session = openInspectionSession("synthetic-sci-sound", sources)
    defer: session.close()
    let sequence = session.resourceAtPath("/game/sounds/sequences/80")
    check sequence.kind == vrnkOpaque
    let playable = session.resourceAtPath("/game/sounds/samples/80")
    check playable.kind == vrnkAudio
    check playable.sampleRate == 3750

  test "SCI font decodes MSB-first glyph rows":
    var fontData = @[0'u8, 0, 1, 0, 6, 0, 8, 0, 3, 2, 0xa0, 0x40]
    let font = decodeSciFont(fontData)
    check font.glyphs.len == 1
    check font.glyphs[0].bitmap.coverage == @[255'u8, 0, 255, 0, 255, 0]

  test "SCI0 view decodes nibble runs and placement":
    var data = @[1'u8, 0, 0, 0, 0, 0, 0, 0]
    data.add leBytes(10)
    data.add @[1'u8, 0, 0, 0]
    data.add leBytes(16)
    data.add @[3'u8, 0, 2, 0, 0xff, 2, 0, 0, 0x11, 0x22, 0x31]
    let view = parseSci0View(data)
    check view.loops.len == 1
    check view.loops[0].cels[0].xOffset == -1
    check view.loops[0].cels[0].pixels == @[1'u8, 2, 2, 1, 1, 1]

  test "documented SCI0 picture exposes all three maps":
    let picture = renderSci0Picture(@[0xf0'u8, 0, 0xf8, 0, 0x94, 0x4f, 0xff])
    check picture.visual.image.pixelAt(148, 79) == 0
    check picture.visual.image.pixelAt(148, 190) == 15
    check picture.priority.image.pixelAt(148, 79) == 0
    check picture.control.image.pixelAt(148, 79) == 0

  test "SCI0 pictures draw absolute lines and replace palette entries":
    let linePicture = renderSci0Picture(@[
      0xf0'u8, 12, 0xf6, 0, 1, 1, 0, 3, 1, 0xff])
    check linePicture.visual.image.pixelAt(1, 1) == 12
    check linePicture.visual.image.pixelAt(2, 1) == 12
    check linePicture.visual.image.pixelAt(3, 1) == 12

    let palettePicture = renderSci0Picture(@[
      0xfe'u8, 0, 0, 0x12, 0xf0, 0, 0xf6, 0, 1, 1, 0, 2, 1, 0xff])
    check palettePicture.visual.image.pixelAt(1, 1) == 2
    check palettePicture.visual.image.pixelAt(2, 1) == 1

  test "underspecified SCI0 extended picture operations are not guessed":
    expect ValueError:
      discard renderSci0Picture(@[0xfe'u8, 7, 0xff])

  test "directory inspection exposes SCI resources":
    let map = @[0x01'u8, 0x38, 0, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
    var fontData = @[0'u8, 0, 1, 0, 6, 0, 8, 0, 1, 1, 0x80]
    var volume = @[0x01'u8, 0x38]
    volume.add leBytes(fontData.len + 4)
    volume.add leBytes(fontData.len)
    volume.add @[0'u8, 0]
    volume.add fontData
    let sources = newSourceCollection(relatedSources = @[
      member("RESOURCE.MAP", map), member("RESOURCE.000", volume)])
    let session = openInspectionSession("synthetic-sci", sources)
    defer: session.close()
    check session.selectedFormat.typeId == SierraSciGameTypeId
    check session.resourceTree.roots[0].children.len == 1
    check session.resourceTree.roots[0].children[0].path == "/game/fonts"
    check session.resourceTree.findFontResource("/game/fonts/1/font") != nil
