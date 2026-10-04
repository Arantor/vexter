## Command-line client for vexterlib.

import std/[json, os, strformat, strutils, terminal]
import vexterlib
import vexter_output
import vexter_session_input

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
    ansiLetterSpacing: AnsiLetterSpacing
    ansiAspect: AnsiPresentationAspect
    output: string
    input: string

proc usage(): string =
  """Usage:
  vexter inspect [--json] [--all-candidates] [--ignore-warnings]
                 [--input-format FORMAT] [--pcx-channel-order rgb|bgr]
                 [--ansi-letter-spacing auto|8|9]
                 [--ansi-aspect auto|legacy|square] INPUT
  vexter export [--format png|gif|apng|gif-cycled|apng-cycled|palette-swatch|gpl|bmfont|tracker-json|html-report|metadata-json|md|txt|wav|bin]
                [--resource PATH] [--allow-large-animation]
                [--input-format FORMAT] [-o OUTPUT] [--force]
                [--ignore-warnings] [--pcx-channel-order rgb|bgr]
                [--ansi-letter-spacing auto|8|9]
                [--ansi-aspect auto|legacy|square] INPUT
  vexter export-all [--format png|gif|apng|gif-cycled|apng-cycled|palette-swatch|gpl|bmfont|tracker-json|html-report|metadata-json|md|txt|wav|bin]
                    [--resource PATH-PATTERN]... [--input-format FORMAT]
                    -o DIRECTORY [--force] [--ignore-warnings]
                    [--allow-large-animation]
                    [--pcx-channel-order rgb|bgr]
                    [--ansi-letter-spacing auto|8|9]
                    [--ansi-aspect auto|legacy|square] INPUT
  vexter extract [--input-format FORMAT] -o DIRECTORY [--force] INPUT"""

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
    of "--input-format", "--format", "--resource", "--pcx-channel-order",
        "--ansi-letter-spacing", "--ansi-aspect", "-o":
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
      of "--ansi-letter-spacing":
        case arguments[index].toLowerAscii
        of "auto": result.ansiLetterSpacing = alsAuto
        of "8": result.ansiLetterSpacing = alsEight
        of "9": result.ansiLetterSpacing = alsNine
        else: raise newException(CliError,
          "invalid ANSI letter spacing: " & arguments[index])
      of "--ansi-aspect":
        case arguments[index].toLowerAscii
        of "auto": result.ansiAspect = apaAuto
        of "legacy": result.ansiAspect = apaLegacy
        of "square": result.ansiAspect = apaSquare
        else: raise newException(CliError,
          "invalid ANSI aspect: " & arguments[index])
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

proc descriptorKind(item: VextResourceDescriptor): string =
  case item.kind
  of vrnkGroup: "group"
  of vrnkRaster: "raster"
  of vrnkText: "text"
  of vrnkDocument: "document"
  of vrnkAudio: "audio"
  of vrnkFont: "font"
  of vrnkPalette: "palette"
  of vrnkTracker: "tracker"
  of vrnkVector: "vector"
  of vrnkOpaque: "opaque"

