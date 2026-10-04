import std/unittest
import vexterlib

suite "shared detection input":
  test "initial and requested windows are cached":
    let data = newSeq[byte](256)
    var reads: seq[tuple[offset, amount: int]]
    let source = newByteSource(data.len,
      proc(offset, amount: int): seq[byte] =
        reads.add (offset, amount)
        data[offset ..< offset + amount])
    let input = newDetectionInput("unknown.bin", source, 1024,
      trailingBytes = 64)
    check reads == @[(0, 11), (192, 64)]

    discard input.readWindow(2, 4)
    discard input.readWindow(100, 12)
    discard input.readWindow(103, 4)
    check reads == @[(0, 11), (192, 64), (100, 12)]

    discard input.completeBytes()
    discard input.completeBytes()
    check reads == @[(0, 11), (192, 64), (100, 12), (0, 256)]

  test "all byte-backed detectors consume the shared complete cache":
    let data = newSeq[byte](ZxSpectrumScreenSize)
    var reads = 0
    let source = newByteSource(data.len,
      proc(offset, amount: int): seq[byte] =
        inc reads
        data[offset ..< offset + amount])
    let input = newDetectionInput("display.scr", source, data.len)
    let initialReads = reads
    let first = input.detectFormats()
    require first.len > 0
    check first[0].typeId == ZxSpectrumScreenDumpTypeId
    check reads == initialReads + 1
    let second = input.detectFormats()
    check second[0].typeId == ZxSpectrumScreenDumpTypeId
    check reads == initialReads + 1

  test "complete materialization observes the detection limit":
    let source = memoryByteSource(newSeq[byte](65))
    let input = newDetectionInput("unknown.bin", source, 32)
    expect ValueError:
      discard input.completeBytes()
