## Classic Amiga Workbench DiskObject (.info) container parsing.

import std/[os, strutils]

const
  AmigaWorkbenchIconTypeId* = "amiga.workbench-icon"
  AmigaWorkbenchClassicImageTypeId* = "amiga.workbench-icon.classic-image"
  AmigaWorkbenchNewIconImageTypeId* = "amiga.workbench-icon.newicon-image"
  AmigaWorkbenchGlowIconImageTypeId* = "amiga.workbench-icon.glowicon-image"
  AmigaWorkbenchIconHeaderSize* = 78
  AmigaWorkbenchImageHeaderSize* = 20
  WorkbenchDiskMagic* = 0xe310
  WorkbenchDiskVersion* = 1

type
  WorkbenchIconImage* = object
    left*, top*, width*, height*, depth*: int
    planePick*, planeOnOff*: byte
    data*: seq[byte]

  WorkbenchIcon* = object
    version*, iconType*: int
    gadgetLeft*, gadgetTop*, gadgetWidth*, gadgetHeight*: int
    gadgetFlags*, gadgetActivation*, gadgetType*: int
    currentX*, currentY*, stackSize*: int
    defaultTool*, toolWindow*: string
    toolTypes*: seq[string]
    normalImage*, selectedImage*: WorkbenchIconImage
    hasNormalImage*, hasSelectedImage*: bool

  WorkbenchEnhancedImage* = object
    width*, height*: int
    palette*: seq[array[3, byte]]
    pixels*, alpha*: seq[byte]

  WorkbenchGlowIcon* = object
    images*: seq[WorkbenchEnhancedImage]
    frameless*: bool
    aspectX*, aspectY*: int

proc be16(data: openArray[byte], offset: int): int =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc signed16(data: openArray[byte], offset: int): int =
  let value = be16(data, offset)
  if value >= 0x8000: value - 0x10000 else: value

proc be32(data: openArray[byte], offset: int): uint32 =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc signed32(data: openArray[byte], offset: int): int =
  cast[int32](be32(data, offset)).int

proc requireAvailable(data: openArray[byte], offset, length: int,
    description: string) =
  if offset < 0 or length < 0 or offset > data.len or length > data.len - offset:
    raise newException(ValueError, "truncated Workbench icon " & description)

proc parseImage(data: openArray[byte], offset: var int): WorkbenchIconImage =
  requireAvailable(data, offset, AmigaWorkbenchImageHeaderSize, "image header")
  result.left = signed16(data, offset)
  result.top = signed16(data, offset + 2)
  result.width = signed16(data, offset + 4)
  result.height = signed16(data, offset + 6)
  result.depth = signed16(data, offset + 8)
  let hasData = be32(data, offset + 10) != 0
  result.planePick = data[offset + 14]
  result.planeOnOff = data[offset + 15]
  let hasNext = be32(data, offset + 16) != 0
  offset += AmigaWorkbenchImageHeaderSize
  if result.width <= 0 or result.height <= 0 or result.depth < 0 or result.depth > 8:
    raise newException(ValueError, "invalid Workbench icon image dimensions")
  if hasNext:
    raise newException(ValueError, "chained Workbench icon images are not supported")
  if hasData:
    let rowBytes = ((result.width + 15) div 16) * 2
    if result.height > high(int) div max(rowBytes, 1) or
        result.depth > high(int) div max(rowBytes * result.height, 1):
      raise newException(ValueError, "Workbench icon image is too large")
    let length = rowBytes * result.height * result.depth
    requireAvailable(data, offset, length, "image data")
    result.data = @data[offset ..< offset + length]
    offset += length

proc parseCountedString(data: openArray[byte], offset: var int,
    description: string): string =
  requireAvailable(data, offset, 4, description & " length")
  let length = int(be32(data, offset))
  offset += 4
  requireAvailable(data, offset, length, description)
  if length > 0:
    let contentLength = if data[offset + length - 1] == 0: length - 1 else: length
    result = newString(contentLength)
    for index in 0 ..< contentLength:
      result[index] = char(data[offset + index])
  offset += length

