## Random-access inputs used by inspection sessions.
##
## The core library deliberately does not open host files. Frontends provide a
## bounded reader (and, where applicable, a companion resolver), while tests
## and embedders can use the owned in-memory adapter below.

import std/strutils

type
  VextSourceRead* = proc(offset, length: int): seq[byte] {.closure.}
  VextSourceClose* = proc() {.closure.}

  VextByteSource* = ref object
    length*: int
    label*: string
    readProc: VextSourceRead
    closeProc: VextSourceClose
    closed: bool

  VextCompanionSourceResolver* = proc(relativePath: string): VextByteSource
    {.closure.}
  VextRelatedSourceOpen* = proc(): VextByteSource {.closure.}

  VextRelatedSource* = object
    ## A frontend-validated, collection-relative file. Paths always use '/'
    ## separators and contain no empty, dot, or parent segments.
    relativePath*: string
    size*: int
    open*: VextRelatedSourceOpen

  VextSourceCollection* = ref object
    primary*: VextByteSource
    selectedMember*: string
    relatedSources*: seq[VextRelatedSource]
    resolveCompanion*: VextCompanionSourceResolver
    companions: seq[VextByteSource]
    closed: bool

proc newByteSource*(length: int, read: VextSourceRead,
    label = "", close: VextSourceClose = nil): VextByteSource =
  if length < 0:
    raise newException(ValueError, "source length cannot be negative")
  if read.isNil:
    raise newException(ValueError, "source reader is required")
  VextByteSource(length: length, label: label, readProc: read,
    closeProc: close)

proc readAt*(source: VextByteSource, offset, length: int): seq[byte] =
  if source.isNil or source.closed:
    raise newException(ValueError, "source is not available")
  if offset < 0 or length < 0 or offset > source.length - length:
    raise newException(ValueError, "source read is outside its bounds")
  result = source.readProc(offset, length)
  if result.len != length:
    raise newException(IOError, "source reader returned a short read")

proc readAll*(source: VextByteSource, maximum = high(int)): seq[byte] =
  if source.isNil:
    raise newException(ValueError, "source is not available")
  if source.length > maximum:
    raise newException(ValueError, "source exceeds the permitted materialization size")
  source.readAt(0, source.length)

proc close*(source: VextByteSource) =
  if source.isNil or source.closed: return
  source.closed = true
  if source.closeProc != nil: source.closeProc()

proc memoryByteSource*(data: sink seq[byte], label = ""): VextByteSource =
  ## Owns `data` and serves bounded copies from it. The closure is the sole
  ## owner, so closing the source releases the complete buffer.
  var owned = move(data)
  result = newByteSource(owned.len,
    proc(offset, length: int): seq[byte] =
      result = newSeq[byte](length)
      for index in 0 ..< length:
        result[index] = owned[offset + index],
    label,
    proc() = owned.setLen(0))

proc sliceByteSource*(source: VextByteSource, offset, length: int,
    label = ""): VextByteSource =
  ## Presents a bounded, non-owning window over another source. Closing the
  ## view does not close its parent; the caller must keep the parent alive.
  if source.isNil or offset < 0 or length < 0 or offset > source.length - length:
    raise newException(ValueError, "source slice is outside its bounds")
  newByteSource(length,
    proc(relativeOffset, readLength: int): seq[byte] =
      source.readAt(offset + relativeOffset, readLength),
    label)

proc safeRelatedPath(path: string): bool =
  if path.len == 0 or path[0] in {'/', '\\'} or '\\' in path: return false
  for segment in path.split('/'):
    if segment.len == 0 or segment in [".", ".."]: return false
  true

proc newSourceCollection*(primary: VextByteSource = nil,
    resolver: VextCompanionSourceResolver = nil,
    relatedSources: seq[VextRelatedSource] = @[],
    selectedMember = ""): VextSourceCollection =
  for item in relatedSources:
    if not item.relativePath.safeRelatedPath or item.size < 0 or item.open.isNil:
      raise newException(ValueError, "invalid related-source manifest entry")
  VextSourceCollection(primary: primary, resolveCompanion: resolver,
    relatedSources: relatedSources, selectedMember: selectedMember)

proc companion*(collection: VextSourceCollection,
    relativePath: string): VextByteSource

proc related*(collection: VextSourceCollection,
    relativePath: string): VextByteSource =
  ## Resolves one manifest member case-insensitively, rejecting ambiguity.
  collection.companion(relativePath)

proc companion*(collection: VextSourceCollection,
    relativePath: string): VextByteSource =
  if collection.isNil or collection.closed or not relativePath.safeRelatedPath:
    raise newException(ValueError, "source collection is not available")
  var found = -1
  for index, item in collection.relatedSources:
    if item.relativePath.cmpIgnoreCase(relativePath) == 0:
      if found >= 0: return nil
      found = index
  if found >= 0:
    result = collection.relatedSources[found].open()
  elif not collection.resolveCompanion.isNil:
    result = collection.resolveCompanion(relativePath)
  if not result.isNil: collection.companions.add result

proc close*(collection: VextSourceCollection) =
  if collection.isNil or collection.closed: return
  collection.closed = true
  if not collection.primary.isNil: collection.primary.close()
  for source in collection.companions: source.close()
  collection.companions.setLen(0)
