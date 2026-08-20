## Reusable hierarchical resource descriptions returned by container inspection.

import ./archetypes/raster
import ./archetypes/audio
import ./metadata

type
  VextResourceNodeKind* = enum
    vrnkGroup
    vrnkRaster
    vrnkText
    vrnkAudio
    vrnkOpaque

  VextResourceNode* = ref object
    path*: string
    typeId*: string
    kind*: VextResourceNodeKind
    raster*: VextRaster
    text*: string
    instrument*: VextSampledInstrument
    data*: seq[byte]
    rawDataAvailable*: bool
    metadata*: seq[VextMetadataEntry]
    children*: seq[VextResourceNode]
    defaultExportPriority*: int

  VextResourceTree* = object
    roots*: seq[VextResourceNode]

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

proc findRasterResource*(tree: VextResourceTree,
    path: string): VextResourceNode =
  for resource in tree.rasterResources:
    if resource.path == path:
      return resource
