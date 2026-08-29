## Reusable hierarchical resource descriptions returned by container inspection.

import ./archetypes/raster
import ./archetypes/audio
import ./archetypes/font
import ./archetypes/palette
import ./archetypes/tracker
import ./metadata

type
  VextPayloadMaterializer* = proc(): seq[byte] {.closure.}
  VextSoundMaterializer* = proc(): VextSound {.closure.}

  VextPayloadSource* = ref object
    ## Shared immutable bytes retained once for lazy container members.
    data*: seq[byte]

  VextPayloadSpan* = object
    offset*, length*: int

  VextPayloadRef* = object
    source*: VextPayloadSource
    spans*: seq[VextPayloadSpan]
    length*: int
    materializer*: VextPayloadMaterializer

  VextResourceNodeKind* = enum
    vrnkGroup
    vrnkRaster
    vrnkText
    vrnkAudio
    vrnkFont
    vrnkPalette
    vrnkTracker
    vrnkOpaque

  VextAudioResourceKind* = enum
    varkSound
    varkSampledInstrument

  VextResourceNode* = ref object
    path*: string
    typeId*: string
    kind*: VextResourceNodeKind
    raster*: VextRaster
    text*: string
    audioKind*: VextAudioResourceKind
    sound*: VextSound
    soundMaterializer*: VextSoundMaterializer
    derivedAudioChannels*, derivedAudioBitsPerSample*,
      derivedAudioSampleRate*, derivedAudioMaximumSamples*: int
    instrument*: VextSampledInstrument
    font*: VextBitmapFont
    palette*: VextPalette
    tracker*: VextTrackerModule
    ## Base path for sampled-instrument resources referenced by tracker JSON.
    ## Child pattern views may share the parent module's sample collection.
    trackerSampleResourcePath*: string
    data*: seq[byte]
    lazyPayload*: VextPayloadRef
    nestedInspectionAttempted*: bool
    rawDataAvailable*: bool
    ## Populated when a contained file was identified but could not be decoded.
    ## The original bytes remain available independently of this presentation.
    failureFormat*: string
    failureMessage*: string
    metadata*: seq[VextMetadataEntry]
    children*: seq[VextResourceNode]
    defaultExportPriority*: int

  VextResourceTree* = object
    roots*: seq[VextResourceNode]

proc payloadBytes*(payload: VextPayloadRef): seq[byte] =
  if payload.materializer != nil:
    result = payload.materializer()
    if result.len != payload.length:
      raise newException(ValueError,
        "lazy payload materializer returned an unexpected length")
    return
  if payload.source.isNil:
    return
  if payload.length < 0:
    raise newException(ValueError, "invalid lazy payload length")
  result = newSeq[byte](payload.length)
  var target = 0
  for span in payload.spans:
    if span.offset < 0 or span.length < 0 or
        span.offset > payload.source.data.len - span.length or
        target > result.len - span.length:
      raise newException(ValueError, "lazy payload span is outside its source")
    for index in 0 ..< span.length:
      result[target + index] = payload.source.data[span.offset + index]
    target += span.length
  if target != result.len:
    raise newException(ValueError, "lazy payload spans do not match their length")

proc resourceBytes*(node: VextResourceNode): seq[byte] =
  if node.isNil:
    raise newException(ValueError, "cannot read a missing resource")
  if not node.lazyPayload.source.isNil:
    return node.lazyPayload.payloadBytes
  node.data

proc retainedByteLength*(node: VextResourceNode): int =
  if node.isNil: 0
  elif not node.lazyPayload.source.isNil: node.lazyPayload.length
  else: node.data.len

proc audioSound*(node: VextResourceNode): VextSound =
  ## Returns the playable sound carried by either audio resource archetype.
  if node.isNil or node.kind != vrnkAudio:
    raise newException(ValueError, "resource is not audio")
  case node.audioKind
  of varkSound:
    if node.soundMaterializer != nil:
      node.sound = node.soundMaterializer()
      node.soundMaterializer = nil
    node.sound
  of varkSampledInstrument: node.instrument.sound

proc addRasterResources(node: VextResourceNode,
    resources: var seq[VextResourceNode]) =
  if node.kind == vrnkRaster:
    resources.add node
  for child in node.children:
    addRasterResources(child, resources)

proc rasterResources*(tree: VextResourceTree): seq[VextResourceNode] =
  for root in tree.roots:
    addRasterResources(root, result)

proc addLeafResources(node: VextResourceNode,
    resources: var seq[VextResourceNode]) =
  if node.kind != vrnkGroup:
    resources.add node
  for child in node.children:
    addLeafResources(child, resources)

proc leafResources*(tree: VextResourceTree): seq[VextResourceNode] =
  ## Returns every independently addressable resource in depth-first order.
  for root in tree.roots:
    addLeafResources(root, result)

proc addResources(node: VextResourceNode,
    resources: var seq[VextResourceNode]) =
  resources.add node
  for child in node.children:
    addResources(child, resources)

proc allResources*(tree: VextResourceTree): seq[VextResourceNode] =
  ## Returns groups and leaves in depth-first presentation order.
  for root in tree.roots:
    addResources(root, result)

proc fontResources*(tree: VextResourceTree): seq[VextResourceNode] =
  for resource in tree.leafResources:
    if resource.kind == vrnkFont: result.add resource

proc findFontResource*(tree: VextResourceTree,
    path: string): VextResourceNode =
  for resource in tree.fontResources:
    if resource.path == path: return resource

proc findRasterResource*(tree: VextResourceTree,
    path: string): VextResourceNode =
  for resource in tree.rasterResources:
    if resource.path == path:
      return resource
