## Command-line client for vexterlib.

import std/[json, os, strformat, strutils]
import vexterlib

type
  CliError = object of CatchableError

  CliOptions = object
    json: bool
    allCandidates: bool
    force: bool
    inputFormat: string
    outputFormat: string
    resource: string
    output: string
    input: string

proc usage(): string =
  """Usage:
  vexter inspect [--json] [--all-candidates] [--input-format FORMAT] INPUT
  vexter export [--format png|gif] [--resource PATH]
                [--input-format FORMAT] [-o OUTPUT] [--force] INPUT"""

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc parseOptions(arguments: seq[string]): CliOptions =
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    case argument
    of "--json":
      result.json = true
    of "--all-candidates":
      result.allCandidates = true
    of "--force":
      result.force = true
    of "--input-format", "--format", "--resource", "-o":
      inc index
      if index >= arguments.len:
        raise newException(CliError, "missing value for " & argument)
      case argument
      of "--input-format": result.inputFormat = arguments[index]
      of "--format": result.outputFormat = arguments[index].toLowerAscii
      of "--resource": result.resource = arguments[index]
      of "-o": result.output = arguments[index]
      else: discard
    else:
      if argument.startsWith("-"):
        raise newException(CliError, "unknown option: " & argument)
      if result.input.len > 0:
        raise newException(CliError, "more than one input was provided")
      result.input = argument
    inc index

  if result.input.len == 0:
    raise newException(CliError, "no input was provided")

proc selectedCandidate(options: CliOptions, data: openArray[byte]):
    VextDetectionCandidate =
  if options.inputFormat.len > 0:
    if options.inputFormat notin [ZxSpectrumScreenTypeId,
        ZxSpectrumSnapshotTypeId]:
      raise newException(CliError,
        "unsupported input format: " & options.inputFormat)
    if options.inputFormat == ZxSpectrumScreenTypeId and
        data.len != ZxSpectrumScreenSize:
      raise newException(CliError,
        "ZX Spectrum screen must contain exactly 6912 bytes")
    if options.inputFormat == ZxSpectrumSnapshotTypeId and
        not isZxSpectrumSnapshotSize(data.len):
      raise newException(CliError,
        "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
    return VextDetectionCandidate(
      typeId: options.inputFormat,
      confidence: vdcProbable,
      evidence: @[VextDetectionEvidence(
        description: "format selected with --input-format")])

  let candidates = detectFormats(options.input, data)
  if candidates.len == 0:
    raise newException(CliError, "input format was not recognized")
  candidates[0]

proc inspect(options: CliOptions) =
  let data = readBytes(options.input)
  let selected = selectedCandidate(options, data)
  let candidates = detectFormats(options.input, data)
  let raster = decodeScreenResource(selected.typeId, data)

  if options.json:
    var candidateNodes = newJArray()
    let shownCandidates =
      if options.allCandidates and options.inputFormat.len == 0: candidates
      else: @[selected]
    for candidate in shownCandidates:
      var evidence = newJArray()
      for item in candidate.evidence:
        evidence.add %item.description
      candidateNodes.add %*{
        "type": candidate.typeId,
        "confidence": $candidate.confidence,
        "evidence": evidence
      }
    var resource = %*{
      "path": ZxSpectrumScreenResourcePath,
      "type": ZxSpectrumScreenTypeId,
      "archetype": raster.archetypeName,
      "width": raster.width,
      "height": raster.height
    }
    if raster.kind == vrkIndexedAnimation:
      resource["frames"] = %raster.animation.frames.len
    let document = %*{
      "input": options.input,
      "selectedFormat": selected.typeId,
      "candidates": candidateNodes,
      "resources": [resource]
    }
    echo document.pretty
  else:
    echo options.input
    echo &"Format: {selected.typeId} ({selected.confidence})"
    for item in selected.evidence:
      echo "  Evidence: " & item.description
    echo "Resources:"
    var description = &"  {ZxSpectrumScreenResourcePath}  " &
      &"{ZxSpectrumScreenTypeId} -> {raster.archetypeName} " &
      &"{raster.width}x{raster.height}"
    if raster.kind == vrkIndexedAnimation:
      description.add &", {raster.animation.frames.len} frame(s)"
    echo description

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc exportResource(options: CliOptions) =
  let data = readBytes(options.input)
  let selected = selectedCandidate(options, data)
  if options.resource.len > 0 and
      options.resource != ZxSpectrumScreenResourcePath:
    raise newException(CliError,
      "resource was not found: " & options.resource)

  let raster = decodeScreenResource(selected.typeId, data)
  var outputFormat = options.outputFormat
  if outputFormat.len == 0:
    outputFormat = if raster.kind == vrkIndexedAnimation: "gif" else: "png"

  let artifacts = case outputFormat
    of "png": exportPng(raster.naturalImage,
      options.input.splitFile.name & ".png")
    of "gif": exportGif(raster.asIndexedAnimation,
      options.input.splitFile.name & ".gif")
    else:
      raise newException(CliError,
        "unsupported output format: " & outputFormat)

  if artifacts.artifacts.len != 1:
    raise newException(CliError,
      "export produced multiple artifacts; an output directory is required")
  let artifact = artifacts.artifacts[0]
  let destination = if options.output.len > 0: options.output
                    else: options.input.changeFileExt(outputFormat)
  if fileExists(destination) and not options.force:
    raise newException(CliError,
      "output already exists (use --force): " & destination)
  writeFile(destination, bytesToString(artifact.data))
  echo destination

proc main() =
  let arguments = commandLineParams()
  if arguments.len == 0 or arguments[0] in ["-h", "--help"]:
    echo usage()
    return
  let options = parseOptions(arguments[1 .. ^1])
  case arguments[0]
  of "inspect": inspect(options)
  of "export": exportResource(options)
  else: raise newException(CliError, "unknown command: " & arguments[0])

when isMainModule:
  try:
    main()
  except CliError, IOError, OSError, ValueError:
    stderr.writeLine("vexter: " & getCurrentExceptionMsg())
    quit(1)
