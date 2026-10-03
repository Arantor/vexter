## Shared filesystem preflight for the CLI and GUI frontends.

import std/os

proc preflightOutput*(destination: string, directory, force: bool) =
  # Check the complete parent chain, including the caller's output root.
  # Broken links also count: fileExists/dirExists alone miss them.
  var current = destination.absolutePath
  var first = true
  while true:
    if symlinkExists(current):
      raise newException(IOError,
        "output path is a symbolic link: " & current)
    if first and not directory:
      if dirExists(current):
        raise newException(IOError,
          "output path is a directory: " & destination)
      if fileExists(current) and not force:
        raise newException(IOError,
          "output already exists (use --force): " & destination)
    elif fileExists(current):
      raise newException(IOError,
        "output directory conflicts with a file: " & current)
    let parent = current.parentDir
    if parent.len == 0 or parent == current: break
    current = parent
    first = false

