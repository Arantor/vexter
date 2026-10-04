## Shared filesystem-backed inspection-session setup for Vexter frontends.

import std/[os, strutils]
import vexterlib

proc fileByteSource(path: string): VextByteSource =
  let length = int(path.getFileSize)
  var input = open(path, fmRead)
  newByteSource(length,
    proc(offset, amount: int): seq[byte] =
      input.setFilePos(offset)
      result = newSeq[byte](amount)
      if amount > 0 and input.readBuffer(addr result[0], amount) != amount:
        raise newException(IOError, "short read from " & path),
    path, proc() = input.close())

proc companionSourceResolverFor(path: string): VextCompanionSourceResolver =
  let directory = path.parentDir
  result = proc(relativePath: string): VextByteSource =
    var candidate = directory
    for segment in relativePath.split('/'):
      let exact = candidate / segment
      if exact.fileExists or exact.dirExists:
        candidate = exact
        continue
      var match = ""
      if candidate.dirExists:
        for kind, item in candidate.walkDir:
          if item.extractFilename.cmpIgnoreCase(segment) == 0:
            if match.len > 0: return nil
            match = item
      if match.len == 0: return nil
      candidate = match
    if candidate.fileExists: fileByteSource(candidate) else: nil

proc sourceOpenerFor(path: string): VextRelatedSourceOpen =
  result = proc(): VextByteSource = fileByteSource(path)

proc filesystemSourceCollection*(path: string): VextSourceCollection =
  ## Creates the common source view used by both interactive and eager
  ## frontends. Opening a file exposes only sibling files; opening a directory
  ## additionally exposes files in its immediate child directories.
  let directory = if path.dirExists: path else: path.parentDir
  var related: seq[VextRelatedSource]
  proc addDirectory(base: string, prefix = "") =
    for kind, item in base.walkDir:
      if kind == pcFile:
        # Snapshot the iterator value before putting it in a lazy closure.
        let fullPath = item
        let relative = if prefix.len == 0: item.extractFilename
          else: prefix & "/" & item.extractFilename
        if relative.safeRelatedPath:
          try:
            related.add VextRelatedSource(relativePath: relative,
              size: int(fullPath.getFileSize), open: sourceOpenerFor(fullPath))
          except OSError:
            # Related files are optional. A stale or host-incompatible entry
            # beside the selected input must not prevent opening that input.
            discard
  directory.addDirectory()
  # Launchers may sit beside a single immediate child data directory. Deeper
  # traversal remains deliberately out of scope. Only an explicitly opened
  # directory is package-discovery scope.
  if path.dirExists:
    for kind, item in directory.walkDir:
      if kind == pcDir: item.addDirectory(item.extractFilename)
  let primary = if path.fileExists: fileByteSource(path) else: nil
  newSourceCollection(primary, if path.fileExists:
      companionSourceResolverFor(path) else: nil,
    related, if path.fileExists: path.extractFilename else: "")

proc openFilesystemInspectionSession*(path: string, inputFormat = "",
    ignoreWarnings = false, pcxChannelOrder = pcoRgb,
    ansiLetterSpacing = alsAuto, ansiAspect = apaAuto,
    limits = defaultWorkLimits(), progress: VextSessionProgressCallback = nil):
    VextInspectionSession =
  ## Opens the same filesystem-backed session for eager and incremental
  ## consumers. The consumer chooses whether to call `resourceTree` or issue
  ## descriptor expansion and resource-load requests on demand.
  openInspectionSession(path, filesystemSourceCollection(path), inputFormat,
    ignoreWarnings, pcxChannelOrder, ansiLetterSpacing, ansiAspect, limits,
    progress)
