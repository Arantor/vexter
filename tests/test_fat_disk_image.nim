import std/[strutils, unittest]
import vexterlib

proc putWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value and 0xff)
  data[offset + 1] = byte((value shr 8) and 0xff)

proc putDword(data: var seq[byte], offset, value: int) =
  data.putWord(offset, value)
  data.putWord(offset + 2, value shr 16)

proc sampleFat12(): seq[byte] =
  result = newSeq[byte](10 * 512)
  result[0] = 0xeb; result[1] = 0x3c; result[2] = 0x90
  for index, value in "VEXTER  ": result[3 + index] = byte(value)
  result.putWord(11, 512)
  result[13] = 1
  result.putWord(14, 1)
  result[16] = 2
  result.putWord(17, 16)
  result.putWord(19, 10)
  result[21] = 0xf8
  result.putWord(22, 1)
  result.putWord(24, 1)
  result.putWord(26, 1)
  result[510] = 0x55; result[511] = 0xaa
  for fatOffset in [512, 1024]:
    result[fatOffset] = 0xf8
    result[fatOffset + 1] = 0xff
    result[fatOffset + 2] = 0xff
    result[fatOffset + 3] = 0xff # cluster 2 -> 0xfff
    result[fatOffset + 4] = 0x0f
  let root = 1536
  for index, value in "HELLO   WS ": result[root + index] = byte(value)
  result[root + 11] = 0x20
  result.putWord(root + 26, 2)
  let contents = @[byte('H'), byte('i'), 0xa0'u8, byte('t'), byte('h'),
    byte('e'), byte('r'), byte('e'), 0x0d'u8, 0x0a, 0x1a]
  result.putDword(root + 28, contents.len)
  for index, value in contents: result[2048 + index] = value

suite "FAT raw disk images":
  test "FAT12 BPB, mirrored FATs, root directory, and file chain parse":
    let volume = parseFatDiskImage(sampleFat12())
    check volume.kind == fkFat12
    check volume.bytesPerSector == 512
    check volume.entries.len == 1
    check volume.entries[0].name == "HELLO.WS"
    check volume.entries[0].data == @[byte('H'), byte('i'), 0xa0'u8,
      byte('t'), byte('h'), byte('e'), byte('r'), byte('e'), 0x0d, 0x0a,
      0x1a]

  test "detection requires structure and uses IMG only as supporting evidence":
    let detected = detectFormats("sample.img", sampleFat12())
    check detected[0].typeId == FatDiskImageTypeId
    check detected[0].confidence == vdcProbable
    var invalid = sampleFat12()
    invalid[1024] = 0
    check not isFatDiskImage(invalid)
    check detectFormats("sample.img", invalid).len == 0

  test "inspection exposes files for export and whole-container extraction":
    let inspected = inspectSource("sample.img", sampleFat12())
    check inspected.resources.roots[0].path == "/disk"
    var file: VextResourceNode
    for item in inspected.resources.allResources:
      if item.path == "/disk/HELLO.WS": file = item
    check not file.isNil
    check file.kind == vrnkOpaque
    check file.resourceBytes.len == 11
    let session = openInspectionSession("sample.img",
      newSourceCollection(memoryByteSource(sampleFat12())))
    let plan = session.extractionPlan()
    check plan.entries.len == 1
    check plan.entries[0].kind == veekFile
    check plan.entries[0].relativePath.endsWith("HELLO.WS")
    let descriptor = session.resourceAtPath("/disk/HELLO.WS")
    check vrcProbeNested in descriptor.capabilities
    let loaded = session.loadResource(descriptor.id)
    check loaded.resources.roots[0].kind == vrnkGroup
    check loaded.resources.roots[0].children.len == 1
    check loaded.resources.roots[0].children[0].kind == vrnkDocument
