import std/[strutils, unittest]
import vexterlib/compression/lzma

proc hexBytes(value: string): seq[byte] =
  for index in countup(0, value.high, 2):
    result.add byte(parseHexInt(value[index .. index + 1]))

suite "raw LZMA1":
  test "literal and repeated-match stream with end marker":
    let packed = hexBytes("00341949ee8de94f7e21b620b7ffffba340000")
    let decoded = decodeRawLzma1(packed,
      RawLzmaProperties(lc: 3, lp: 0, pb: 2,
        dictionarySize: 64 * 1024), 1024)
    check cast[string](decoded) == "hello hello hello\n"

  test "declared-size decoding":
    let packed = hexBytes("002a1a08a2032566f14b78c5a205ff2ee6d9d2201aad34f8e21de84136fadc0669bb3ce410342709ebb366e3f3f4a661bffd51cc00")
    let decoded = decodeRawLzma1(packed,
      RawLzmaProperties(lc: 3, lp: 0, pb: 2,
        dictionarySize: 1024 * 1024), 100, 44)
    check cast[string](decoded) == "The quick brown fox jumps over the lazy dog."

  test "properties, truncation, and output limits are checked":
    expect ValueError:
      discard decodeRawLzma1(@[0'u8, 0, 0, 0, 0],
        RawLzmaProperties(lc: 9, dictionarySize: 1), 10)
    expect ValueError:
      discard decodeRawLzma1(hexBytes("00341949"),
        RawLzmaProperties(lc: 3, lp: 0, pb: 2,
          dictionarySize: 64 * 1024), 1024)
    expect ValueError:
      discard decodeRawLzma1(hexBytes("00341949ee8de94f7e21b620b7ffffba340000"),
        RawLzmaProperties(lc: 3, lp: 0, pb: 2,
          dictionarySize: 64 * 1024), 4)
