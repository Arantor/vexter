## Random-access inputs used by inspection sessions.
##
## The core library deliberately does not open host files. Frontends provide a
## bounded reader (and, where applicable, a companion resolver), while tests
## and embedders can use the owned in-memory adapter below.

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

  VextSourceCollection* = ref object
    primary*: VextByteSource
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

proc newSourceCollection*(primary: VextByteSource,
    resolver: VextCompanionSourceResolver = nil): VextSourceCollection =
  if primary.isNil:
    raise newException(ValueError, "a primary source is required")
  VextSourceCollection(primary: primary, resolveCompanion: resolver)

proc companion*(collection: VextSourceCollection,
    relativePath: string): VextByteSource =
  if collection.isNil or collection.closed:
    raise newException(ValueError, "source collection is not available")
  if collection.resolveCompanion.isNil: return
  result = collection.resolveCompanion(relativePath)
  if not result.isNil: collection.companions.add result

proc close*(collection: VextSourceCollection) =
  if collection.isNil or collection.closed: return
  collection.closed = true
  collection.primary.close()
  for source in collection.companions: source.close()
  collection.companions.setLen(0)
