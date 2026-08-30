import std/unittest
import vexterlib

const FixtureDirectory = "d64/"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

proc d64Fixture(): seq[byte] =
  result = newSeq[byte](D64StandardSize)
  const bam = 0x16500
  const directory = 0x16600
  result[bam] = 18; result[bam + 1] = 1; result[bam + 2] = 0x41
  for index, value in "TEST DISK": result[bam + 0x90 + index] = byte(value)
  for index in 9 ..< 16: result[bam + 0x90 + index] = 0xa0
  result[bam + 0xa2] = byte('I'); result[bam + 0xa3] = byte('D')
  result[bam + 0xa5] = byte('2'); result[bam + 0xa6] = byte('A')
  result[directory] = 0; result[directory + 1] = 0xff
  result[directory + 2] = 0x82
  result[directory + 3] = 1; result[directory + 4] = 0
  for index, value in "HELLO": result[directory + 5 + index] = byte(value)
  for index in 5 ..< 16: result[directory + 5 + index] = 0xa0
  result[directory + 0x1e] = 1
  result[0] = 0; result[1] = 6
  for index, value in "hello": result[2 + index] = byte(value)

suite "Commodore 1541 D64 disk images":
  test "BAM, directory entries, and chained file payloads decode":
    let disk = parseD64(d64Fixture())
    check disk.tracks == 35
    check disk.sectorCount == 683
    check not disk.hasErrorBytes
    check disk.name == "TEST DISK"
    check disk.diskId == "ID"
    check disk.dosType == "2A"
    check disk.entries.len == 1
    check disk.entries[0].name == "HELLO"
    check disk.entries[0].kind == dfkProgram
    check disk.entries[0].closed
    check disk.entries[0].declaredSectors == 1
    check disk.entries[0].actualSectors == 1
    check disk.entries[0].data == @['h'.byte, 'e'.byte, 'l'.byte,
      'l'.byte, 'o'.byte]
    check inspectSource("disk.d64", d64Fixture()).selectedFormat.confidence ==
      vdcProbable
    check inspectSource("disk.bin", d64Fixture()).selectedFormat.confidence ==
      vdcPossible

  test "invalid sizes and cyclic chains are rejected":
    expect ValueError: discard parseD64(d64Fixture()[0 ..< D64StandardSize - 1])
    var cyclic = d64Fixture()
    cyclic[0] = 1; cyclic[1] = 0
    expect ValueError: discard parseD64(cyclic)

  test "authentic demo disk exposes and recursively decodes Koala images":
    let path = FixtureDirectory & "KoalaDemo-Romp.d64"
    let data = readBytes(path)
    let disk = parseD64(data)
    check disk.name == "KOALA DEMO"
    check disk.entries.len == 16
    check disk.entries[0].name == "KOALA DEMO"
    let inspection = inspectSource(path, data)
    check inspection.selectedFormat.typeId == D64TypeId
    check inspection.resources.rasterResources.len == 15
    for resource in inspection.resources.rasterResources:
      check resource.typeId == KoalaPainterImageTypeId
      check resource.raster.width == 320
      check resource.raster.height == 200

  test "authentic game disk exposes its two program files":
    let path = FixtureDirectory & "TALESOAN.D64"
    let disk = parseD64(readBytes(path))
    check disk.name == "ASS PRESENTS:"
    check disk.entries.len == 2
    check disk.entries[0].name == "ARABIAN NIGHTS+"
    check disk.entries[0].kind == dfkProgram
    check disk.entries[1].name == "ARABIAN HIGH_2FREM"
    check disk.entries[1].kind == dfkProgram
