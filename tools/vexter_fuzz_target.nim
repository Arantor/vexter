## Process fuzzing target. External fuzz infrastructure supplies instrumentation,
## time/memory limits, corpora, and the input path.

import std/os
import vexterlib

proc usage(): string =
  "usage: vexter_fuzz_target detect|parse|inspect|session TYPE-ID|- FILENAME INPUT"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents: result[index] = byte(value)

proc main() =
  if paramCount() != 4:
    stderr.writeLine usage()
    quit 2
  let mode = paramStr(1)
  let typeId = paramStr(2)
  let filename = paramStr(3)
  let data = readBytes(paramStr(4))
  try:
    case mode
    of "detect":
      discard detectFormats(filename, data)
    of "parse":
      let handler = formatHandler(typeId)
      if handler.isNil:
        raise newException(ValueError, "unknown format type: " & typeId)
      if handler[].carrierTypeId.len == 0:
        discard handler[].parse(data)
      else:
        discard forceFormat(filename, data, typeId)
    of "inspect":
      discard inspectSource(filename, data,
        if typeId == "-": "" else: typeId)
    of "session":
      var limits = defaultWorkLimits()
      limits.maximumResources = 10_000
      limits.maximumManifestBytes = 16 * 1024 * 1024
      limits.maximumWorkingBytes = 16 * 1024 * 1024
      let session = openInspectionSession(filename,
        newSourceCollection(memoryByteSource(data)),
        if typeId == "-": "" else: typeId, limits = limits)
      defer: session.close()
      session.walkTopology(proc(descriptor: VextResourceDescriptor): bool =
        if vrcMaterializePayload in descriptor.capabilities:
          discard session.loadResource(descriptor.id)
        true)
      for root in session.rootDescriptors:
        if vrcExtractTree in root.capabilities:
          let plan = session.extractionPlan(root.id)
          for entry in plan.entries:
            if entry.kind == veekFile:
              discard session.materializePayload(entry.descriptor.id)
    else:
      raise newException(ValueError, "unknown fuzz mode: " & mode)
  except CatchableError:
    # Structured rejection and unavailable optional native codecs are normal.
    # Defects, assertions, signals, sanitizer findings, and hangs escape.
    discard

when isMainModule:
  main()
