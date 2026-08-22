## Reusable hierarchical resource descriptions returned by container inspection.

import ./archetypes/raster
import ./archetypes/audio
import ./archetypes/font
import ./metadata

type
  VextResourceNodeKind* = enum
    vrnkGroup
    vrnkRaster
    vrnkText
    vrnkAudio
    vrnkFont
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
    instrument*: VextSampledInstrument
    font*: VextBitmapFont
    data*: seq[byte]
    rawDataAvailable*: bool
    metadata*: seq[VextMetadataEntry]
    children*: seq[VextResourceNode]
    defaultExportPriority*: int

  VextResourceTree* = object
    roots*: seq[VextResourceNode]

proc audioSound*(node: VextResourceNode): VextSound =
  ## Returns the playable sound carried by either audio resource archetype.
  if node.isNil or node.kind != vrnkAudio:
    raise newException(ValueError, "resource is not audio")
  case node.audioKind
  of varkSound: node.sound
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
