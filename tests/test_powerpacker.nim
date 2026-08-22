import std/[os, unittest]
import vexterlib

const LemmingsFixturePath = "Lemmings Inspiration.anim"

proc readBytes(path: string): seq[byte] =
  for value in readFile(path): result.add byte(value)

proc appendLong(data: var seq[byte], value: uint32) =
  data.add byte(value shr 24)
  data.add byte(value shr 16)
  data.add byte(value shr 8)
  data.add byte(value)

proc appendValueBits(bits: var seq[int], value, count: int) =
  for index in countdown(count - 1, 0):
    bits.add (value shr index) and 1

proc literalPowerPacker(raw: openArray[byte]): seq[byte] =
  var bits = @[0] # literal operation
  var remaining = raw.len - 1
  while remaining >= 3:
    bits.appendValueBits(3, 2)
    remaining -= 3
  bits.appendValueBits(remaining, 2)
  for index in countdown(raw.high, 0):
    bits.appendValueBits(int(raw[index]), 8)

  let
    firstLength = if bits.len mod 32 == 0: 32 else: bits.len mod 32
    startShift = 32 - firstLength
  var words: seq[uint32]
  var position = 0
  while position < bits.len:
    let
      length = if position == 0: firstLength else: 32
      shift = if position == 0: startShift else: 0
    var word: uint32
    for index in 0 ..< length:
      word = word or (uint32(bits[position + index]) shl (shift + index))
    words.add word
    position += length

  for value in "PP20": result.add byte(value)
  result.appendLong(0x090a0b0b)
  for index in countdown(words.high, 0): result.appendLong(words[index])
  result.appendLong((uint32(raw.len) shl 8) or uint32(startShift))

proc genericIff(): seq[byte] =
  for value in "FORM": result.add byte(value)
  result.appendLong(12)
  for value in "TESTDATA": result.add byte(value)
  result.appendLong(0)

suite "PowerPacker":
  test "literal PP20 streams unwrap into recursively inspected content":
    let
      raw = genericIff()
      packed = literalPowerPacker(raw)
      archive = parsePowerPacker(packed)
      candidates = detectFormats("wrapped.pp", packed)
      inspection = inspectSource("wrapped.pp", packed)
    check archive.version == "PP20"
    check archive.modeTable == [9, 10, 11, 11]
    check unpackPowerPacker(archive) == raw
    var pp11 = packed
    pp11[2] = byte('1')
    pp11[3] = byte('1')
    check unpackPowerPacker(pp11) == raw
    check candidates.len == 1
    check candidates[0].typeId == PowerPackerTypeId
    check inspection.resources.roots[0].path == "/content"
    check inspection.resources.roots[0].typeId == AmigaIffTypeId

  test "Lemmings PowerPacker stream opens its eight-frame ANIM":
    if fileExists(LemmingsFixturePath):
      let
        packed = readBytes(LemmingsFixturePath)
        archive = parsePowerPacker(packed)
        unpacked = unpackPowerPacker(archive)
        parsedAnim = parseAmigaAnim(unpacked)
        inspection = inspectSource(LemmingsFixturePath, packed)
        raster = inspection.resources.rasterResources[0].raster
      check archive.unpackedSize == 36598
      check unpacked[0 .. 3] ==
        @[byte('F'), byte('O'), byte('R'), byte('M')]
      check inspection.selectedFormat.typeId == PowerPackerTypeId
      check raster.width == 320
      check raster.height == 256
      check parsedAnim.hasDpan
      check parsedAnim.dpanVersion == 3
      check parsedAnim.logicalFrameCount == 8
      check parsedAnim.framesPerSecond == 10
      check raster.animation.frames.len == 8
      for frame in raster.animation.frames:
        check frame.durationMs == 100

  test "unknown efficiency tables and invalid shifts are rejected":
    let packed = literalPowerPacker(genericIff())
    var badMode = packed
    badMode[4] = 8
    check not isPowerPacker(badMode)
    var badShift = packed
    badShift[^1] = 32
    check not isPowerPacker(badShift)
