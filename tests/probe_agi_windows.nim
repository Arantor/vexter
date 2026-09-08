import std/os
import vexterlib

proc fileSource(path: string): VextByteSource =
  let size = int(path.getFileSize)
  var handle = open(path, fmRead)
  newByteSource(size, proc(offset, amount: int): seq[byte] =
    handle.setFilePos(offset)
    result = newSeq[byte](amount)
    if amount > 0: discard handle.readBuffer(addr result[0], amount),
    path, proc() = handle.close())

proc opener(path: string): VextRelatedSourceOpen =
  result = proc(): VextByteSource = fileSource(path)

proc collection(path: string): VextSourceCollection =
  var related: seq[VextRelatedSource]
  proc add(base, prefix: string) =
    for kind, item in base.walkDir:
      if kind == pcFile:
        let fullPath = item
        related.add VextRelatedSource(
          relativePath: if prefix.len == 0: item.extractFilename
            else: prefix & "/" & item.extractFilename,
          size: int(fullPath.getFileSize), open: opener(fullPath))
  add(path, "")
  for kind, item in path.walkDir:
    if kind == pcDir: add(item, item.extractFilename)
  for item in related: echo item.relativePath
  newSourceCollection(relatedSources = related)

let sources = collection(paramStr(1))
echo "games=", discoverAgiGames(sources).len
let session = openInspectionSession(paramStr(1), sources)
echo session.selectedFormat.typeId
