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
    check tree.leafResources[0].metadata[0].key == "tap.name"
    check tree.leafResources[0].metadata[1].key ==
      "basic.variable-area-offset"
    check tree.leafResources[0].metadata[1].value.integerValue == program.len
    check tree.leafResources[0].metadata[2].key == "basic.autostart-line"
    check tree.leafResources[0].metadata[2].value.integerValue == 10

  test "Program records without autostart omit autostart metadata":
    let
      program = basicLine(10, @[0xea'u8])
      tap = tapHeader("MANUAL", program.len, 32768,
        kind = ZxSpectrumTapProgramType, parameter2 = program.len) &
        tapBlock(ZxSpectrumTapDataFlag, program)
      resource = inspectSource("manual.tap", tap).resources.leafResources[0]
    check resource.metadata.len == 2
    check resource.metadata[0].key == "tap.name"
    check resource.metadata[1].key == "basic.variable-area-offset"
    check resource.metadata[1].value.integerValue == program.len

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
    check tree.roots.len == 2
    check tree.roots[0].path == "/screen/1"
    check tree.roots[1].path == "/screen/2"
    check extractZxSpectrumTapScreen(tap, "/screen/1")[0] == 1
    check extractZxSpectrumTapScreen(tap, "/screen/2")[0] == 2
    expect ValueError:
      discard extractZxSpectrumTapScreen(tap, "/screen")

  test "non-screen CODE records are exposed as opaque resources":
    let tap = tapHeader("OTHER", 4, 32768) &
      tapBlock(ZxSpectrumTapDataFlag, @[1'u8, 2, 3, 4])
    let codeBlocks = parseZxSpectrumTapCode(tap)
    check isZxSpectrumTap(tap)
    check zxSpectrumTapScreenPaths(tap).len == 0
    check codeBlocks.len == 1
    check codeBlocks[0].name == "OTHER"
    check codeBlocks[0].startAddress == 32768
    check codeBlocks[0].declaredLength == 4
    let tree = inspectSource("other.tap", tap).resources
    let resources = tree.leafResources
    check resources.len == 1
    check resources[0].path == ZxSpectrumTapCodeResourcePath
    check resources[0].typeId == ZxSpectrumTapCodeTypeId
    check resources[0].kind == vrnkOpaque
    check resources[0].rawDataAvailable
    check resources[0].data == @[1'u8, 2, 3, 4]
    check resources[0].metadata[0].key == "tap.name"
    check resources[0].metadata[0].value.stringValue == "OTHER"
    check resources[0].metadata[1].key == "code.start-address"
    check resources[0].metadata[1].value.integerValue == 32768
    check resources[0].metadata[2].key == "code.length"
    check resources[0].metadata[2].value.integerValue == 4
    let exported = exportResource(tree, VextExportRequest(
      resourcePath: ZxSpectrumTapCodeResourcePath,
      suggestedName: "other"))
    check exported.outputFormat == "bin"
    check exported.artifacts.artifacts[0].suggestedFilename == "other.bin"
    check exported.artifacts.artifacts[0].data == @[1'u8, 2, 3, 4]

  test "screens and ordinary CODE records use separate pathways":
    let tap = screenRecord("DISPLAY", 3) &
      tapHeader("MACHINE", 3, 40000) &
      tapBlock(ZxSpectrumTapDataFlag, @[0xaa'u8, 0xbb, 0xcc])
    let tree = inspectSource("mixed.tap", tap).resources
    check tree.leafResources.len == 2
    check tree.leafResources[0].path == ZxSpectrumScreenResourcePath
    check tree.leafResources[1].path == ZxSpectrumTapCodeResourcePath
    check tree.leafResources[1].data == @[0xaa'u8, 0xbb, 0xcc]

  test "screen recognition ignores the unused second CODE parameter":
    let tap = tapHeader("DISPLAY", ZxSpectrumScreenSize,
      ZxSpectrumTapScreenAddress, parameter2 = 32771) &
      tapBlock(ZxSpectrumTapDataFlag,
        newSeqWith(ZxSpectrumScreenSize, 0x5a'u8))
    let tree = inspectSource("display.tap", tap).resources
    check tree.roots.len == 1
    check tree.roots[0].path == ZxSpectrumScreenResourcePath
    check tree.roots[0].kind == vrnkRaster

  test "multiple ordinary CODE records receive numbered paths":
    let tap = tapHeader("FIRST", 1, 30000) &
      tapBlock(ZxSpectrumTapDataFlag, @[1'u8]) &
      tapHeader("SECOND", 2, 31000) &
      tapBlock(ZxSpectrumTapDataFlag, @[2'u8, 3])
    let tree = inspectSource("code.tap", tap).resources
    check tree.roots.len == 2
    check tree.roots[0].path == "/code/1"
    check tree.roots[1].path == "/code/2"

  test "resource roots retain physical tape order":
    let
      program = basicLine(10, @[0xea'u8])
      tap = tapHeader("LOADER", program.len, 10,
        kind = ZxSpectrumTapProgramType, parameter2 = program.len) &
        tapBlock(ZxSpectrumTapDataFlag, program) &
        screenRecord("DISPLAY", 0) &
        tapHeader("MACHINE", 2, 33161) &
        tapBlock(ZxSpectrumTapDataFlag, @[1'u8, 2])
      tree = inspectSource("ordered.tap", tap).resources
    check tree.roots.len == 3
    check tree.roots[0].path == ZxSpectrumBasicResourcePath
    check tree.roots[1].path == ZxSpectrumScreenResourcePath
    check tree.roots[2].path == ZxSpectrumTapCodeResourcePath

  test "number and character arrays are ordered opaque resources":
    let tap = tapHeader("NUMBERS", 3, 0x8100,
      kind = ZxSpectrumTapNumberArrayType, parameter2 = 0) &
      tapBlock(ZxSpectrumTapDataFlag, @[1'u8, 2, 3]) &
      tapHeader("LETTERS", 2, 0xc200,
        kind = ZxSpectrumTapCharacterArrayType, parameter2 = 0) &
      tapBlock(ZxSpectrumTapDataFlag, @[byte('A'), byte('B')])
    let tree = inspectSource("arrays.tap", tap).resources
    check tree.roots.len == 2
    check tree.roots[0].path == ZxSpectrumTapNumberArrayResourcePath
    check tree.roots[0].typeId == ZxSpectrumTapNumberArrayTypeId
    check tree.roots[0].kind == vrnkOpaque
    check tree.roots[0].rawDataAvailable
    check tree.roots[0].data == @[1'u8, 2, 3]
    check tree.roots[1].path == ZxSpectrumTapCharacterArrayResourcePath
    check tree.roots[1].typeId == ZxSpectrumTapCharacterArrayTypeId
    check tree.roots[1].kind == vrnkOpaque
    check tree.roots[1].rawDataAvailable
    check tree.roots[1].data == @[byte('A'), byte('B')]
    check exportResource(tree, VextExportRequest(
      resourcePath: ZxSpectrumTapNumberArrayResourcePath,
      suggestedName: "numbers")).artifacts.artifacts[0].data ==
      @[1'u8, 2, 3]

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
