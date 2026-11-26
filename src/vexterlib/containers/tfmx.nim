## TFMX MDAT structure. Informed only by the supplied Pickard document and
## TFMX_v1.6/source/rout.tfmx7v_sid.s (see docs/tfmx.md).
import std/strutils

const TfmxTypeId* = "tfmx.song"
type
  TfmxSong* = object
    index*, first*, last*, tempo*: int
  TfmxModule* = object
    data*: seq[byte]
    text*: string
    trackOffset*, patternOffset*, macroOffset*: int
    songs*: seq[TfmxSong]

proc word*(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 2:
    raise newException(ValueError, "TFMX word outside music data")
  int(data[offset]) shl 8 or int(data[offset + 1])

proc longword*(data: openArray[byte], offset: int): int =
  let value = uint32(data.word(offset)) shl 16 or uint32(data.word(offset + 2))
  if uint64(value) > uint64(high(int)):
    raise newException(ValueError, "TFMX offset outside host range")
  int(value)

proc pointer*(module: TfmxModule, macros: bool, index: int): int =
  if index < 0 or index >= 128:
    raise newException(ValueError, "TFMX program number outside pointer table")
  let table = if macros: module.macroOffset else: module.patternOffset
  result = module.data.longword(table + index * 4)
  if result < 0x200 or result > module.data.len - 4 or result mod 4 != 0:
    raise newException(ValueError, "TFMX program pointer outside music data")

proc parseTfmx*(data: openArray[byte]): TfmxModule =
  if data.len < 0x200:
    raise newException(ValueError, "truncated TFMX header")
  for i, c in "TFMX-SONG ":
    if data[i] != byte(c):
      raise newException(ValueError, "invalid TFMX signature")
  result.data = @data
  result.trackOffset = data.longword(0x1d0)
  result.patternOffset = data.longword(0x1d4)
  result.macroOffset = data.longword(0x1d8)
  if result.trackOffset == 0: result.trackOffset = 0x800
  if result.patternOffset == 0: result.patternOffset = 0x400
  if result.macroOffset == 0: result.macroOffset = 0x600
  for offset in [result.trackOffset, result.patternOffset, result.macroOffset]:
    if offset < 0x200 or offset > data.len - 4 or offset mod 4 != 0:
      raise newException(ValueError, "TFMX section outside music data")
  for line in 0 ..< 6:
    var text = ""
    for i in 0 ..< 40:
      let c = data[16 + line * 40 + i]
      text.add if c >= 32 and c < 127: char(c) else: ' '
    if result.text.len > 0: result.text.add '\n'
    result.text.add text.strip
  for i in 0 ..< 32:
    let first = data.word(0x100 + 2*i)
    let last = data.word(0x140 + 2*i)
    # Empty entries conventionally contain 0/0 and a default tempo. Slot 0
    # remains selectable even for a legitimate one-position song.
    if i > 0 and first == 0 and last == 0: continue
    if first > last: continue
    if last > (data.len - result.trackOffset) div 16 - 1:
      raise newException(ValueError, "TFMX song track range outside music data")
    result.songs.add TfmxSong(index: i, first: first, last: last,
      tempo: data.word(0x180 + 2*i))
  if result.songs.len == 0:
    raise newException(ValueError, "TFMX has no bounded song ranges")

proc isTfmx*(data: openArray[byte]): bool =
  try:
    discard parseTfmx(data)
    true
  except ValueError: false
