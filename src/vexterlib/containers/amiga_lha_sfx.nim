## Amiga Hunk executables with appended LHA self-extractor payloads.

import ./[amiga_hunk_executable, lha_archive]

const AmigaLhaSfxTypeId* = "amiga.lha-sfx"

type AmigaLhaSfx* = object
  executable*: AmigaHunkExecutable
  usageArchive*: LhaArchive
  archive*: LhaArchive

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc parseAmigaLhaSfx*(data: openArray[byte]): AmigaLhaSfx =
  result.executable = parseAmigaHunkExecutable(data)
  let usageOffset = result.executable.executableLength
  if usageOffset > data.len - 24 or data[usageOffset + 20] != 0:
    raise newException(ValueError, "Amiga executable has no level-0 LHA SFX record")
  let usageEnd = usageOffset + int(data[usageOffset]) + 2 +
    int(leDword(data, usageOffset + 7))
  if usageEnd >= data.len:
    raise newException(ValueError, "truncated Amiga LHA SFX usage record")
  var archiveOffset = usageEnd
  while archiveOffset < data.len and data[archiveOffset] == 0:
    inc archiveOffset
  if archiveOffset == usageEnd or archiveOffset >= data.len:
    raise newException(ValueError, "Amiga LHA SFX main archive was not found")
  var usageBytes: seq[byte]
  usageBytes.add data.toOpenArray(usageOffset, archiveOffset - 1)
  result.usageArchive = parseLhaArchive(usageBytes)
  result.archive = parseLhaArchive(data.toOpenArray(archiveOffset, data.high))

proc isAmigaLhaSfx*(data: openArray[byte]): bool =
  try:
    discard parseAmigaLhaSfx(data)
    true
  except ValueError:
    false
