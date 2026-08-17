import std/[sequtils, unittest]
import vexterlib

proc addWord(data: var seq[byte], value: int) =
  data.add byte(value and 0xff)
  data.add byte((value shr 8) and 0xff)

proc tapBlock(flag: byte, payload: openArray[byte]): seq[byte] =
  result.addWord(payload.len + 2)
  result.add flag
  var checksum = flag
  for value in payload:
    result.add value
    checksum = checksum xor value
  result.add checksum

proc tapHeader(name: string, dataLength, startAddress: int,
    kind = ZxSpectrumTapCodeType, parameter2 = ZxSpectrumTapCodeParameter2):
    seq[byte] =
  var payload = @[kind]
  for index in 0 ..< 10:
    payload.add byte(if index < name.len: name[index] else: ' ')
  payload.addWord(dataLength)
  payload.addWord(startAddress)
  payload.addWord(parameter2)
  tapBlock(ZxSpectrumTapHeaderFlag, payload)

proc screenRecord(name: string, fill: byte): seq[byte] =
  result = tapHeader(name, ZxSpectrumScreenSize,
    ZxSpectrumTapScreenAddress)
  result.add tapBlock(ZxSpectrumTapDataFlag,
    newSeqWith(ZxSpectrumScreenSize, fill))

proc basicLine(number: int, body: openArray[byte]): seq[byte] =
  result = @[byte(number shr 8), byte(number), byte((body.len + 1) and 0xff),
    byte((body.len + 1) shr 8)]
  result.add body
  result.add 0x0d'u8

suite "ZX Spectrum TAP container":
  test "Program records expose tokenised BASIC listings":
    let
      program = basicLine(10, @[0xf2'u8, byte('1')])
      tap = tapHeader("PROGRAM", program.len, 10,
        kind = ZxSpectrumTapProgramType, parameter2 = program.len) &
        tapBlock(ZxSpectrumTapDataFlag, program)
      listings = parseZxSpectrumTapBasic(tap)
      tree = inspectSource("program.tap", tap).resources
    check listings.len == 1
    check listings[0].name == "PROGRAM"
    check decodeZxSpectrumBasic(listings[0].data) == " 10 PAUSE 1"
    check tree.leafResources.len == 1
    check tree.leafResources[0].path == ZxSpectrumBasicResourcePath
    check tree.leafResources[0].text == " 10 PAUSE 1"

  test "one CODE screen is detected and exposed as /screen":
    let tap = screenRecord("SCREEN", 0x5a)
    let candidates = detectFormats("display.TAP", tap)
    check ZxSpectrumTapTypeId == "zx-spectrum.tap"
    check candidates.len == 1
    check candidates[0].typeId == ZxSpectrumTapTypeId
    check candidates[0].confidence == vdcProbable
    check candidates[0].evidence.len == 2
    let resources = inspectSource("display.TAP", tap).resources.rasterResources
    check resources.len == 1
    check resources[0].path == "/screen"
    check extractZxSpectrumTapScreen(tap, "/screen") ==
      newSeqWith(ZxSpectrumScreenSize, 0x5a'u8)

  test "multiple CODE screens receive numbered paths":
    let tap = screenRecord("FIRST", 1) & screenRecord("SECOND", 2)
    check zxSpectrumTapScreenPaths(tap) == @["/screen/1", "/screen/2"]
    let tree = inspectSource("screens.tap", tap).resources
    check tree.roots.len == 1
    check tree.roots[0].kind == vrnkGroup
    check tree.roots[0].children.len == 2
    check extractZxSpectrumTapScreen(tap, "/screen/1")[0] == 1
    check extractZxSpectrumTapScreen(tap, "/screen/2")[0] == 2
    expect ValueError:
      discard extractZxSpectrumTapScreen(tap, "/screen")

  test "only CODE records with the screen address and length qualify":
    let tap = tapHeader("OTHER", 4, 32768) &
      tapBlock(ZxSpectrumTapDataFlag, @[1'u8, 2, 3, 4])
    check isZxSpectrumTap(tap)
    check zxSpectrumTapScreenPaths(tap).len == 0
    check inspectSource("other.tap", tap).resources.roots.len == 0

  test "bad checksums, truncation, and mismatched lengths are rejected":
    var badChecksum = screenRecord("BAD", 0)
    badChecksum[^1] = badChecksum[^1] xor 1
    check not isZxSpectrumTap(badChecksum)

    let truncated = screenRecord("SHORT", 0)[0 .. ^2]
    check not isZxSpectrumTap(truncated)

    let mismatched = tapHeader("WRONG", ZxSpectrumScreenSize,
      ZxSpectrumTapScreenAddress) &
      tapBlock(ZxSpectrumTapDataFlag, @[0'u8])
    check not isZxSpectrumTap(mismatched)

  test "a header must be immediately followed by its data block":
    let headerOnly = tapHeader("MISSING", ZxSpectrumScreenSize,
      ZxSpectrumTapScreenAddress)
    check not isZxSpectrumTap(headerOnly)
