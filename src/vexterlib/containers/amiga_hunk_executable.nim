## Minimal structural parsing for Amiga load-file Hunk executables.

const
  AmigaHunkExecutableTypeId* = "amiga.hunk-executable"
  AmigaHunkCodeTypeId* = "amiga.hunk-code"
  AmigaHunkDataTypeId* = "amiga.hunk-data"
  AmigaHunkBssTypeId* = "amiga.hunk-bss"
  AmigaHunkOverlayTypeId* = "amiga.hunk-overlay"

  HunkCode = 1001'u32
  HunkData = 1002'u32
  HunkBss = 1003'u32
  HunkReloc32 = 1004'u32
  HunkReloc16 = 1005'u32
  HunkReloc8 = 1006'u32
  HunkSymbol = 1008'u32
  HunkDebug = 1009'u32
  HunkEnd = 1010'u32
  HunkHeader = 1011'u32
  HunkOverlay = 1013'u32

type
  AmigaHunkKind* = enum ahkCode, ahkData, ahkBss

  AmigaHunk* = object
    kind*: AmigaHunkKind
    memoryLongwords*: int
    data*: seq[byte]

  AmigaHunkExecutable* = object
    hunks*: seq[AmigaHunk]
    overlay*: seq[byte]
    executableLength*: int

proc beDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc takeDword(data: openArray[byte], offset: var int): uint32 =
  if offset > data.len - 4:
    raise newException(ValueError, "truncated Amiga Hunk executable")
  result = beDword(data, offset)
  offset += 4

proc skipLongwords(data: openArray[byte], offset: var int, count: uint32) =
  if uint64(count) * 4'u64 > uint64(data.len - offset):
    raise newException(ValueError, "truncated Amiga Hunk record")
  offset += int(count) * 4

proc parseAmigaHunkExecutable*(data: openArray[byte]): AmigaHunkExecutable =
  var offset = 0
  if data.len < 24 or data.takeDword(offset) != HunkHeader:
    raise newException(ValueError, "Amiga HUNK_HEADER was not found")
  var residentLength = data.takeDword(offset)
  while residentLength != 0:
    data.skipLongwords(offset, residentLength)
    residentLength = data.takeDword(offset)
  let tableSize = data.takeDword(offset)
  let firstHunk = data.takeDword(offset)
  let lastHunk = data.takeDword(offset)
  if lastHunk < firstHunk:
    raise newException(ValueError, "invalid Amiga Hunk table range")
  let hunkCount64 = uint64(lastHunk) - uint64(firstHunk) + 1
  if hunkCount64 > uint64(high(int)) or uint64(tableSize) < hunkCount64:
    raise newException(ValueError, "invalid Amiga Hunk table size")
  let hunkCount = int(hunkCount64)
  var memorySizes = newSeq[int](hunkCount)
  for index in 0 ..< hunkCount:
    memorySizes[index] = int(data.takeDword(offset) and 0x3fffffff'u32)

  var current = -1
  var ended = 0
  while ended < hunkCount:
    let identifier = data.takeDword(offset) and 0x3fffffff'u32
    case identifier
    of HunkCode, HunkData:
      inc current
      if current >= hunkCount:
        raise newException(ValueError, "too many loadable Amiga hunks")
      let length = data.takeDword(offset) and 0x3fffffff'u32
      if int(length) > memorySizes[current]:
        raise newException(ValueError, "Amiga Hunk data exceeds memory size")
      if uint64(length) * 4'u64 > uint64(data.len - offset):
        raise newException(ValueError, "truncated Amiga Hunk data")
      var payload: seq[byte]
      if length > 0:
        payload.add data.toOpenArray(offset, offset + int(length) * 4 - 1)
      offset += int(length) * 4
      result.hunks.add AmigaHunk(
        kind: if identifier == HunkCode: ahkCode else: ahkData,
        memoryLongwords: memorySizes[current], data: payload)
    of HunkBss:
      inc current
      if current >= hunkCount:
        raise newException(ValueError, "too many loadable Amiga hunks")
      let length = int(data.takeDword(offset) and 0x3fffffff'u32)
      if length != memorySizes[current]:
        raise newException(ValueError, "Amiga HUNK_BSS size disagrees with table")
      result.hunks.add AmigaHunk(kind: ahkBss,
        memoryLongwords: memorySizes[current])
    of HunkReloc32, HunkReloc16, HunkReloc8:
      var count = data.takeDword(offset)
      while count != 0:
        discard data.takeDword(offset) # target hunk
        data.skipLongwords(offset, count)
        count = data.takeDword(offset)
    of HunkSymbol:
      var nameLength = data.takeDword(offset)
      while nameLength != 0:
        data.skipLongwords(offset, nameLength)
        discard data.takeDword(offset)
        nameLength = data.takeDword(offset)
    of HunkDebug:
      data.skipLongwords(offset, data.takeDword(offset))
    of HunkEnd:
      inc ended
    else:
      raise newException(ValueError, "unsupported Amiga Hunk record: " &
        $identifier)
  if result.hunks.len != hunkCount:
    raise newException(ValueError, "Amiga Hunk table and records disagree")

  if offset <= data.len - 8 and
      (beDword(data, offset) and 0x3fffffff'u32) == HunkOverlay:
    offset += 4
    let length = data.takeDword(offset)
    if uint64(length) * 4'u64 > uint64(data.len - offset):
      raise newException(ValueError, "truncated Amiga HUNK_OVERLAY")
    if length > 0:
      result.overlay.add data.toOpenArray(offset,
        offset + int(length) * 4 - 1)
    offset += int(length) * 4
  result.executableLength = offset

proc isAmigaHunkExecutable*(data: openArray[byte]): bool =
  try:
    discard parseAmigaHunkExecutable(data)
    true
  except ValueError:
    false
