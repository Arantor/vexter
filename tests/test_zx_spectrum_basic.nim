import std/unittest
import vexterlib

const
  SnapshotPath = "tests/fixtures/zx-spectrum.snapshot/colours-listing.sna"
  ListingPath = "tests/fixtures/zx-spectrum.basic/colours-listing.txt"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc basicLine(number: int, body: openArray[byte]): seq[byte] =
  result = @[byte(number shr 8), byte(number), byte((body.len + 1) and 0xff),
    byte((body.len + 1) shr 8)]
  result.add body
  result.add 0x0d'u8

suite "ZX Spectrum tokenised BASIC":
  test "48K snapshot listing matches the supplied transcription":
    let
      snapshot = readBytes(SnapshotPath)
      expected = readFile(ListingPath)
      inspection = inspectSource(SnapshotPath, snapshot)
    check ZxSpectrumBasicTypeId == "zx-spectrum.basic"
    check ZxSpectrumBasicResourcePath == "/listing"
    check extractZxSpectrumSnapshotBasic(snapshot) == expected
    check inspection.resources.leafResources.len == 2
    check inspection.resources.leafResources[1].path == "/listing"
    check inspection.resources.leafResources[1].text == expected

  test "fixed block graphics map to Unicode":
    let listing = basicLine(10, @[0xf5'u8, byte('"'), 0x80'u8, 0x81'u8,
      0x82'u8, 0x8f'u8, byte('"')])
    check decodeZxSpectrumBasic(listing) == " 10 PRINT \" ▝▘█\""

  test "UDGs and inline controls use reversible annotated text":
    let listing = basicLine(1, @[0xf5'u8, byte('"'), 0x90'u8, 0x10'u8,
      2'u8, 0x14'u8, 1'u8, byte('"')])
    check decodeZxSpectrumBasic(listing) ==
      "REM VEXTER: ⟦UDG A⟧ through ⟦UDG U⟧ denote runtime-defined characters.\n" &
      "REM VEXTER: ⟦INK n⟧ and similar markers preserve parameterised display controls.\n" &
      "  1 PRINT \"⟦UDG A⟧⟦INK 2⟧⟦INVERSE 1⟧\""

  test "every parameterised display control retains its source values":
    let listing = basicLine(2, @[0x10'u8, 2, 0x11, 4, 0x12, 1,
      0x13, 1, 0x14, 0, 0x15, 1, 0x16, 10, 5, 0x17, 20])
    check decodeZxSpectrumBasic(listing) ==
      "REM VEXTER: ⟦INK n⟧ and similar markers preserve parameterised display controls.\n" &
      "  2 ⟦INK 2⟧⟦PAPER 4⟧⟦FLASH 1⟧⟦BRIGHT 1⟧⟦INVERSE 0⟧" &
      "⟦OVER 1⟧⟦AT 10 5⟧⟦TAB 20⟧"

  test "truncated display controls remain reversible unknown bytes":
    let listing = basicLine(3, @[byte('A'), 0x16'u8, 9])
    check decodeZxSpectrumBasic(listing) ==
      "REM VEXTER: ⟦ZX:$HH⟧ preserves an unrecognised source byte.\n" &
      "  3 A⟦ZX:$16⟧⟦ZX:$09⟧"

  test "line zero is accepted and the variables boundary ends parsing":
    var listing = basicLine(0, @[0xea'u8, byte('C')])
    listing.add @[0x80'u8, 0'u8]
    check decodeZxSpectrumBasic(listing) == "  0 REM C"

  test "128K extraction remains explicit pending paging semantics":
    expect ValueError:
      discard extractZxSpectrumSnapshotBasic(
        newSeq[byte](ZxSpectrumSnapshot128Size))

  test "malformed listings are rejected":
    expect ValueError:
      discard decodeZxSpectrumBasic(@[0'u8, 10, 2, 0, byte('A')])
