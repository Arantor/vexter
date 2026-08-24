## Read-only parsing for single-volume ZIP archives.

import std/[strutils, unicode]

const
  ZipArchiveTypeId* = "archive.zip"
  ZipDirectoryTypeId* = "archive.zip-directory"
  ZipFileTypeId* = "archive.zip-file"
  ZipMaximumNameCharacters* = 255

type
  ZipEntry* = object
    name*: string
    segments*: seq[string]
    isDirectory*: bool
    compressionMethod*: int
    localHeaderOffset*: int
    payloadOffset*: int
    utf8Name*: bool
    compressedSize*: int
    uncompressedSize*: int
    expectedCrc*: uint32

  ZipArchive* = object
    comment*: string
    entries*: seq[ZipEntry]

  ZStream = object
    nextIn: ptr byte
    availIn: uint32
    totalIn: culong
    nextOut: ptr byte
    availOut: uint32
    totalOut: culong
    msg: cstring
    state: pointer
    zalloc: pointer
    zfree: pointer
    opaque: pointer
    dataType: cint
    adler: culong
    reserved: culong

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
elif defined(macosx):
  const ZlibLibrary = "libz.dylib"
else:
  const ZlibLibrary = "libz.so(|.1)"

proc zlibVersion(): cstring {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateInit2(stream: ptr ZStream, windowBits: cint, version: cstring,
    streamSize: cint): cint {.cdecl, importc: "inflateInit2_", dynlib: ZlibLibrary.}
proc inflate(stream: ptr ZStream, flush: cint): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}
proc inflateEnd(stream: ptr ZStream): cint
    {.cdecl, importc, dynlib: ZlibLibrary.}

proc leWord(data: openArray[byte], offset: int): uint16 {.inline.} =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

proc rawInflate(source: openArray[byte], expectedSize: int): seq[byte] =
  result = newSeq[byte](expectedSize)
  var stream: ZStream
  if source.len > 0:
    stream.nextIn = unsafeAddr source[0]
  stream.availIn = uint32(source.len)
  if result.len > 0:
    stream.nextOut = addr result[0]
  stream.availOut = uint32(result.len)
  if inflateInit2(addr stream, -15, zlibVersion(), cint(sizeof(ZStream))) != 0:
    raise newException(ValueError, "could not initialize ZIP DEFLATE decoder")
  let status = inflate(addr stream, 4)
  discard inflateEnd(addr stream)
  if status != 1 or int(stream.totalOut) != expectedSize or stream.availIn != 0:
    raise newException(ValueError, "invalid or truncated ZIP DEFLATE data")

proc decodeName(data: openArray[byte]): string =
  ## ZIP's legacy encoding is CP437. ASCII is preserved exactly; the complete
  ## upper half is mapped to Unicode so archive names never depend on the host.
  const cp437 = [
    0x00c7, 0x00fc, 0x00e9, 0x00e2, 0x00e4, 0x00e0, 0x00e5, 0x00e7,
    0x00ea, 0x00eb, 0x00e8, 0x00ef, 0x00ee, 0x00ec, 0x00c4, 0x00c5,
    0x00c9, 0x00e6, 0x00c6, 0x00f4, 0x00f6, 0x00f2, 0x00fb, 0x00f9,
    0x00ff, 0x00d6, 0x00dc, 0x00a2, 0x00a3, 0x00a5, 0x20a7, 0x0192,
    0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba,
    0x00bf, 0x2310, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510,
    0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f,
    0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b,
    0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580,
    0x03b1, 0x00df, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0x00b5, 0x03c4,
    0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229,
    0x2261, 0x00b1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00f7, 0x2248,
    0x00b0, 0x2219, 0x00b7, 0x221a, 0x207f, 0x00b2, 0x25a0, 0x00a0]
  for value in data:
    if value < 0x80:
      result.add char(value)
    else:
      result.add toUTF8(Rune(cp437[int(value) - 0x80]))

