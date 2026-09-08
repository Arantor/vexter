import std/unittest
import vexterlib

proc member(path: string, data: seq[byte]): VextRelatedSource =
  let retained = data
  VextRelatedSource(relativePath: path, size: data.len,
    open: proc(): VextByteSource = memoryByteSource(retained))

suite "Sierra AGI game packages":
  test "v2 package discovery validates headers and keeps resources lazy":
    let directory = @[0'u8, 0, 0]
    let volume = @[0x12'u8, 0x34, 0, 3, 0, 1, 2, 3]
    let sources = newSourceCollection(relatedSources = @[
      member("logdir", directory), member("PICDIR", directory),
      member("ViewDir", directory), member("snddir", directory),
      member("vol.0", volume)])
    let games = discoverAgiGames(sources)
    check games.len == 1
    check games[0].version == av2
    check games[0].entries.len == 4
    check resourceBytes(sources, games[0], games[0].entries[0]) == @[1'u8, 2, 3]

  test "inspection accepts a directory collection without a primary file":
    let directory = @[0'u8, 0, 0]
    let volume = @[0x12'u8, 0x34, 0, 3, 0, 1, 2, 3]
    let sources = newSourceCollection(relatedSources = @[
      member("LOGDIR", directory), member("PICDIR", directory),
      member("VIEWDIR", directory), member("SNDDIR", directory),
      member("VOL.0", volume)])
    let session = openInspectionSession("synthetic-game", sources)
    defer: session.close()
    check session.selectedFormat.typeId == SierraAgiGameTypeId
    check session.resourceTree.roots.len == 1

  test "case-folding ambiguity rejects a package member":
    let directory = @[0'u8, 0, 0]
    let volume = @[0x12'u8, 0x34, 0, 0, 0]
    let sources = newSourceCollection(relatedSources = @[
      member("LOGDIR", directory), member("logdir", directory),
      member("PICDIR", directory), member("VIEWDIR", directory),
      member("SNDDIR", directory), member("VOL.0", volume)])
    check discoverAgiGames(sources).len == 0

  test "v3 packed picture nibbles expand after command parameters":
    check unpackV3Picture(@[0xf0'u8, 0x3a, 0xff], 4) ==
      @[0xf0'u8, 3, 10, 0xff]

  test "VIEW cels decode RLE, transparency, display aspect, and mirroring":
    # Two loops share equivalent cel data. Loop 1 declares loop 0 as the
    # unmirrored source and is therefore flipped for display.
    let data = @[1'u8, 1, 2, 0, 0, 9, 0, 18, 0,
      1, 3, 0, 2, 1, 0x0f, 0x11, 0x21, 0,
      1, 3, 0, 2, 1, 0x8f, 0x11, 0x21, 0]
    let view = parseAgiView(data)
    check view.loops.len == 2
    check view.loops[0].cels[0].pixels == @[1'u8, 2]
    check view.loops[1].cels[0].pixels == @[2'u8, 1]
    let image = view.loops[0].cels[0].raster.image
    check (image.width, image.height) == (4, 1)
    check image.pixels == @[1'u8, 1, 2, 2]
    check image.alpha == @[255'u8, 255, 255, 255]

  test "WORDS.TOK is prefix-decoded with big-endian identifiers":
    var words = newSeq[byte](52)
    words.add @[0'u8, byte('c') xor 0x7f, byte('a') xor 0x7f,
      (byte('t') xor 0x7f) or 0x80, 0, 42, 0]
    check decodeWordsTok(words) == "id\tword\n42\tcat\n"

  test "OBJECT supports plaintext and Avis Durgan encryption":
    let plain = @[3'u8, 0, 15, 3, 0, 255, byte('k'), byte('e'), byte('y'), 0]
    check decodeObject(plain) == "id\troom\tstate\tname\n0\t255\tcarried\tkey\n"
    var encrypted = newSeq[byte](plain.len)
    let key = "Avis Durgan"
    for index, value in plain: encrypted[index] = value xor byte(key[index mod key.len])
    check decodeObject(encrypted) == decodeObject(plain)