proc parseToolTypes(data: openArray[byte], offset: var int): seq[string] =
  requireAvailable(data, offset, 4, "tool-types pointer-array length")
  let arrayLength = int(be32(data, offset))
  offset += 4
  # The stored LONG is the allocation size of the pointer array, including
  # its terminating NULL, not the byte length of the strings which follow it.
  if arrayLength < 4 or (arrayLength mod 4) != 0:
    raise newException(ValueError, "invalid Workbench tool-types pointer array")
  let count = arrayLength div 4 - 1
  if count > 65535:
    raise newException(ValueError, "too many Workbench tool types")
  for index in 0 ..< count:
    result.add parseCountedString(data, offset, "tool type")

proc parseWorkbenchIcon*(data: openArray[byte]): WorkbenchIcon =
  if data.len < AmigaWorkbenchIconHeaderSize or be16(data, 0) != WorkbenchDiskMagic:
    raise newException(ValueError, "invalid Workbench icon magic")
  result.version = be16(data, 2)
  if result.version != WorkbenchDiskVersion:
    raise newException(ValueError, "unsupported Workbench icon version: " & $result.version)
  result.gadgetLeft = signed16(data, 8)
  result.gadgetTop = signed16(data, 10)
  result.gadgetWidth = signed16(data, 12)
  result.gadgetHeight = signed16(data, 14)
  result.gadgetFlags = be16(data, 16)
  result.gadgetActivation = be16(data, 18)
  result.gadgetType = be16(data, 20)
  let hasNormal = be32(data, 22) != 0
  let hasSelected = be32(data, 26) != 0
  let hasDefaultTool = be32(data, 50) != 0
  let hasToolTypes = be32(data, 54) != 0
  let hasDrawerData = be32(data, 66) != 0
  let hasToolWindow = be32(data, 70) != 0
  result.iconType = int(data[48])
  result.currentX = signed32(data, 58)
  result.currentY = signed32(data, 62)
  result.stackSize = signed32(data, 74)
  var offset = AmigaWorkbenchIconHeaderSize
  # icon.library writes the pre-V36 on-disk DrawerData before imagery for
  # drawer-like objects. OLDDRAWERDATAFILESIZE is 56 bytes in the supplied SDK.
  if hasDrawerData and result.iconType in [1, 2, 5]:
    requireAvailable(data, offset, 56, "drawer data")
    offset += 56
  if hasNormal:
    result.normalImage = parseImage(data, offset)
    result.hasNormalImage = true
  if hasSelected:
    result.selectedImage = parseImage(data, offset)
    result.hasSelectedImage = true
  if hasDefaultTool:
    result.defaultTool = parseCountedString(data, offset, "default tool")
  if hasToolTypes:
    result.toolTypes = parseToolTypes(data, offset)
  if hasToolWindow:
    result.toolWindow = parseCountedString(data, offset, "tool window")

proc isWorkbenchIcon*(data: openArray[byte]): bool =
  try:
    discard parseWorkbenchIcon(data)
    true
  except ValueError:
    false

proc hasWorkbenchIconExtension*(filename: string): bool =
  filename.splitFile.ext.toLowerAscii == ".info"

proc newIconToolTypes*(icon: WorkbenchIcon, state: int): seq[string] =
  let prefix = if state == 1: "IM1=" else: "IM2="
  for value in icon.toolTypes:
    if value.startsWith(prefix): result.add value

proc decodedNewIconBits(value: string, start: int): seq[byte] =
  for index in start ..< value.len:
    let encoded = ord(value[index])
    if encoded >= 0x20 and encoded <= 0x6f:
      let decoded = encoded - 0x20
      for bit in countdown(6, 0): result.add byte((decoded shr bit) and 1)
    elif encoded >= 0xa1 and encoded <= 0xd0:
      let decoded = encoded - 0x51
      for bit in countdown(6, 0): result.add byte((decoded shr bit) and 1)
    elif encoded >= 0xd1 and encoded <= 0xff:
      result.add newSeq[byte]((encoded - 0xd0) * 7)
    else:
      raise newException(ValueError, "invalid NewIcons encoded byte")

