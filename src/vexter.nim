## Command-line client for vexterlib.

import std/[json, os, strformat, strutils]
import vexterlib

type
  CliError = object of CatchableError

  CliOptions = object
    json: bool
    allCandidates: bool
    force: bool
    allowLargeAnimation: bool
    ignoreWarnings: bool
    inputFormat: string
    outputFormat: string
    resources: seq[string]
    pcxChannelOrder: PcxChannelOrder
    output: string
    input: string

proc usage(): string =
  """Usage:
  vexter inspect [--json] [--all-candidates] [--ignore-warnings]
                 [--input-format FORMAT] [--pcx-channel-order rgb|bgr] INPUT
  vexter export [--format png|gif|apng|gif-cycled|apng-cycled|bmfont|html-report|metadata-json|txt|wav|bin]
                [--resource PATH] [--allow-large-animation]
                [--input-format FORMAT] [-o OUTPUT] [--force]
                [--ignore-warnings] [--pcx-channel-order rgb|bgr] INPUT
  vexter export-all [--format png|gif|apng|gif-cycled|apng-cycled|bmfont|html-report|metadata-json|txt|wav|bin]
                    [--resource PATH-PATTERN]... [--input-format FORMAT]
                    -o DIRECTORY [--force] [--ignore-warnings]
                    [--allow-large-animation]
                    [--pcx-channel-order rgb|bgr] INPUT"""

proc readBytes(path: string): seq[byte] {.gcsafe.} =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc companionResolverFor(path: string): VextCompanionResolver =
  let directory = path.parentDir
  result = proc(relativePath: string): seq[byte] {.gcsafe.} =
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
            if match.len > 0: return @[] # ambiguous on a case-sensitive host
            match = item
      if match.len == 0: return @[]
      candidate = match
    if candidate.fileExists: readBytes(candidate) else: @[]

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
    of "--allow-large-animation":
      result.allowLargeAnimation = true
    of "--ignore-warnings":
      result.ignoreWarnings = true
    of "--input-format", "--format", "--resource", "--pcx-channel-order", "-o":
      inc index
      if index >= arguments.len:
        raise newException(CliError, "missing value for " & argument)
      case argument
      of "--input-format": result.inputFormat = arguments[index]
      of "--format": result.outputFormat = arguments[index].toLowerAscii
      of "--resource": result.resources.add arguments[index]
      of "--pcx-channel-order":
        case arguments[index].toLowerAscii
        of "rgb": result.pcxChannelOrder = pcoRgb
        of "bgr": result.pcxChannelOrder = pcoBgr
        else: raise newException(CliError,
          "invalid PCX channel order: " & arguments[index])
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