proc inspect(options: CliOptions) =
  let progress: VextSessionProgressCallback =
    if stderr.isatty:
      proc(event: VextSessionProgressEvent): bool =
        let status = if event.discovered > 0:
            &"{event.completed}/{event.discovered}, {event.pending} pending"
          else: event.message
        stderr.write("\rVexter: " & status & "                    ")
        if event.phase == vsppComplete: stderr.write("\r" & repeat(' ', 72) & "\r")
        true
    else: nil
  let session = openFilesystemInspectionSession(options.input,
    options.inputFormat, options.ignoreWarnings, options.pcxChannelOrder,
    options.ansiLetterSpacing, options.ansiAspect, progress = progress)
  defer: session.close()
  var resources: seq[VextResourceDescriptor]
  session.walkTopology(proc(item: VextResourceDescriptor): bool =
    if item.kind != vrnkGroup: resources.add item
    true, progress)

  if options.json:
    var candidateNodes = newJArray()
    let shownCandidates =
      if options.allCandidates and options.inputFormat.len == 0:
        session.candidates
      else: @[session.selectedFormat]
    for candidate in shownCandidates:
      var evidence = newJArray()
      for item in candidate.evidence:
        evidence.add %item.description
      var derivation = newJArray()
      for stage in candidate.derivation.stages:
        derivation.add %stage.typeId
      candidateNodes.add %*{
        "type": candidate.typeId,
        "confidence": $candidate.confidence,
        "derivation": derivation,
        "evidence": evidence
      }
    var resourceNodes = newJArray()
    for item in resources:
      var resource = %*{
        "path": item.path,
        "type": item.typeId,
        "kind": item.descriptorKind
      }
      if item.kind == vrnkRaster and item.archetype.len > 0:
        resource["archetype"] = %item.archetype
        resource["width"] = %item.width
        resource["height"] = %item.height
        if item.frames > 0: resource["frames"] = %item.frames
      elif item.kind == vrnkAudio:
        resource["archetype"] = %item.archetype
        resource["channels"] = %item.channels
        resource["bitsPerSample"] = %item.bitsPerSample
        resource["sampleRate"] = %item.sampleRate
        resource["samples"] = %item.samples
      elif item.kind == vrnkFont:
        resource["archetype"] = %"VextBitmapFont"
        resource["glyphs"] = %item.glyphs
        resource["characters"] = %item.characters
        resource["lineHeight"] = %item.lineHeight
        resource["baseline"] = %item.baseline
      elif item.kind == vrnkPalette:
        resource["archetype"] = %"VextPalette"
        resource["colours"] = %item.colours
        resource["colourCycleRanges"] = %item.colourCycleRanges
      elif item.kind == vrnkVector:
        resource["archetype"] = %item.archetype
      if item.failureMessage.len > 0:
        resource["failure"] = %*{
          "format": item.failureFormat,
          "message": item.failureMessage
        }
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
      "selectedFormat": session.selectedFormat.typeId,
      "candidates": candidateNodes,
      "resources": resourceNodes
    }
    if session.warnings.len > 0:
      var warningNodes = newJArray()
      for warning in session.warnings:
        warningNodes.add %*{
          "path": warning.path,
          "format": warning.format,
          "message": warning.message
        }
      document["warnings"] = warningNodes
    echo document.pretty
  else:
    echo options.input
    echo &"Format: {session.selectedFormat.typeId} " &
      &"({session.selectedFormat.confidence})"
    if session.selectedFormat.derivation.stages.len > 1:
      var stages: seq[string]
      for stage in session.selectedFormat.derivation.stages:
        stages.add stage.typeId
      echo "Derivation: " & stages.join(" -> ")
    for item in session.selectedFormat.evidence:
      echo "  Evidence: " & item.description
    echo "Resources:"
    for item in resources:
      var description = &"  {item.path}  {item.typeId}"
      if item.kind == vrnkRaster and item.archetype.len > 0:
        description.add &" -> {item.archetype} {item.width}x{item.height}"
        if item.frames > 0: description.add &", {item.frames} frame(s)"
      elif item.kind == vrnkText:
        description.add " (text)"
      elif item.kind == vrnkDocument:
        description.add " -> VextFlowDocument"
      elif item.kind == vrnkAudio:
        description.add &" -> {item.archetype} {item.channels} channel(s), " &
          &"{item.bitsPerSample}-bit, {item.sampleRate} Hz"
      elif item.kind == vrnkFont:
        description.add &" -> VextBitmapFont {item.glyphs} glyph(s), " &
          &"{item.characters} character mapping(s), " &
          &"line height {item.lineHeight}, baseline {item.baseline}"
      elif item.kind == vrnkPalette:
        description.add &" -> VextPalette {item.colours} colour(s), " &
          &"{item.colourCycleRanges} cycling range(s)"
      elif item.kind == vrnkVector:
        description.add " -> VextVectorDrawing"
      elif item.kind == vrnkTracker:
        description.add " -> VextTrackerModule"
      elif item.kind == vrnkGroup:
        description.add " (group)"
      else:
        description.add " (opaque)"
      echo description
      for entry in item.metadata:
        let value = case entry.value.kind
          of vmvkInteger: $entry.value.integerValue
          of vmvkString: entry.value.stringValue
        echo &"    {entry.key}: {value}"
    if session.warnings.len > 0:
      echo "Warnings:"
      for warning in session.warnings:
        echo &"  {warning.path} ({warning.format}): {warning.message}"

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc exportResource(options: CliOptions) =
  if options.resources.len > 1:
    raise newException(CliError,
      "--resource may be repeated only with export-all")
  let session = openFilesystemInspectionSession(options.input,
    options.inputFormat, options.ignoreWarnings, options.pcxChannelOrder,
    options.ansiLetterSpacing, options.ansiAspect)
  defer: session.close()
  let tree = session.resourceTree()
  let exportWarnings = session.warnings
  for warning in exportWarnings:
    stderr.writeLine(&"vexter: warning: {warning.path} " &
      &"({warning.format}): {warning.message}")
  let exported = vexterlib.exportResource(tree,
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
    preflightOutput(options.output, directory = true, force = options.force)
    for artifact in artifacts.artifacts:
      let destination = options.output / artifact.suggestedFilename
      preflightOutput(destination, directory = false, force = options.force)
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
    of "tracker-json": "json"
    of "html-report": "html"
    else: exported.outputFormat
  let destination = if options.output.len > 0: options.output
                    else: options.input.changeFileExt(extension)
  preflightOutput(destination, directory = false, force = options.force)
  writeFile(destination, bytesToString(artifact.data))
  echo destination

proc exportAllResources(options: CliOptions) =
  if options.output.len == 0:
    raise newException(CliError, "export-all requires -o DIRECTORY")
  preflightOutput(options.output, directory = true, force = options.force)

  let session = openFilesystemInspectionSession(options.input,
    options.inputFormat, options.ignoreWarnings, options.pcxChannelOrder,
    options.ansiLetterSpacing, options.ansiAspect)
  defer: session.close()
  let tree = session.resourceTree()
  let exportWarnings = session.warnings
  for warning in exportWarnings:
    stderr.writeLine(&"vexter: warning: {warning.path} " &
      &"({warning.format}): {warning.message}")
  let exported = vexterlib.exportAllResources(tree,
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
      preflightOutput(destination, directory = false, force = options.force)
      destinations.add destination
      relativeNames.add artifact.suggestedFilename
      artifacts.add artifact

  for index, name in relativeNames:
    for otherIndex, other in relativeNames:
      if index != otherIndex and name.toLowerAscii.startsWith(
          other.toLowerAscii & "/"):
        raise newException(CliError,
          "output paths conflict: " & other & " and " & name)

  createDir(options.output)
  for index, artifact in artifacts:
    let destination = destinations[index]
    let parent = destination.parentDir
    if parent.len > 0:
      createDir(parent)
    writeFile(destination, bytesToString(artifact.data))
    echo destination

proc extractContainer(options: CliOptions) =
  if options.output.len == 0:
    raise newException(CliError, "extract requires -o DIRECTORY")
  preflightOutput(options.output, directory = true, force = options.force)
  let session = openFilesystemInspectionSession(options.input,
    options.inputFormat)
  defer: session.close()
  let plan = session.extractionPlan()
  for warning in plan.warnings:
    stderr.writeLine("vexter: warning: " & warning)

  # Validate every destination before creating the output directory or
  # materializing a potentially expensive member.
  for entry in plan.entries:
    let destination = options.output / entry.relativePath
    preflightOutput(destination, directory = entry.kind == veekDirectory,
      force = options.force)

  createDir(options.output)
  for entry in plan.entries:
    let destination = options.output / entry.relativePath
    if entry.kind == veekDirectory:
      createDir(destination)
      continue
    if destination.parentDir.len > 0: createDir(destination.parentDir)
    var output: File
    if not open(output, destination, fmWrite):
      raise newException(CliError, "could not create extraction file: " & destination)
    try:
      session.streamPayload(entry.descriptor.id,
        proc(data: openArray[byte]) =
          if data.len > 0 and output.writeBuffer(unsafeAddr data[0], data.len) != data.len:
            raise newException(IOError, "short write extracting: " & destination))
    finally:
      output.close()
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
  of "extract": extractContainer(options)
  else: raise newException(CliError, "unknown command: " & arguments[0])

when isMainModule:
  try:
    main()
  except CliError, IOError, OSError, ValueError:
    stderr.writeLine("vexter: " & getCurrentExceptionMsg())
    quit(1)