proc entriesFromBits(bits: openArray[byte], width: int): seq[int] =
  if width <= 0 or width > 8: raise newException(ValueError, "invalid encoded entry width")
  var offset = 0
  while offset + width <= bits.len:
    var value = 0
    for bit in 0 ..< width: value = (value shl 1) or int(bits[offset + bit])
    result.add value
    offset += width

proc parseNewIcon*(icon: WorkbenchIcon, state: int): WorkbenchEnhancedImage =
  let lines = icon.newIconToolTypes(state)
  if lines.len == 0: return
  if lines[0].len < 9:
    raise newException(ValueError, "truncated NewIcons image header")
  let header = lines[0]
  let transparency = header[4]
  if transparency notin {'B', 'C'}:
    raise newException(ValueError, "invalid NewIcons transparency flag")
  result.width = ord(header[5]) - 0x21
  result.height = ord(header[6]) - 0x21
  let colourCount = ((ord(header[7]) - 0x21) shl 6) + ord(header[8]) - 0x21
  if result.width <= 0 or result.width > 93 or result.height <= 0 or
      result.height > 93 or colourCount <= 0 or colourCount > 256:
    raise newException(ValueError, "invalid NewIcons image properties")
  var lineIndex = 0
  var paletteBytes: seq[byte]
  while paletteBytes.len < colourCount * 3 and lineIndex < lines.len:
    let start = if lineIndex == 0: 9 else: 4
    for value in entriesFromBits(decodedNewIconBits(lines[lineIndex], start), 8):
      if paletteBytes.len < colourCount * 3: paletteBytes.add byte(value)
    lineIndex += 1
  if paletteBytes.len != colourCount * 3:
    raise newException(ValueError, "truncated NewIcons palette")
  for index in 0 ..< colourCount:
    result.palette.add [paletteBytes[index * 3], paletteBytes[index * 3 + 1],
      paletteBytes[index * 3 + 2]]
  var depth = 1
  while (1 shl depth) < colourCount: depth += 1
  while lineIndex < lines.len and result.pixels.len < result.width * result.height:
    for value in entriesFromBits(decodedNewIconBits(lines[lineIndex], 4), depth):
      if result.pixels.len < result.width * result.height:
        if value >= colourCount:
          raise newException(ValueError, "NewIcons pixel exceeds its palette")
        result.pixels.add byte(value)
    lineIndex += 1
  if result.pixels.len != result.width * result.height:
    raise newException(ValueError, "truncated NewIcons pixel data")
  if transparency == 'B':
    result.alpha = newSeq[byte](result.pixels.len)
    for index, value in result.pixels:
      result.alpha[index] = if value == 0: 0 else: 255

proc fourCc(data: openArray[byte], offset: int): string =
  result = newString(4)
  for index in 0 .. 3: result[index] = char(data[offset + index])

type BitReader = object
  data: seq[byte]
  bitOffset: int

proc readBits(reader: var BitReader, count: int): int =
  if count < 0 or reader.bitOffset + count > reader.data.len * 8:
    raise newException(ValueError, "truncated GlowIcons compressed data")
  for bit in 0 ..< count:
    let position = reader.bitOffset + bit
    result = (result shl 1) or
      ((int(reader.data[position div 8]) shr (7 - position mod 8)) and 1)
  reader.bitOffset += count

