## Electron ASAR archive indexing and stored-member extraction.

import std/[json, sequtils, strutils, unicode]
import ../byte_sources

const
  ElectronAsarTypeId* = "archive.electron-asar"
  ElectronAsarDirectoryTypeId* = "archive.electron-asar-directory"
  ElectronAsarFileTypeId* = "archive.electron-asar-file"
  ElectronAsarMaximumNameCharacters* = 255

type
  ElectronAsarEntry* = object
    name*: string
    segments*: seq[string]
    isDirectory*: bool
    unpacked*: bool
    executable*: bool
    size*: int
    payloadOffset*: int
    integrityAlgorithm*: string
    integrityHash*: string
    integrityBlockSize*: int
    integrityBlocks*: int

  ElectronAsarArchive* = object
    entries*: seq[ElectronAsarEntry]
    headerSize*: int
    headerJsonSize*: int
    payloadOffset*: int

proc leDword(data: openArray[byte], offset: int): uint32 {.inline.} =
  uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
    (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)

proc decimalOffset(value, path: string): int =
  if value.len == 0:
    raise newException(ValueError, "empty ASAR file offset: " & path)
  var parsed = 0'u64
  for digit in value:
    if digit notin {'0' .. '9'}:
      raise newException(ValueError, "invalid ASAR file offset: " & path)
    let number = uint64(ord(digit) - ord('0'))
    if parsed > (high(uint64) - number) div 10:
      raise newException(ValueError, "ASAR file offset overflows UINT64: " & path)
    parsed = parsed * 10 + number
  if parsed > uint64(high(int)):
    raise newException(ValueError, "ASAR file offset exceeds host limits: " & path)
  int(parsed)

proc requiredObject(parent: JsonNode, key, context: string): JsonNode =
  if parent.kind != JObject or not parent.hasKey(key) or
      parent[key].kind != JObject:
    raise newException(ValueError, "ASAR " & context & " requires an object named " & key)
  parent[key]

proc optionalBool(node: JsonNode, key, path: string): bool =
  if not node.hasKey(key): return false
  if node[key].kind != JBool:
    raise newException(ValueError, "ASAR " & key & " must be boolean: " & path)
  node[key].getBool

proc validateName(name, path: string) =
  if name.len == 0 or name in [".", ".."] or '/' in name or '\\' in name:
    raise newException(ValueError, "invalid ASAR member name: " & path)
  if validateUtf8(name) != -1:
    raise newException(ValueError, "invalid UTF-8 ASAR member name: " & path)
  if runeLen(name) > ElectronAsarMaximumNameCharacters:
    raise newException(ValueError, "ASAR member name exceeds 255 characters: " & path)

proc parseIntegrity(node: JsonNode, entry: var ElectronAsarEntry,
    path: string) =
  if not node.hasKey("integrity"): return
  let integrity = node["integrity"]
  if integrity.kind != JObject:
    raise newException(ValueError, "ASAR integrity must be an object: " & path)
  for key in ["algorithm", "hash", "blockSize", "blocks"]:
    if not integrity.hasKey(key):
      raise newException(ValueError,
        "incomplete ASAR integrity metadata: " & path)
  if integrity["algorithm"].kind != JString:
    raise newException(ValueError, "invalid ASAR integrity algorithm: " & path)
  entry.integrityAlgorithm = integrity["algorithm"].getStr
  if entry.integrityAlgorithm != "SHA256":
    raise newException(ValueError, "unsupported ASAR integrity algorithm: " &
      entry.integrityAlgorithm)
  if integrity["hash"].kind != JString:
    raise newException(ValueError, "invalid ASAR integrity hash: " & path)
  entry.integrityHash = integrity["hash"].getStr
  if entry.integrityHash.len != 64 or
      entry.integrityHash.anyIt(it notin HexDigits):
    raise newException(ValueError, "invalid ASAR SHA256 hash: " & path)
  if integrity["blockSize"].kind != JInt or
      integrity["blockSize"].getBiggestInt <= 0 or
      integrity["blockSize"].getBiggestInt > high(int):
    raise newException(ValueError, "invalid ASAR integrity block size: " & path)
  entry.integrityBlockSize = int(integrity["blockSize"].getBiggestInt)
  if integrity["blocks"].kind != JArray:
    raise newException(ValueError, "invalid ASAR integrity blocks: " & path)
  for hash in integrity["blocks"]:
    if hash.kind != JString or hash.getStr.len != 64 or
        hash.getStr.anyIt(it notin HexDigits):
      raise newException(ValueError, "invalid ASAR integrity block hash: " & path)
  entry.integrityBlocks = integrity["blocks"].len
  let expectedBlocks = if entry.size == 0: 0
    else: (entry.size - 1) div entry.integrityBlockSize + 1
  if entry.integrityBlocks != expectedBlocks:
    raise newException(ValueError,
      "ASAR integrity block count does not match file size: " & path)

