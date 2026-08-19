import std/unittest
import vexterlib

proc putWord(data: var seq[byte], offset: int, value: uint16) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc putDword(data: var seq[byte], offset: int, value: uint32) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc getDword(data: openArray[byte], offset: int): uint32 =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc dmsCrc(data: openArray[byte]): uint16 =
  var crc = 0'u16
  for value in data:
    crc = crc xor uint16(value)
    for bit in 0 ..< 8:
      crc = if (crc and 1) != 0: (crc shr 1) xor 0xa001'u16 else: crc shr 1
  crc

proc checksum(data: openArray[byte]): uint16 =
  var sum = 0'u32
  for value in data: sum += uint32(value)
  uint16(sum and 0xffff)

proc rleEncode(data: openArray[byte]): seq[byte] =
  var index = 0
  while index < data.len:
    var amount = 1
    while index + amount < data.len and data[index + amount] == data[index] and
        amount < 0xfe:
      inc amount
    if amount >= 3:
      result.add @[0x90'u8, byte(amount), data[index]]
      index += amount
    else:
      for unused in 0 ..< amount:
        if data[index] == 0x90: result.add @[0x90'u8, 0]
        else: result.add data[index]
        inc index

proc emptyAdf(): seq[byte] =
  result = newSeq[byte](AmigaAdfDdSize)
  result[0] = byte('D')
  result[1] = byte('O')
  result[2] = byte('S')
  result[3] = 1
  let root = result.len div AmigaAdfBlockSize div 2
  let offset = root * AmigaAdfBlockSize
  result.putDword(offset, 2)
  result.putDword(offset + 12, 72)
  result[offset + 432] = 3
  result[offset + 433] = byte('D')
  result[offset + 434] = byte('M')
  result[offset + 435] = byte('S')
  result.putDword(offset + 508, 1)
  var sum = 0'u32
  for position in countup(offset, offset + 508, 4):
    sum += result.getDword(position)
  result.putDword(offset + 20, 0'u32 - sum)

proc dmsFixture(mode = adcNone): seq[byte] =
  let adf = emptyAdf()
  result = newSeq[byte](AmigaDmsHeaderSize)
  for index, value in "DMS! PRO": result[index] = byte(value)
  result.putWord(16, 0)
  result.putWord(18, 79)
  result.putDword(20, uint32(adf.len))
  result.putDword(24, uint32(adf.len))
  result.putWord(36, 1)
  result.putWord(38, 2)
  result.putWord(50, 2)
  result.putWord(52, uint16(ord(mode)))
  result.putWord(54, dmsCrc(result.toOpenArray(4, 53)))
  const trackLength = AmigaAdfDdSize div 80
  for track in 0 .. 79:
    var plain: seq[byte]
    plain.add adf.toOpenArray(track * trackLength,
      (track + 1) * trackLength - 1)
    let payload = if mode == adcSimple: rleEncode(plain) else: plain
    let offset = result.len
    result.setLen(offset + AmigaDmsTrackHeaderSize + payload.len)
    result[offset] = byte('T')
    result[offset + 1] = byte('R')
    result.putWord(offset + 2, uint16(track))
    result.putWord(offset + 6, uint16(payload.len))
    result.putWord(offset + 8, uint16(payload.len))
    result.putWord(offset + 10, trackLength)
    result[offset + 13] = byte(ord(mode))
    for index, value in payload:
      result[offset + AmigaDmsTrackHeaderSize + index] = value
    result.putWord(offset + 14, checksum(plain))
    result.putWord(offset + 16, dmsCrc(result.toOpenArray(
      offset + AmigaDmsTrackHeaderSize,
      offset + AmigaDmsTrackHeaderSize + payload.len - 1)))
    result.putWord(offset + 18, dmsCrc(result.toOpenArray(offset, offset + 17)))

suite "Amiga DMS disk archives":
  test "uncompressed tracks reconstruct an ADF and expose its filesystem":
    let
      data = dmsFixture()
      archive = parseAmigaDms(data)
      candidates = detectFormats("empty.DMS", data)
      inspection = inspectSource("empty.DMS", data)
    check archive.headerKind == " PRO"
    check archive.lowTrack == 0
    check archive.highTrack == 79
    check archive.tracks.len == 80
    check unpackAmigaDms(archive) == emptyAdf()
    check candidates.len == 1
    check candidates[0].typeId == AmigaDmsTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check inspection.resources.roots.len == 1
    check inspection.resources.roots[0].path == "/disk"
    check inspection.resources.roots[0].typeId == AmigaDmsTypeId
    check inspection.resources.roots[0].children.len == 0

  test "the optional header word may be zero as in authentic disk archives":
    var data = dmsFixture()
    for index in 4 .. 7: data[index] = 0
    data.putWord(54, dmsCrc(data.toOpenArray(4, 53)))
    let archive = parseAmigaDms(data)
    check archive.headerKind == ""
    check isAmigaDms(data)

  test "SIMPLE compression expands DMS RLE tracks":
    let data = dmsFixture(adcSimple)
    check unpackAmigaDms(data) == emptyAdf()

  test "compressed, encrypted, truncated, and malformed archives fail clearly":
    let compressed = parseAmigaDms(dmsFixture(adcQuick))
    expect ValueError:
      discard unpackAmigaDms(compressed)
    let compressedInspection = inspectSource("compressed.dms",
      dmsFixture(adcQuick))
    check compressedInspection.selectedFormat.typeId == AmigaDmsTypeId
    check compressedInspection.resources.roots[0].path == "/tracks"
    check compressedInspection.resources.leafResources.len == 80
    check compressedInspection.resources.leafResources[0].typeId ==
      AmigaDmsTrackTypeId

    var encrypted = dmsFixture()
    encrypted.putDword(8, DmsEncryptedFlag)
    encrypted.putWord(54, dmsCrc(encrypted.toOpenArray(4, 53)))
    expect ValueError:
      discard unpackAmigaDms(encrypted)

    var truncated = dmsFixture()
    truncated.setLen(truncated.len - 1)
    check not isAmigaDms(truncated)

    var badTrack = dmsFixture()
    badTrack[AmigaDmsHeaderSize] = byte('X')
    check not isAmigaDms(badTrack)

  test "authentic public-domain HEAVY2 archives decode as AmigaDOS disks":
    let fixtures = [
      ("Frustration.dms", 348045, 80),
      ("HolyGrail.dms", 260782, 80),
      ("GoldenFleece.dms", 173695, 80)]
    for fixture in fixtures:
      let raw = readFile(fixture[0])
      var data = newSeq[byte](raw.len)
      for index, value in raw: data[index] = byte(value)
      let
        archive = parseAmigaDms(data)
        candidates = detectFormats(fixture[0], data)
        diskData = unpackAmigaDms(archive)
        volume = parseAmigaAdf(diskData)
        inspection = inspectSource(fixture[0], data, ignoreWarnings = true)
      check data.len == fixture[1]
      check archive.headerKind == ""
      check archive.lowTrack == 0
      check archive.highTrack == 79
      check archive.unpackedSize == uint32(AmigaAdfDdSize)
      check archive.compression == adcHeavy2
      check archive.tracks.len == fixture[2]
      check diskData.len == AmigaAdfDdSize
      check diskData[0 .. 3] == @[byte('D'), byte('O'), byte('S'), 0'u8]
      check volume.filesystem == "OFS"
      check volume.entries.len > 0
      check candidates.len == 1
      check candidates[0].typeId == AmigaDmsTypeId
      check inspection.selectedFormat.typeId == AmigaDmsTypeId
      check inspection.resources.roots[0].path == "/disk"
      check inspection.resources.leafResources.len > 0
