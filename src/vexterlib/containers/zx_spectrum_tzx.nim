## Structural parser for Spectrum TZX tape images.
##
## Standard-speed data blocks are promoted through the TAP record decoder.
## Other currently known blocks are bounded and skipped; waveform replay and
## TZX control-flow interpretation are intentionally deferred.

import ./zx_spectrum_tap

const
  ZxSpectrumTzxTypeId* = "zx-spectrum.tzx"
  ZxSpectrumTzxSignature* = [byte('Z'), byte('X'), byte('T'), byte('a'),
    byte('p'), byte('e'), byte('!'), 0x1a'u8]

type
  ZxSpectrumTzx* = object
    majorVersion*: int
    minorVersion*: int
    records*: seq[ZxSpectrumTapRecord]
    blockCount*: int
    standardDataBlockCount*: int

proc wordAt(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc tripleAt(data: openArray[byte], offset: int): int {.inline.} =
  wordAt(data, offset) or (int(data[offset + 2]) shl 16)

proc dwordAt(data: openArray[byte], offset: int): int64 {.inline.} =
  int64(data[offset]) or (int64(data[offset + 1]) shl 8) or
    (int64(data[offset + 2]) shl 16) or (int64(data[offset + 3]) shl 24)

proc parseZxSpectrumTzx*(data: openArray[byte]): ZxSpectrumTzx =
  if data.len < 10:
    raise newException(ValueError, "truncated ZX Spectrum TZX header")
  for index, value in ZxSpectrumTzxSignature:
    if data[index] != value:
      raise newException(ValueError, "invalid ZX Spectrum TZX signature")
  if data[8] != 1:
    raise newException(ValueError, "unsupported ZX Spectrum TZX major version")
  result.majorVersion = int(data[8])
  result.minorVersion = int(data[9])

  var offset = 10
  var standardBlocks: seq[seq[byte]]
  template flushStandardBlocks() =
    if standardBlocks.len > 0:
      result.records.add parseZxSpectrumTapeBlocks(standardBlocks)
      standardBlocks.setLen(0)
  while offset < data.len:
    let id = data[offset]
    inc offset
    let remaining = data.len - offset
    var payloadLength: int64
    case id
    of 0x10:
      if remaining < 4: raise newException(ValueError, "truncated TZX standard-speed data block")
      payloadLength = int64(4 + wordAt(data, offset + 2))
    of 0x11:
      if remaining < 18: raise newException(ValueError, "truncated TZX turbo-speed data block")
      payloadLength = int64(18 + tripleAt(data, offset + 15))
    of 0x12: payloadLength = 4
    of 0x13:
      if remaining < 1: raise newException(ValueError, "truncated TZX pulse sequence")
      payloadLength = int64(1 + int(data[offset]) * 2)
    of 0x14:
      if remaining < 10: raise newException(ValueError, "truncated TZX pure-data block")
      payloadLength = int64(10 + tripleAt(data, offset + 7))
    of 0x15:
      if remaining < 8: raise newException(ValueError, "truncated TZX direct-recording block")
      payloadLength = int64(8 + tripleAt(data, offset + 5))
    of 0x18, 0x19:
      if remaining < 4: raise newException(ValueError, "truncated length-prefixed TZX block")
      payloadLength = 4 + dwordAt(data, offset)
    of 0x20, 0x23, 0x24: payloadLength = 2
    of 0x21, 0x30:
      if remaining < 1: raise newException(ValueError, "truncated byte-length TZX block")
      payloadLength = int64(1 + int(data[offset]))
    of 0x22, 0x25, 0x27: payloadLength = 0
    of 0x26:
      if remaining < 2: raise newException(ValueError, "truncated TZX call sequence")
      payloadLength = int64(2 + wordAt(data, offset) * 2)
    of 0x28, 0x32:
      if remaining < 2: raise newException(ValueError, "truncated word-length TZX block")
      payloadLength = int64(2 + wordAt(data, offset))
    of 0x2a, 0x2b:
      if remaining < 4: raise newException(ValueError, "truncated dword-length TZX block")
      payloadLength = 4 + dwordAt(data, offset)
    of 0x31:
      if remaining < 2: raise newException(ValueError, "truncated TZX message block")
      payloadLength = int64(2 + int(data[offset + 1]))
    of 0x33:
      if remaining < 1: raise newException(ValueError, "truncated TZX hardware block")
      payloadLength = int64(1 + int(data[offset]) * 3)
    of 0x35:
      if remaining < 20: raise newException(ValueError, "truncated TZX custom-info block")
      payloadLength = 20 + dwordAt(data, offset + 16)
    of 0x5a: payloadLength = 9
    else:
      raise newException(ValueError, "unsupported ZX Spectrum TZX block ID")

    if payloadLength < 0 or payloadLength > int64(remaining):
      raise newException(ValueError, "truncated ZX Spectrum TZX block")
    let length = int(payloadLength)
    if id == 0x10:
      let tapeLength = wordAt(data, offset + 2)
      standardBlocks.add @data[offset + 4 ..< offset + 4 + tapeLength]
      inc result.standardDataBlockCount
    else:
      flushStandardBlocks()
    offset += length
    inc result.blockCount

  if result.blockCount == 0:
    raise newException(ValueError, "ZX Spectrum TZX contains no blocks")
  flushStandardBlocks()

proc isZxSpectrumTzx*(data: openArray[byte]): bool =
  try:
    discard parseZxSpectrumTzx(data)
    true
  except ValueError:
    false
