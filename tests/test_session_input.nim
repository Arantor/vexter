import std/[os, tempfiles, unittest]
import vexterlib
import vexter_session_input

proc storedLha(name, contents: string): string =
  let headerSize = 22 + name.len
  result = newString(headerSize + 2)
  result[0] = char(headerSize)
  for index, value in "-lh0-": result[2 + index] = value
  for index in 0 ..< 4:
    result[7 + index] = char(contents.len shr (index * 8) and 0xff)
    result[11 + index] = char(contents.len shr (index * 8) and 0xff)
  result[20] = char(0)
  result[21] = char(name.len)
  for index, value in name: result[22 + index] = value
  var crc: uint16
  for value in contents:
    crc = crc xor uint16(byte(value))
    for bit in 0 ..< 8:
      crc = (crc shr 1) xor
        (if (crc and 1) != 0: 0xa001'u16 else: 0'u16)
  result[22 + name.len] = char(crc and 0xff)
  result[23 + name.len] = char(crc shr 8)
  for index in 2 ..< result.len:
    result[1] = char((int(result[1]) + int(result[index])) and 0xff)
  result.add contents
  result.add char(0)

suite "shared filesystem inspection sessions":
  test "incremental and eager consumers use one filesystem-backed session":
    let
      directory = createTempDir("vexter-session-input-", "")
      archive = directory / "collection.lha"
    defer: removeDir(directory)
    writeFile(archive, storedLha("readme.txt", "hello"))
    let session = openFilesystemInspectionSession(archive)
    defer: session.close()

    check session.selectedFormat.typeId == LhaArchiveTypeId
    let roots = session.rootDescriptors
    require roots.len == 1
    let delta = session.expandResource(roots[0].id)
    require delta.children.len == 1
    check delta.children[0].path == "/archive/readme.txt"

    let tree = session.resourceTree()
    require tree.roots.len == 1
    require tree.roots[0].children.len == 1
    check tree.roots[0].children[0].resourceBytes ==
      @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]

  test "companion paths resolve case-independently":
    let
      directory = createTempDir("vexter-session-companion-", "")
      primaryPath = directory / "image.bin"
      companionDirectory = directory / "Palettes"
      companionPath = companionDirectory / "Colours.dat"
    defer: removeDir(directory)
    createDir(companionDirectory)
    writeFile(primaryPath, "primary")
    writeFile(companionPath, "companion")

    let sources = filesystemSourceCollection(primaryPath)
    defer: sources.close()
    let companion = sources.companion("palettes/colours.dat")
    require not companion.isNil
    check companion.readAll() == @[
      byte('c'), byte('o'), byte('m'), byte('p'), byte('a'), byte('n'),
      byte('i'), byte('o'), byte('n')]