proc inspect(options: CliOptions) =
  let data = readBytes(options.input)
  let inspection = inspectSource(options.input, data, options.inputFormat,
    options.ignoreWarnings, options.pcxChannelOrder,
    companionResolver = companionResolverFor(options.input))
  let resources = inspection.resources.leafResources

  if options.json:
    var candidateNodes = newJArray()
    let shownCandidates =
      if options.allCandidates and options.inputFormat.len == 0:
        inspection.candidates
      else: @[inspection.selectedFormat]
    for candidate in shownCandidates:
      var evidence = newJArray()
      for item in candidate.evidence:
        evidence.add %item.description
      candidateNodes.add %*{
        "type": candidate.typeId,
        "confidence": $candidate.confidence,
        "evidence": evidence
      }
    var resourceNodes = newJArray()
    for item in resources:
      var resource = %*{
        "path": item.path,
        "type": item.typeId,
        "kind": (case item.kind
          of vrnkRaster: "raster"
          of vrnkText: "text"
          of vrnkAudio: "audio"
          of vrnkFont: "font"
          of vrnkPalette: "palette"
          else: "opaque")
      }
      if item.kind == vrnkRaster:
        let raster = item.raster
        resource["archetype"] = %raster.archetypeName
        resource["width"] = %raster.width
        resource["height"] = %raster.height
        case raster.kind
        of vrkIndexedAnimation:
          resource["frames"] = %raster.animation.frames.len
        of vrkTrueColourAnimation:
          resource["frames"] = %raster.trueColourAnimation.frames.len
        else: discard
      elif item.kind == vrnkAudio:
        let sound = item.audioSound
        resource["archetype"] = %(if item.audioKind == varkSound: "sound"
          else: "sampled-instrument")
        resource["channels"] = %sound.buffer.channels.len
        resource["bitsPerSample"] = %sound.buffer.bitsPerSample
        resource["sampleRate"] = %sound.sampleRate
        resource["samples"] = %sound.buffer.sampleCount
      elif item.kind == vrnkFont:
        resource["archetype"] = %"VextBitmapFont"
        resource["glyphs"] = %item.font.glyphs.len
        resource["characters"] = %item.font.mappings.len
        resource["lineHeight"] = %item.font.lineHeight
        resource["baseline"] = %item.font.baseline
      elif item.kind == vrnkPalette:
        resource["archetype"] = %"VextPalette"
        resource["colours"] = %item.palette.colours.len
        resource["colourCycleRanges"] = %item.palette.colourCycles.len
      if item.metadata.len > 0:
        var metadata = newJObject()
        for entry in item.metadata:
          metadata[entry.key] = case entry.value.kind
            of vmvkInteger: %entry.value.integerValue
            of vmvkString: %entry.value.stringValue
        resource["metadata"] = metadata
      resourceNodes.add resource
    let document = %*{
      "input": options.input,
      "selectedFormat": inspection.selectedFormat.typeId,
      "candidates": candidateNodes,
      "resources": resourceNodes
    }
    if inspection.warnings.len > 0:
      var warningNodes = newJArray()
      for warning in inspection.warnings:
        warningNodes.add %*{
          "path": warning.path,
          "format": warning.format,
          "message": warning.message
        }
      document["warnings"] = warningNodes
    echo document.pretty
  else:
    echo options.input
    echo &"Format: {inspection.selectedFormat.typeId} " &
      &"({inspection.selectedFormat.confidence})"
    for item in inspection.selectedFormat.evidence:
      echo "  Evidence: " & item.description
    echo "Resources:"
    for item in resources:
      var description = &"  {item.path}  {item.typeId}"
      if item.kind == vrnkRaster:
        let raster = item.raster
        description.add &" -> {raster.archetypeName} " &
          &"{raster.width}x{raster.height}"
        case raster.kind
        of vrkIndexedAnimation:
          description.add &", {raster.animation.frames.len} frame(s)"
        of vrkTrueColourAnimation:
          description.add &", {raster.trueColourAnimation.frames.len} frame(s)"
        else: discard
      elif item.kind == vrnkText:
        description.add " (text)"
      elif item.kind == vrnkAudio:
        let sound = item.audioSound
        let archetype = if item.audioKind == varkSound: "sound"
          else: "sampled-instrument"
        description.add &" -> {archetype} " &
          &"{sound.buffer.channels.len} channel(s), " &
          &"{sound.buffer.bitsPerSample}-bit, " &
          &"{sound.sampleRate} Hz"
      elif item.kind == vrnkFont:
        description.add &" -> VextBitmapFont {item.font.glyphs.len} glyph(s), " &
          &"{item.font.mappings.len} character mapping(s), " &
          &"line height {item.font.lineHeight}, baseline {item.font.baseline}"
      elif item.kind == vrnkPalette:
        description.add &" -> VextPalette {item.palette.colours.len} colour(s), " &
          &"{item.palette.colourCycles.len} cycling range(s)"
      else:
        description.add " (opaque)"
      echo description
      for entry in item.metadata:
        let value = case entry.value.kind
          of vmvkInteger: $entry.value.integerValue
          of vmvkString: entry.value.stringValue
        echo &"    {entry.key}: {value}"
    if inspection.warnings.len > 0:
      echo "Warnings:"
      for warning in inspection.warnings:
        echo &"  {warning.path} ({warning.format}): {warning.message}"

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc exportResource(options: CliOptions) =
  if options.resources.len > 1:
    raise newException(CliError,
      "--resource may be repeated only with export-all")
  let data = readBytes(options.input)
  let inspection = inspectSource(options.input, data, options.inputFormat,
    options.ignoreWarnings, options.pcxChannelOrder,
    companionResolver = companionResolverFor(options.input))
  for warning in inspection.warnings:
    stderr.writeLine(&"vexter: warning: {warning.path} " &
      &"({warning.format}): {warning.message}")
  let exported = vexterlib.exportResource(inspection.resources,
    VextExportRequest(
      resourcePath: (if options.resources.len == 1: options.resources[0]
                     else: ""),
      outputFormat: options.outputFormat,
      suggestedName: options.input.splitFile.name,
      allowLargeAnimation: options.allowLargeAnimation))
  for warning in exported.warnings:
    stderr.writeLine("vexter: warning: " & exported.resourcePath &
      " (" & exported.outputFormat & "): " & warning)
  let artifacts = exported.artifacts

  if artifacts.artifacts.len != 1:
    if options.output.len == 0:
      raise newException(CliError,
        "export produced multiple artifacts; specify an output directory with -o")
    if fileExists(options.output):
      raise newException(CliError, "output path is not a directory: " & options.output)
    for artifact in artifacts.artifacts:
      let destination = options.output / artifact.suggestedFilename
      if fileExists(destination) and not options.force:
        raise newException(CliError,
          "output already exists (use --force): " & destination)
    createDir(options.output)
    for artifact in artifacts.artifacts:
      let destination = options.output / artifact.suggestedFilename
      writeFile(destination, bytesToString(artifact.data))
      echo destination
    return
  let artifact = artifacts.artifacts[0]
  let extension = case exported.outputFormat
    of "apng-cycled": "png"
    of "gif-cycled": "gif"
    of "metadata-json": "json"
    of "html-report": "html"
    else: exported.outputFormat
  let destination = if options.output.len > 0: options.output
                    else: options.input.changeFileExt(extension)
  if fileExists(destination) and not options.force:
    raise newException(CliError,
      "output already exists (use --force): " & destination)
  writeFile(destination, bytesToString(artifact.data))
  echo destination

