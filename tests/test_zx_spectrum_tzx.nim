import std/[sequtils, unittest]
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)

proc tapData(flag: byte, payload: openArray[byte]): seq[byte] =
  result.add flag
  var checksum = flag
  for value in payload:
    result.add value
    checksum = checksum xor value
  result.add checksum

proc tapHeader(name: string, dataLength, startAddress: int): seq[byte] =
  var payload = @[ZxSpectrumTapCodeType]
  for index in 0 ..< 10:
    payload.add byte(if index < name.len: name[index] else: ' ')
  payload.addWord(dataLength)
  payload.addWord(startAddress)
  payload.addWord(ZxSpectrumTapCodeParameter2)
  tapData(ZxSpectrumTapHeaderFlag, payload)

proc tzxHeader(): seq[byte] =
  @[byte('Z'), byte('X'), byte('T'), byte('a'), byte('p'), byte('e'),
    byte('!'), 0x1a'u8, 1, 20]

proc standardBlock(tapeData: openArray[byte], pause = 1000): seq[byte] =
  result = @[0x10'u8]
  result.addWord(pause)
  result.addWord(tapeData.len)
  result.add tapeData

suite "ZX Spectrum TZX container":
  test "standard-speed TAP-style records reuse screen decoding":
    let tzx = tzxHeader() &
      standardBlock(tapHeader("DISPLAY", ZxSpectrumScreenSize,
        ZxSpectrumTapScreenAddress)) &
      standardBlock(tapData(ZxSpectrumTapDataFlag,
        newSeqWith(ZxSpectrumScreenSize, 0x5a'u8)))
    let candidates = detectFormats("display.TZX", tzx)
    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumTzxTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 3
    let parsed = parseZxSpectrumTzx(tzx)
    check parsed.majorVersion == 1
    check parsed.minorVersion == 20
    check parsed.blockCount == 2
    check parsed.standardDataBlockCount == 2
    check parsed.records.len == 1
    let resource = inspectSource("display.tzx", tzx).resources.roots[0]
    check resource.path == ZxSpectrumScreenResourcePath
    check resource.kind == vrnkRaster

  test "ordinary standard-speed CODE payloads remain exportable":
    let tzx = tzxHeader() &
      standardBlock(tapHeader("MACHINE", 3, 40000)) &
      standardBlock(tapData(ZxSpectrumTapDataFlag, @[1'u8, 2, 3]))
    let resource = inspectSource("machine.tzx", tzx).resources.roots[0]
    check resource.path == ZxSpectrumTapCodeResourcePath
    check resource.data == @[1'u8, 2, 3]
    check resource.metadata[0].value.stringValue == "MACHINE"

  test "common non-data blocks are structurally skipped":
    let tzx = tzxHeader() &
      @[0x20'u8, 0xe8, 0x03] &
      @[0x21'u8, 3, byte('O'), byte('N'), byte('E')] &
      @[0x22'u8] &
      @[0x30'u8, 4, byte('T'), byte('E'), byte('S'), byte('T')] &
      @[0x33'u8, 1, 0, 0, 0] &
      @[0x5a'u8, byte('X'), byte('T'), byte('a'), byte('p'), byte('e'),
        byte('!'), 0x1a, 1, 20]
    let parsed = parseZxSpectrumTzx(tzx)
    check parsed.blockCount == 6
    check parsed.records.len == 0
    check inspectSource("metadata.tzx", tzx).resources.roots.len == 0

  test "a non-data block cannot bridge a TAP header and payload":
    let tzx = tzxHeader() &
      standardBlock(tapHeader("BROKEN", 1, 40000)) &
      @[0x20'u8, 0, 0] &
      standardBlock(tapData(ZxSpectrumTapDataFlag, @[1'u8]))
    check not isZxSpectrumTzx(tzx)

  test "bad checksums, truncation, versions, and unknown blocks are rejected":
    var badChecksum = tzxHeader() &
      standardBlock(tapData(ZxSpectrumTapDataFlag, @[1'u8]))
    badChecksum[^1] = badChecksum[^1] xor 1
    check not isZxSpectrumTzx(badChecksum)
    check not isZxSpectrumTzx(tzxHeader() & @[0x10'u8, 0, 0, 4, 0, 0])
    var badVersion = tzxHeader()
    badVersion[8] = 2
    check not isZxSpectrumTzx(badVersion)
    check not isZxSpectrumTzx(tzxHeader() & @[0x99'u8])

  test "forced TZX inspection validates its signature":
    expect ValueError:
      discard inspectSource("bad.bin", @[0'u8, 1, 2],
        inputFormat = ZxSpectrumTzxTypeId)