proc unpackGlowEntries(data: seq[byte], format, depth, expected: int): seq[byte] =
  if format == 0:
    if data.len < expected: raise newException(ValueError, "truncated GlowIcons data")
    return data[0 ..< expected]
  if format != 1: raise newException(ValueError, "unsupported GlowIcons compression")
  var reader = BitReader(data: data)
  while result.len < expected and reader.bitOffset + 8 <= data.len * 8:
    let control = reader.readBits(8)
    if control <= 0x7f:
      for index in 0 .. control:
        if result.len >= expected: break
        result.add byte(reader.readBits(depth))
    elif control != 0x80:
      let count = 257 - control
      let value = byte(reader.readBits(depth))
      for index in 0 ..< count:
        if result.len < expected: result.add value
  if result.len != expected: raise newException(ValueError, "truncated GlowIcons RLE data")

proc findGlowForm(data: openArray[byte]): int =
  for offset in 0 .. max(0, data.len - 12):
    if offset + 12 <= data.len and fourCc(data, offset) == "FORM" and
        fourCc(data, offset + 8) == "ICON":
      let size = int(be32(data, offset + 4))
      if size >= 4 and size <= data.len - offset - 8: return offset
  -1

proc parseGlowIcon*(data: openArray[byte]): WorkbenchGlowIcon =
  let formOffset = findGlowForm(data)
  if formOffset < 0: return
  let formEnd = formOffset + 8 + int(be32(data, formOffset + 4))
  var offset = formOffset + 12
  var width, height: int
  var sharedPalette: seq[array[3, byte]]
  while offset < formEnd:
    requireAvailable(data, offset, 8, "GlowIcons chunk header")
    let kind = fourCc(data, offset)
    let length = int(be32(data, offset + 4))
    requireAvailable(data, offset + 8, length, "GlowIcons " & kind & " chunk")
    let body = offset + 8
    if kind == "FACE":
      if length < 6: raise newException(ValueError, "truncated GlowIcons FACE chunk")
      width = int(data[body]) + 1
      height = int(data[body + 1]) + 1
      result.frameless = (data[body + 2] and 1) != 0
      result.aspectX = int(data[body + 3] shr 4)
      result.aspectY = int(data[body + 3] and 0x0f)
    elif kind == "IMAG":
      if length < 10 or width <= 0 or height <= 0:
        raise newException(ValueError, "GlowIcons IMAG precedes a valid FACE chunk")
      let transparent = int(data[body])
      let colourCount = int(data[body + 1]) + 1
      let flags = data[body + 2]
      let imageFormat = int(data[body + 3])
      let paletteFormat = int(data[body + 4])
      let depth = int(data[body + 5])
      let imageLength = be16(data, body + 6) + 1
      let paletteLength = be16(data, body + 8) + 1
      if depth <= 0 or depth > 8 or imageLength > length - 10:
        raise newException(ValueError, "invalid GlowIcons IMAG properties")
      var imageData = @data[body + 10 ..< body + 10 + imageLength]
      var image = WorkbenchEnhancedImage(width: width, height: height)
      image.pixels = unpackGlowEntries(imageData, imageFormat, depth, width * height)
      if (flags and 2) != 0:
        if paletteLength > length - 10 - imageLength:
          raise newException(ValueError, "truncated GlowIcons palette")
        var paletteData = @data[body + 10 + imageLength ..<
          body + 10 + imageLength + paletteLength]
        let expanded = unpackGlowEntries(paletteData, paletteFormat, 8, colourCount * 3)
        for index in 0 ..< colourCount:
          image.palette.add [expanded[index * 3], expanded[index * 3 + 1],
            expanded[index * 3 + 2]]
        sharedPalette = image.palette
      else:
        image.palette = sharedPalette
      if image.palette.len < colourCount:
        raise newException(ValueError, "GlowIcons image has no usable palette")
      for value in image.pixels:
        if int(value) >= colourCount:
          raise newException(ValueError, "GlowIcons pixel exceeds its palette")
      if (flags and 1) != 0:
        if transparent >= colourCount:
          raise newException(ValueError, "invalid GlowIcons transparent colour")
        image.alpha = newSeq[byte](image.pixels.len)
        for index, value in image.pixels:
          image.alpha[index] = if int(value) == transparent: 0 else: 255
      result.images.add image
    offset = body + length + (length and 1)