proc exportAllResources(options: CliOptions) =
  if options.output.len == 0:
    raise newException(CliError, "export-all requires -o DIRECTORY")
  if fileExists(options.output):
    raise newException(CliError,
      "export-all output is not a directory: " & options.output)

  let data = readBytes(options.input)
  let inspection = inspectSource(options.input, data, options.inputFormat,
    options.ignoreWarnings, options.pcxChannelOrder,
    companionResolver = companionResolverFor(options.input))
  for warning in inspection.warnings:
    stderr.writeLine(&"vexter: warning: {warning.path} " &
      &"({warning.format}): {warning.message}")
  let exported = vexterlib.exportAllResources(inspection.resources,
    VextExportAllRequest(
      resourcePatterns: options.resources,
      outputFormat: options.outputFormat,
      allowLargeAnimation: options.allowLargeAnimation))

  for item in exported.exports:
    for warning in item.warnings:
      stderr.writeLine("vexter: warning: " & item.resourcePath &
        " (" & item.outputFormat & "): " & warning)

  var destinations: seq[string]
  var relativeNames: seq[string]
  var artifacts: seq[VextArtifact]
  for item in exported.exports:
    for artifact in item.artifacts.artifacts:
      let destination = options.output / artifact.suggestedFilename
      if dirExists(destination):
        raise newException(CliError,
          "output path is a directory: " & destination)
      if fileExists(destination) and not options.force:
        raise newException(CliError,
          "output already exists (use --force): " & destination)
      destinations.add destination
      relativeNames.add artifact.suggestedFilename
      artifacts.add artifact

  for index, name in relativeNames:
    for otherIndex, other in relativeNames:
      if index != otherIndex and name.toLowerAscii.startsWith(
          other.toLowerAscii & "/"):
        raise newException(CliError,
          "output paths conflict: " & other & " and " & name)
    var parent = destinations[index].parentDir
    while parent.len > 0 and parent != options.output:
      if fileExists(parent):
        raise newException(CliError,
          "output parent is a file: " & parent)
      let next = parent.parentDir
      if next == parent:
        break
      parent = next

  createDir(options.output)
  for index, artifact in artifacts:
    let destination = destinations[index]
    let parent = destination.parentDir
    if parent.len > 0:
      createDir(parent)
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
  of "export-all": exportAllResources(options)
  else: raise newException(CliError, "unknown command: " & arguments[0])

when isMainModule:
  try:
    main()
  except CliError, IOError, OSError, ValueError:
    stderr.writeLine("vexter: " & getCurrentExceptionMsg())
    quit(1)
