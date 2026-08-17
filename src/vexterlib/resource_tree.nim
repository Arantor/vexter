## Reusable hierarchical resource descriptions returned by container inspection.

import ./archetypes/raster

type
  VextResourceNodeKind* = enum
    vrnkGroup
    vrnkRaster

  VextResourceNode* = ref object
    path*: string
    typeId*: string
    kind*: VextResourceNodeKind
    raster*: VextRaster
    children*: seq[VextResourceNode]

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

proc findRasterResource*(tree: VextResourceTree,
    path: string): VextResourceNode =
  for resource in tree.rasterResources:
    if resource.path == path:
      return resource