proc validatedSegments(name: string, directory: bool): seq[string] =
  var canonical = name.replace('\\', '/')
  if canonical.len == 0 or canonical[0] == '/':
    raise newException(ValueError, "invalid absolute or empty ZIP entry name")
  if directory and canonical.endsWith('/'):
    canonical.setLen(canonical.len - 1)
  for segment in canonical.split('/'):
    if segment.len == 0 or segment in [".", ".."]:
      raise newException(ValueError, "cyclic or ambiguous ZIP entry path: " & name)
    result.add segment

proc parseZipArchive*(data: openArray[byte]): ZipArchive =
  if data.len < 22:
    raise newException(ValueError, "ZIP archive is too short")
  var eocd = -1
  let firstPossible = max(0, data.len - 22 - 65535)
  for offset in countdown(data.len - 22, firstPossible):
    if leDword(data, offset) == 0x06054b50'u32 and
        offset + 22 + int(leWord(data, offset + 20)) == data.len:
      eocd = offset
      break
  if eocd < 0:
    raise newException(ValueError, "ZIP end-of-central-directory record was not found")
  if leWord(data, eocd + 4) != 0 or leWord(data, eocd + 6) != 0 or
      leWord(data, eocd + 8) != leWord(data, eocd + 10):
    raise newException(ValueError, "multi-volume ZIP archives are not supported")
  let entryCount = int(leWord(data, eocd + 10))
  let centralSize = int(leDword(data, eocd + 12))
  let centralOffset = int(leDword(data, eocd + 16))
  if entryCount == 0xffff or centralSize == int(0xffffffff'u32) or
      centralOffset == int(0xffffffff'u32):
    raise newException(ValueError, "ZIP64 archives are not supported")
  if centralOffset < 0 or centralSize < 0 or
      centralOffset + centralSize != eocd:
    raise newException(ValueError, "invalid ZIP central-directory bounds")
  let commentLength = int(leWord(data, eocd + 20))
  if commentLength > 0:
    result.comment = decodeName(data.toOpenArray(eocd + 22, data.high))

  var offset = centralOffset
  var names: seq[string]
  for index in 0 ..< entryCount:
    if offset + 46 > eocd or leDword(data, offset) != 0x02014b50'u32:
      raise newException(ValueError, "invalid ZIP central-directory entry")
    let flags = int(leWord(data, offset + 8))
    let compression = int(leWord(data, offset + 10))
    let expectedCrc = leDword(data, offset + 16)
    let compressedSize = int(leDword(data, offset + 20))
    let uncompressedSize = int(leDword(data, offset + 24))
    let nameLength = int(leWord(data, offset + 28))
    let extraLength = int(leWord(data, offset + 30))
    let entryCommentLength = int(leWord(data, offset + 32))
    let disk = leWord(data, offset + 34)
    let localOffset = int(leDword(data, offset + 42))
    let nextOffset = offset + 46 + nameLength + extraLength + entryCommentLength
    if nameLength == 0 or nextOffset > eocd:
      raise newException(ValueError, "invalid ZIP central-directory entry length")
    if disk != 0:
      raise newException(ValueError, "multi-volume ZIP archives are not supported")
    if compressedSize == int(0xffffffff'u32) or
        uncompressedSize == int(0xffffffff'u32) or
        localOffset == int(0xffffffff'u32):
      raise newException(ValueError, "ZIP64 entries are not supported")
    if (flags and 1) != 0:
      raise newException(ValueError, "encrypted ZIP entries are not supported")
    if compression notin [0, 8]:
      raise newException(ValueError, "unsupported ZIP compression method: " & $compression)
    var rawName: seq[byte]
    rawName.add data.toOpenArray(offset + 46, offset + 45 + nameLength)
    var name: string
    if (flags and 0x800) != 0:
      for value in rawName: name.add char(value)
      if validateUtf8(name) != -1:
        raise newException(ValueError, "invalid UTF-8 ZIP entry name")
    else:
      name = decodeName(rawName)
    if runeLen(name) > ZipMaximumNameCharacters:
      raise newException(ValueError, "ZIP entry name exceeds 255 characters")
    let directory = name.endsWith('/') or name.endsWith('\\')
    let segments = validatedSegments(name, directory)
    let canonical = segments.join("/")
    if canonical in names:
      raise newException(ValueError, "duplicate ZIP entry path: " & canonical)
    names.add canonical
    if localOffset < 0 or localOffset + 30 > centralOffset or
        leDword(data, localOffset) != 0x04034b50'u32:
      raise newException(ValueError, "invalid ZIP local-file header")
    if int(leWord(data, localOffset + 6)) != flags or
        int(leWord(data, localOffset + 8)) != compression:
      raise newException(ValueError, "ZIP local and central headers disagree")
    let localNameLength = int(leWord(data, localOffset + 26))
    let localExtraLength = int(leWord(data, localOffset + 28))
    let payloadOffset = localOffset + 30 + localNameLength + localExtraLength
    if payloadOffset < 0 or compressedSize < 0 or
        payloadOffset + compressedSize > centralOffset:
      raise newException(ValueError, "invalid ZIP entry data bounds")
    if localNameLength != nameLength:
      raise newException(ValueError, "ZIP local and central names disagree")
    for nameIndex in 0 ..< nameLength:
      if data[localOffset + 30 + nameIndex] != rawName[nameIndex]:
        raise newException(ValueError, "ZIP local and central names disagree")
    if directory and (compressedSize != 0 or uncompressedSize != 0):
      raise newException(ValueError, "ZIP directory entry contains file data")
    if not directory and compression == 0 and compressedSize != uncompressedSize:
      raise newException(ValueError, "invalid stored ZIP entry size")
    result.entries.add ZipEntry(name: canonical, segments: segments,
      isDirectory: directory, compressionMethod: compression,
      localHeaderOffset: localOffset, payloadOffset: payloadOffset,
      utf8Name: (flags and 0x800) != 0, expectedCrc: expectedCrc,
      compressedSize: compressedSize, uncompressedSize: uncompressedSize,
    )
    offset = nextOffset
  if offset != eocd:
    raise newException(ValueError, "ZIP central-directory size does not match its entries")

proc extractZipEntry*(data: openArray[byte], entry: ZipEntry): seq[byte] =
  ## Expands and verifies one already structurally indexed member.
  if entry.isDirectory:
    raise newException(ValueError, "cannot extract a ZIP directory")
  if entry.payloadOffset < 0 or entry.compressedSize < 0 or
      entry.payloadOffset > data.len - entry.compressedSize:
    raise newException(ValueError, "ZIP entry data is outside its source")
  if entry.compressionMethod == 0:
    result = newSeq[byte](entry.uncompressedSize)
    for index in 0 ..< result.len:
      result[index] = data[entry.payloadOffset + index]
  elif entry.compressionMethod == 8:
    if entry.compressedSize == 0:
      result = rawInflate([], entry.uncompressedSize)
    else:
      result = rawInflate(data.toOpenArray(entry.payloadOffset,
        entry.payloadOffset + entry.compressedSize - 1), entry.uncompressedSize)
  else:
    raise newException(ValueError,
      "unsupported ZIP compression method: " & $entry.compressionMethod)
  if crc32(result) != entry.expectedCrc:
    raise newException(ValueError, "ZIP entry CRC-32 does not match: " & entry.name)

proc isZipArchive*(data: openArray[byte]): bool =
  try:
    discard parseZipArchive(data)
    true
  except ValueError:
    false

proc hasZipExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".zip")

proc normalizedZipExportName*(name: string): string =
  ## Produces one conservative filename that is usable on mainstream host
  ## filesystems. Bulk export can apply collision suffixes after this step.
  const reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3",
    "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2",
    "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
  for value in name:
    if ord(value) < 32 or value in {'<', '>', ':', '"', '/', '\\', '|', '?', '*'}:
      result.add '_'
    else:
      result.add value
  while result.len > 0 and result[^1] in {' ', '.'}:
    result.setLen(result.len - 1)
  if result.len == 0:
    result = "_"
  let stem = result.split('.')[0].toUpperAscii
  if stem in reserved:
    result = "_" & result
