import std/unittest
import vexterlib

proc putDword(data: var seq[byte], offset: int, value: uint32) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc getDword(data: openArray[byte], offset: int): uint32 =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc checksumBlock(data: var seq[byte], sector: int) =
  let offset = sector * AmigaAdfBlockSize
  data.putDword(offset + 20, 0)
  var sum = 0'u32
  for position in countup(offset, offset + 508, 4):
    sum += data.getDword(position)
  data.putDword(offset + 20, 0'u32 - sum)

proc putName(data: var seq[byte], sector: int, name: string) =
  let offset = sector * AmigaAdfBlockSize + 432
  data[offset] = byte(name.len)
  for index, value in name:
    data[offset + 1 + index] = byte(value)

proc directoryBlock(data: var seq[byte], sector: int, name: string,
    firstEntry = 0) =
  let offset = sector * AmigaAdfBlockSize
  data.putDword(offset, 2)
  data.putDword(offset + 4, uint32(sector))
  data.putDword(offset + 24, uint32(firstEntry))
  data.putDword(offset + 508, 2)
  data.putName(sector, name)
  data.checksumBlock(sector)

proc fileHeader(data: var seq[byte], sector: int, name: string,
    contents: openArray[byte], dataSectors: openArray[int], nextHash = 0,
    ofs = false) =
  let offset = sector * AmigaAdfBlockSize
  data.putDword(offset, 2)
  data.putDword(offset + 4, uint32(sector))
  data.putDword(offset + 8, uint32(dataSectors.len))
  if dataSectors.len > 0:
    data.putDword(offset + 16, uint32(dataSectors[0]))
  data.putDword(offset + 324, uint32(contents.len))
  data.putName(sector, name)
  data.putDword(offset + 496, uint32(nextHash))
  data.putDword(offset + 508, cast[uint32](-3'i32))
  for index, dataSector in dataSectors:
    data.putDword(offset + 308 - index * 4, uint32(dataSector))
    let dataOffset = dataSector * AmigaAdfBlockSize
    let sourceOffset = index * (if ofs: 488 else: 512)
    let amount = min(contents.len - sourceOffset, if ofs: 488 else: 512)
    if ofs:
      data.putDword(dataOffset, 8)
      data.putDword(dataOffset + 4, uint32(sector))
      data.putDword(dataOffset + 8, uint32(index + 1))
      data.putDword(dataOffset + 12, uint32(amount))
      if index + 1 < dataSectors.len:
        data.putDword(dataOffset + 16, uint32(dataSectors[index + 1]))
      for byteIndex in 0 ..< amount:
        data[dataOffset + 24 + byteIndex] = contents[sourceOffset + byteIndex]
      data.checksumBlock(dataSector)
    else:
      for byteIndex in 0 ..< amount:
        data[dataOffset + byteIndex] = contents[sourceOffset + byteIndex]
  data.checksumBlock(sector)

proc rootBlock(data: var seq[byte], flags, firstEntry: int) =
  data[0] = byte('D')
  data[1] = byte('O')
  data[2] = byte('S')
  data[3] = byte(flags)
  let sector = data.len div AmigaAdfBlockSize div 2
  let offset = sector * AmigaAdfBlockSize
  data.putDword(offset, 2)
  data.putDword(offset + 12, 72)
  data.putDword(offset + 24, uint32(firstEntry))
  data.putDword(offset + 508, 1)
  data.putName(sector, "VEXTER")
  data.checksumBlock(sector)

proc ffsFixture(): seq[byte] =
  result = newSeq[byte](AmigaAdfDdSize)
  let text = @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]
  result.fileHeader(10, "README", text, [11], nextHash = 20)
  result.directoryBlock(20, "Pictures", 21)
  result.fileHeader(21, "note", @[byte('o'), byte('k')], [22])
  let screen = newSeq[byte](ZxSpectrumScreenSize)
  result.fileHeader(29, "display.scr", screen,
    [30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43])
  result.putDword(20 * AmigaAdfBlockSize + 496, 29)
  result.checksumBlock(20)
  result.rootBlock(1, 10)

proc malformedAmosProgram(): seq[byte] =
  for value in "AMOS Basic V1.00":
    result.add byte(value)
  result.add @[0'u8, 0, 0, 4]
  result.add @[2'u8, 0, 1, 2]
  for value in "AmBs":
    result.add byte(value)
  result.add @[0'u8, 0]

suite "Amiga ADF filesystems":
  test "FFS directories expose files and recursively decode their contents":
    let
      data = ffsFixture()
      volume = parseAmigaAdf(data)
      candidates = detectFormats("disk.ADF", data)
      inspection = inspectSource("disk.ADF", data)
      leaves = inspection.resources.leafResources
      rasters = inspection.resources.rasterResources
    check volume.name == "VEXTER"
    check volume.filesystem == "FFS"
    check volume.rootBlock == 880
    check volume.entries.len == 3
    check candidates.len == 1
    check candidates[0].typeId == AmigaAdfTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 3
    check leaves.len == 3
    check leaves[0].path == "/disk/display.scr/screen"
    check leaves[0].kind == vrnkRaster
    check leaves[1].path == "/disk/Pictures/note"
    check leaves[1].data == @[byte('o'), byte('k')]
    check leaves[2].path == "/disk/README"
    check leaves[2].data == @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]
    check rasters.len == 1
    check rasters[0].raster.width == 256
    check rasters[0].raster.height == 192

  test "OFS data headers are removed during file reconstruction":
    var data = newSeq[byte](AmigaAdfDdSize)
    let payload = @[1'u8, 2, 3, 4]
    data.fileHeader(10, "old-file", payload, [11], ofs = true)
    data.rootBlock(0, 10)
    let volume = parseAmigaAdf(data)
    check volume.filesystem == "OFS"
    check volume.entries[0].data == payload

  test "a directory self-entry is skipped without losing other hash buckets":
    var data = newSeq[byte](AmigaAdfDdSize)
    data.directoryBlock(20, "SD", 20)
    data.fileHeader(21, "note", @[byte('o'), byte('k')], [22], ofs = true)
    data.putDword(20 * AmigaAdfBlockSize + 28, 21)
    data.checksumBlock(20)
    data.rootBlock(0, 20)
    let volume = parseAmigaAdf(data)
    check volume.entries.len == 1
    check volume.entries[0].name == "SD"
    check volume.entries[0].children.len == 1
    check volume.entries[0].children[0].name == "note"
    check volume.entries[0].children[0].data == @[byte('o'), byte('k')]

  test "signatures, root checksums, and directory cycles are rejected":
    var badSignature = ffsFixture()
    badSignature[0] = byte('X')
    check not isAmigaAdf(badSignature)

    var badChecksum = ffsFixture()
    badChecksum[880 * AmigaAdfBlockSize + 27] = 9
    check not isAmigaAdf(badChecksum)

    var cycle = ffsFixture()
    cycle.putDword(10 * AmigaAdfBlockSize + 496, 10)
    cycle.checksumBlock(10)
    check not isAmigaAdf(cycle)

  test "nested decoder failures identify the contained resource path":
    var data = newSeq[byte](AmigaAdfDdSize)
    data.fileHeader(10, "Broken Source.AMOS", malformedAmosProgram(), [11])
    data.rootBlock(1, 10)
    try:
      discard inspectSource("sources.adf", data)
      check false
    except ValueError as error:
      check error.msg == "while inspecting nested resource " &
        "/disk/Broken Source.AMOS: AMOS listing line at byte 0 " &
        "is not null terminated"

    let tolerant = inspectSource("sources.adf", data, ignoreWarnings = true)
    check tolerant.warnings.len == 1
    check tolerant.warnings[0].path == "/disk/Broken Source.AMOS"
    check tolerant.warnings[0].format == AmosProgramTypeId
    check tolerant.warnings[0].message ==
      "AMOS listing line at byte 0 is not null terminated"
    let resource = tolerant.resources.leafResources[0]
    check resource.path == "/disk/Broken Source.AMOS"
    check resource.kind == vrnkOpaque
    check resource.data == malformedAmosProgram()