proc parseElectronAsarHeader(data: openArray[byte],
    totalLength: int): ElectronAsarArchive =
  if data.len < 20:
    raise newException(ValueError, "ASAR archive is too short")
  if leDword(data, 0) != 4:
    raise newException(ValueError, "invalid ASAR header-size Pickle")
  let headerSize = int(leDword(data, 4))
  if headerSize < 12 or (headerSize and 3) != 0 or
      headerSize > totalLength - 8 or headerSize > data.len - 8:
    raise newException(ValueError, "invalid ASAR header size")
  if int(leDword(data, 8)) != headerSize - 4:
    raise newException(ValueError, "invalid ASAR header Pickle size")
  let jsonSize = int(leDword(data, 12))
  if jsonSize <= 0 or jsonSize > headerSize - 9:
    raise newException(ValueError, "invalid ASAR JSON string size")
  let terminator = 16 + jsonSize
  if terminator >= 8 + headerSize or data[terminator] != 0:
    raise newException(ValueError, "ASAR JSON string is not NUL-terminated")
  for offset in terminator + 1 ..< 8 + headerSize:
    if data[offset] != 0:
      raise newException(ValueError, "ASAR header Pickle has non-zero padding")
  var jsonText = newString(jsonSize)
  for index in 0 ..< jsonSize: jsonText[index] = char(data[16 + index])
  let header = try: parseJson(jsonText)
    except JsonParsingError as error:
      raise newException(ValueError, "invalid ASAR JSON header: " & error.msg)
  let files = header.requiredObject("files", "header")
  var archive = ElectronAsarArchive(headerSize: headerSize,
    headerJsonSize: jsonSize, payloadOffset: 8 + headerSize)

  proc visit(children: JsonNode, segments: seq[string],
      inheritedUnpacked = false) =
    for name, node in children:
      let pathSegments = segments & @[name]
      let path = pathSegments.join("/")
      validateName(name, path)
      if node.kind != JObject:
        raise newException(ValueError, "ASAR member must be an object: " & path)
      if node.hasKey("files"):
        if node["files"].kind != JObject:
          raise newException(ValueError, "invalid ASAR directory entry: " & path)
        for key, unused in node:
          if key notin ["files", "unpacked"]:
            raise newException(ValueError,
              "unsupported ASAR directory field '" & key & "': " & path)
        let unpacked = inheritedUnpacked or node.optionalBool("unpacked", path)
        archive.entries.add ElectronAsarEntry(name: path,
          segments: pathSegments, isDirectory: true, unpacked: unpacked)
        visit(node["files"], pathSegments, unpacked)
      else:
        if not node.hasKey("size") or node["size"].kind != JInt or
            node["size"].getBiggestInt < 0 or
            node["size"].getBiggestInt > high(int):
          raise newException(ValueError, "invalid ASAR file size: " & path)
        var entry = ElectronAsarEntry(name: path, segments: pathSegments,
          size: int(node["size"].getBiggestInt),
          unpacked: inheritedUnpacked or node.optionalBool("unpacked", path),
          executable: node.optionalBool("executable", path))
        if not entry.unpacked:
          if not node.hasKey("offset") or node["offset"].kind != JString:
            raise newException(ValueError, "missing ASAR file offset: " & path)
          let relativeOffset = decimalOffset(node["offset"].getStr, path)
          if relativeOffset > totalLength - archive.payloadOffset or
              entry.size > totalLength - archive.payloadOffset - relativeOffset:
            raise newException(ValueError, "ASAR file payload is out of bounds: " & path)
          entry.payloadOffset = archive.payloadOffset + relativeOffset
        parseIntegrity(node, entry, path)
        archive.entries.add entry
  visit(files, @[])
  result = move(archive)

proc parseElectronAsar*(data: openArray[byte]): ElectronAsarArchive =
  parseElectronAsarHeader(data, data.len)

proc parseElectronAsar*(source: VextByteSource,
    maximumHeaderSize = 64 * 1024 * 1024): ElectronAsarArchive =
  if source.length < 20:
    raise newException(ValueError, "ASAR archive is too short")
  let sizePickle = source.readAt(0, 8)
  if leDword(sizePickle, 0) != 4:
    raise newException(ValueError, "invalid ASAR header-size Pickle")
  let headerSize = int(leDword(sizePickle, 4))
  if headerSize > maximumHeaderSize:
    raise newException(ValueError, "ASAR header exceeds the manifest limit")
  if headerSize < 12 or headerSize > source.length - 8:
    raise newException(ValueError, "invalid ASAR header size")
  let headerAndPrefix = source.readAt(0, 8 + headerSize)
  result = parseElectronAsarHeader(headerAndPrefix, source.length)

proc extractElectronAsarEntry*(source: VextByteSource,
    entry: ElectronAsarEntry, maximumSize = high(int)): seq[byte] =
  if entry.isDirectory:
    raise newException(ValueError, "cannot extract an ASAR directory")
  if entry.unpacked:
    raise newException(ValueError, "ASAR member is stored outside the archive: " & entry.name)
  if entry.size > maximumSize:
    raise newException(ValueError,
      "ASAR member exceeds the permitted materialization size: " & entry.name)
  source.readAt(entry.payloadOffset, entry.size)

proc isElectronAsar*(data: openArray[byte]): bool =
  try:
    discard parseElectronAsar(data)
    true
  except ValueError:
    false

proc hasElectronAsarExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".asar")
