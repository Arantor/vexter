import std/[os, unittest]
import vexterlib

const
  PackedFixturePath = "Fishdemo.anim"
  UnpackedFixturePath = "Fishdemo-unpacked.anim"

proc readBytes(path: string): seq[byte] =
  for value in readFile(path): result.add byte(value)

proc putLong(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc checksumByte(data: openArray[byte], offset, length, excluded: int): byte =
  for index in offset ..< offset + length:
    if index != excluded: result = result xor data[index]

proc rawXpkFixture(): tuple[packed, raw: seq[byte]] =
  result.raw = @[
    byte('F'), byte('O'), byte('R'), byte('M'), 0, 0, 0, 12,
    byte('T'), byte('E'), byte('S'), byte('T'),
    byte('D'), byte('A'), byte('T'), byte('A'), 0, 0, 0, 0]
  result.packed = newSeq[byte](36)
  for index, value in "XPKF": result.packed[index] = byte(value)
  for index, value in "SHRI": result.packed[index + 8] = byte(value)
  result.packed.putLong(12, result.raw.len)
  result.packed[16 .. 31] = result.raw[0 .. 15]

  var chunk = newSeq[byte](8)
  var high, low: byte
  for index, value in result.raw:
    if index mod 2 == 0: high = high xor value else: low = low xor value
  chunk[2] = high
  chunk[3] = low
  chunk[4] = byte(result.raw.len shr 8)
  chunk[5] = byte(result.raw.len)
  chunk[6] = chunk[4]
  chunk[7] = chunk[5]
  chunk[1] = checksumByte(chunk, 0, chunk.len, 1)
  result.packed.add chunk
  result.packed.add result.raw
  result.packed.add @[15'u8, 15, 0, 0, 0, 0, 0, 0]
  result.packed.putLong(4, result.packed.len - 8)
  result.packed[33] = checksumByte(result.packed, 0, 36, 33)

suite "XPK SHRI":
  test "raw XPK chunks unwrap into recursively inspected content":
    let
      fixture = rawXpkFixture()
      archive = parseXpk(fixture.packed)
      candidates = detectFormats("wrapped.xpk", fixture.packed)
      inspection = inspectSource("wrapped.xpk", fixture.packed)
    check archive.compression == "SHRI"
    check archive.chunks.len == 1
    check unpackXpk(archive) == fixture.raw
    check candidates.len == 1
    check candidates[0].typeId == XpkTypeId
    check inspection.selectedFormat.typeId == XpkTypeId
    check inspection.resources.roots[0].path == "/content"
    check inspection.resources.roots[0].typeId == AmigaIffTypeId

  test "Fishdemo SHRI reconstructs its supplied control byte-for-byte":
    if fileExists(PackedFixturePath) and fileExists(UnpackedFixturePath):
      let
        packed = readBytes(PackedFixturePath)
        expected = readBytes(UnpackedFixturePath)
        archive = parseXpk(packed)
        unpacked = unpackXpk(archive)
        inspection = inspectSource(PackedFixturePath, packed)
      check archive.chunks.len == 5
      check unpacked == expected
      check inspection.resources.rasterResources[0].raster.width == 320
      check inspection.resources.rasterResources[0].raster.height == 256
      check inspection.resources.rasterResources[0].raster.animation.frames.len == 102

  test "header and chunk checksum damage is rejected":
    let fixture = rawXpkFixture()
    var badHeader = fixture.packed
    badHeader[33] = badHeader[33] xor 1
    check not isXpk(badHeader)
    var badChunk = fixture.packed
    badChunk[44] = badChunk[44] xor 1
    check not isXpk(badChunk)
