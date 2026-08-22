## Raster decoding for the FLI/FLC animation family.

import ../archetypes/raster
import ../containers/flic

const
  FlicAnimationTypeId* = "flic.animation"
  FlicAnimationResourcePath* = "/animation"

proc leWord(data: openArray[byte], offset: int): int {.inline.} =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc signedByte(value: byte): int {.inline.} = int(cast[int8](value))
proc signedWord(value: int): int {.inline.} = int(cast[int16](uint16(value)))

proc need(data: openArray[byte], offset, count: int, message: string) =
  if offset < 0 or count < 0 or offset > data.len - count:
    raise newException(ValueError, message)

proc requireEnd(data: openArray[byte], offset: int, message: string) =
  if offset == data.len: return
  if offset + 1 == data.len and data[offset] == 0: return
  raise newException(ValueError, message)

proc decodeHuffman(data: openArray[byte], outputLength: int,
    codes: openArray[FlicHuffmanCode]): seq[byte] =
  result = newSeq[byte](outputLength)
  var bit = 0
  for output in 0 ..< outputLength:
    var code: uint16
    var matched = false
    for length in 1 .. 16:
      if bit >= data.len * 8:
        raise newException(ValueError, "truncated FLIC Huffman data")
      code = code or (uint16((data[bit div 8] shr (7 - bit mod 8)) and 1) shl
        (16 - length))
      inc bit
      for entry in codes:
        if entry.length == length and entry.code == code:
          result[output] = entry.value
          matched = true
          break
      if matched: break
    if not matched:
      raise newException(ValueError, "invalid FLIC Huffman code")

proc inverseLazyMtf(data: var seq[byte]) =
  var table: array[256, byte]
  for index in 0 .. 255: table[index] = byte(index)
  for offset in 0 ..< data.len:
    let current = int(data[offset])
    data[offset] = table[current]
    if current > 0:
      let destination = current div 2
      for index in countdown(current, destination + 1):
        table[index] = table[index - 1]
      table[destination] = data[offset]

proc inverseBwt(data: openArray[byte], primary: int): seq[byte] =
  if data.len == 0:
    if primary != 0: raise newException(ValueError, "invalid empty FLIC BWT index")
    return @[]
  if primary < 0 or primary >= data.len:
    raise newException(ValueError, "invalid FLIC BWT primary index")
  var occurrences: array[256, int]
  var links = newSeq[int](data.len)
  for index, value in data:
    links[index] = occurrences[int(value)]
    inc occurrences[int(value)]
  var sum = 0
  for value in 0 .. 255:
    let count = occurrences[value]
    occurrences[value] = sum
    sum += count
  result = newSeq[byte](data.len)
  var index = primary
  for output in 0 ..< result.len:
    let value = data[index]
    result[output] = value
    index = links[index] + occurrences[int(value)]

proc expandEgi(data: openArray[byte], source: FlicSource): seq[byte] =
  if source.huffmanCodes.len == 0:
    raise newException(ValueError, "compressed FLIC has no Huffman table")
  let useBwt = (source.extensionFlags and 0x10) != 0
  var offset = 0
  while offset < data.len:
    if offset + 1 == data.len and data[offset] == 0: break
    need(data, offset, if useBwt: 6 else: 4, "truncated FLIC compression block")
    let compressed = leWord(data, offset)
    let expanded = leWord(data, offset + 2)
    let header = if useBwt: 6 else: 4
    if compressed <= 0 or expanded <= 0:
      raise newException(ValueError, "invalid empty FLIC compression block")
    need(data, offset + header, compressed, "truncated FLIC compression block")
    var decodedBlock = decodeHuffman(data.toOpenArray(offset + header,
      offset + header + compressed - 1), expanded, source.huffmanCodes)
    if useBwt:
      let primary = leWord(data, offset + 4)
      inverseLazyMtf(decodedBlock)
      decodedBlock = inverseBwt(decodedBlock, primary)
    result.add decodedBlock
    offset += header + compressed

proc decodeRleList(data: openArray[byte], offset: var int,
    outputLength: int): seq[byte] =
  result = newSeq[byte](outputLength)
  var output = 0
  while output < outputLength:
    need(data, offset, 1, "truncated FLIC SHIFT RLE control")
    let control = signedByte(data[offset])
    inc offset
    if control == 0: raise newException(ValueError, "zero-length FLIC SHIFT RLE packet")
    let count = abs(control)
    if count > outputLength - output:
      raise newException(ValueError, "FLIC SHIFT RLE packet exceeds its list")
    if control > 0:
      need(data, offset, 1, "truncated FLIC SHIFT RLE repeat")
      for index in 0 ..< count: result[output + index] = data[offset]
      inc offset
    else:
      need(data, offset, count, "truncated FLIC SHIFT RLE literal")
      for index in 0 ..< count: result[output + index] = data[offset + index]
      offset += count
    output += count

proc applyFrameShift(data: openArray[byte], pixels: var seq[byte], width,
    height, bytesPerPixel: int) =
  need(data, 0, 4, "truncated FLIC SHIFT header")
  if data[0] != 0 or data[1] != 0:
    raise newException(ValueError, "unsupported FLIC mask SHIFT or flags")
  let priorityBytes = leWord(data, 2)
  var offset = 4
  let vertical = decodeRleList(data, offset, height)
  let horizontal = decodeRleList(data, offset, height)
  discard decodeRleList(data, offset, priorityBytes)
  requireEnd(data, offset, "FLIC SHIFT chunk has trailing data")
  let original = pixels
  let rowBytes = width * bytesPerPixel
  for y in 0 ..< height:
    let sourceY = y + signedByte(vertical[y])
    if sourceY < 0 or sourceY >= height:
      raise newException(ValueError, "FLIC vertical SHIFT exceeds frame")
    let shift = signedByte(horizontal[y])
    for x in 0 ..< width:
      let sourceX = min(width - 1, max(0, x - shift))
      for component in 0 ..< bytesPerPixel:
        pixels[y * rowBytes + x * bytesPerPixel + component] =
          original[sourceY * rowBytes + sourceX * bytesPerPixel + component]

proc scale6(value: byte): uint8 = uint8((int(value) * 255 + 31) div 63)

proc applyPalette(data: openArray[byte], palette: var seq[VextRgb], sixBit: bool) =
  need(data, 0, 2, "truncated FLIC palette packet count")
  let packets = leWord(data, 0)
  var offset = 2
  var index = 0
  for unused in 0 ..< packets:
    need(data, offset, 2, "truncated FLIC palette packet")
    index += int(data[offset])
    let storedCount = int(data[offset + 1])
    let count = if storedCount == 0: 256 else: storedCount
    offset += 2
    if index > 256 - count:
      raise newException(ValueError, "FLIC palette packet exceeds 256 entries")
    need(data, offset, count * 3, "truncated FLIC palette colours")
    for colour in 0 ..< count:
      let base = offset + colour * 3
      palette[index + colour] = if sixBit:
          VextRgb(r: scale6(data[base]), g: scale6(data[base + 1]),
            b: scale6(data[base + 2]))
        else: VextRgb(r: data[base], g: data[base + 1], b: data[base + 2])
    index += count
    offset += count * 3
  requireEnd(data, offset, "FLIC palette chunk has trailing data")

proc decodeBrun(data: openArray[byte], pixels: var seq[byte], width, height,
    bytesPerPixel: int, pixelCounts: bool) =
  var offset = 0
  let rowBytes = width * bytesPerPixel
  for y in 0 ..< height:
    need(data, offset, 1, "truncated FLIC BYTE_RUN packet count")
    inc offset
    var x = 0
    while x < rowBytes:
      need(data, offset, 1, "truncated FLIC BYTE_RUN control")
      let control = signedByte(data[offset])
      inc offset
      if control == 0:
        raise newException(ValueError, "zero-length FLIC BYTE_RUN packet")
      let unit = if pixelCounts: bytesPerPixel else: 1
      let count = abs(control) * unit
      if count > rowBytes - x:
        raise newException(ValueError, "FLIC BYTE_RUN packet exceeds its row")
      if control < 0:
        need(data, offset, count, "truncated FLIC BYTE_RUN literal")
        for index in 0 ..< count: pixels[y * rowBytes + x + index] = data[offset + index]
        offset += count
      else:
        need(data, offset, unit, "truncated FLIC BYTE_RUN repeat")
        for repeat in 0 ..< control:
          for index in 0 ..< unit:
            pixels[y * rowBytes + x + repeat * unit + index] = data[offset + index]
        offset += unit
      x += count
  requireEnd(data, offset, "FLIC BYTE_RUN chunk has trailing data")

proc decodeDeltaFli(data: openArray[byte], pixels: var seq[byte], width,
    height: int) =
  need(data, 0, 4, "truncated FLIC DELTA_FLI header")
  var y = leWord(data, 0)
  let lines = leWord(data, 2)
  if y > height - lines:
    raise newException(ValueError, "FLIC DELTA_FLI lines exceed the frame")
  var offset = 4
  for unused in 0 ..< lines:
    need(data, offset, 1, "truncated FLIC DELTA_FLI packet count")
    let packets = int(data[offset])
    inc offset
    var x = 0
    for packet in 0 ..< packets:
      need(data, offset, 2, "truncated FLIC DELTA_FLI packet")
      x += int(data[offset])
      let control = signedByte(data[offset + 1])
      offset += 2
      if x > width:
        raise newException(ValueError, "FLIC DELTA_FLI skip exceeds its row")
      if control > 0:
        if control > width - x: raise newException(ValueError, "FLIC DELTA_FLI literal exceeds its row")
        need(data, offset, control, "truncated FLIC DELTA_FLI literal")
        for index in 0 ..< control: pixels[y * width + x + index] = data[offset + index]
        offset += control
        x += control
      elif control < 0:
        let count = -control
        if count > width - x: raise newException(ValueError, "FLIC DELTA_FLI repeat exceeds its row")
        need(data, offset, 1, "truncated FLIC DELTA_FLI repeat")
        for index in 0 ..< count: pixels[y * width + x + index] = data[offset]
        inc offset
        x += count
    inc y
  requireEnd(data, offset, "FLIC DELTA_FLI chunk has trailing data")

proc decodeDeltaFlc(data: openArray[byte], pixels: var seq[byte], width,
    height, bytesPerPixel: int, autodeskFlx: bool) =
  need(data, 0, 2, "truncated FLIC DELTA_FLC header")
  let lineCount = leWord(data, 0)
  var offset = 2
  var y = 0
  var decodedLines = 0
  let rowBytes = width * bytesPerPixel
  while decodedLines < lineCount:
    need(data, offset, 2, "truncated FLIC DELTA_FLC opcode")
    var opcode = leWord(data, offset)
    offset += 2
    var lastByte = -1
    while (opcode and 0xc000) != 0:
      case opcode and 0xc000
      of 0x8000:
        lastByte = opcode and 0xff
      of 0xc000:
        let skip = -signedWord(opcode)
        if skip <= 0 or skip > height - y:
          raise newException(ValueError, "invalid FLIC DELTA_FLC line skip")
        y += skip
      else:
        raise newException(ValueError, "undefined FLIC DELTA_FLC opcode")
      need(data, offset, 2, "truncated FLIC DELTA_FLC opcode")
      opcode = leWord(data, offset)
      offset += 2
    if opcode > 0x3fff or y >= height:
      raise newException(ValueError, "invalid FLIC DELTA_FLC packet count")
    var x = 0
    for packet in 0 ..< opcode:
      need(data, offset, 2, "truncated FLIC DELTA_FLC packet")
      let rawSkip = int(data[offset])
      let skip = if bytesPerPixel == 2 and autodeskFlx: rawSkip * 2 else: rawSkip
      x += skip
      let control = signedByte(data[offset + 1])
      offset += 2
      if x > rowBytes:
        raise newException(ValueError, "FLIC DELTA_FLC skip exceeds its row")
      let words = abs(control)
      let count = words * 2
      if count > rowBytes - x:
        raise newException(ValueError, "FLIC DELTA_FLC data exceeds its row")
      if control >= 0:
        need(data, offset, count, "truncated FLIC DELTA_FLC literal")
        for index in 0 ..< count: pixels[y * rowBytes + x + index] = data[offset + index]
        offset += count
      else:
        need(data, offset, 2, "truncated FLIC DELTA_FLC repeat")
        for word in 0 ..< words:
          pixels[y * rowBytes + x + word * 2] = data[offset]
          pixels[y * rowBytes + x + word * 2 + 1] = data[offset + 1]
        offset += 2
      x += count
    if lastByte >= 0:
      pixels[y * rowBytes + rowBytes - 1] = byte(lastByte)
    inc y
    inc decodedLines
  requireEnd(data, offset, "FLIC DELTA_FLC chunk has trailing data")

proc decodeDtaLc(data: openArray[byte], pixels: var seq[byte], width, height,
    bytesPerPixel: int) =
  need(data, 0, 2, "truncated FLIC DTA_LC header")
  let lineCount = leWord(data, 0)
  var offset = 2
  var y = 0
  var decodedLines = 0
  let rowBytes = width * bytesPerPixel
  while decodedLines < lineCount:
    need(data, offset, 2, "truncated FLIC DTA_LC line opcode")
    let opcode = signedWord(leWord(data, offset))
    offset += 2
    if opcode < 0:
      let skip = -opcode
      if skip > height - y: raise newException(ValueError, "FLIC DTA_LC line skip exceeds frame")
      y += skip
      continue
    if y >= height: raise newException(ValueError, "FLIC DTA_LC lines exceed frame")
    var x = 0
    for packet in 0 ..< opcode:
      need(data, offset, 2, "truncated FLIC DTA_LC packet")
      x += int(data[offset]) * bytesPerPixel
      let control = signedByte(data[offset + 1])
      offset += 2
      if x > rowBytes: raise newException(ValueError, "FLIC DTA_LC skip exceeds row")
      let count = abs(control) * bytesPerPixel
      if count > rowBytes - x: raise newException(ValueError, "FLIC DTA_LC data exceeds row")
      if control >= 0:
        need(data, offset, count, "truncated FLIC DTA_LC literal")
        for index in 0 ..< count: pixels[y * rowBytes + x + index] = data[offset + index]
        offset += count
      else:
        need(data, offset, bytesPerPixel, "truncated FLIC DTA_LC repeat")
        for repeat in 0 ..< -control:
          for index in 0 ..< bytesPerPixel:
            pixels[y * rowBytes + x + repeat * bytesPerPixel + index] = data[offset + index]
        offset += bytesPerPixel
      x += count
    inc y
    inc decodedLines
  requireEnd(data, offset, "FLIC DTA_LC chunk has trailing data")

proc frameDuration(source: FlicSource, frame: FlicFrame): int =
  if frame.delayMs > 0: return frame.delayMs
  if source.fileMagic == FlicMagicFli:
    max(1, (int(source.speed) * 1000 + 35) div 70)
  else:
    max(1, int(source.speed))

proc decodeTruePixel(data: openArray[byte], offset, depth: int): VextRgb =
  if depth == 24:
    return VextRgb(r: data[offset + 2], g: data[offset + 1], b: data[offset])
  let value = leWord(data, offset)
  VextRgb(r: uint8(((value shr (if depth == 16: 11 else: 10)) and 0x1f) shl 3),
    g: uint8(((value shr 5) and (if depth == 16: 0x3f else: 0x1f)) shl
      (if depth == 16: 2 else: 3)), b: uint8((value and 0x1f) shl 3))

proc decodeFlic*(source: FlicSource): VextRaster =
  let usesEgiCompression = (source.extensionFlags and 0x18) != 0
  if source.fileMagic == FlicMagicCompressed and not usesEgiCompression:
    raise newException(ValueError, "compressed FLIC has no Huffman/BWT flag")
  if source.depth == 1:
    raise newException(ValueError,
      "one-bit DTA pixel packing is not defined by the supplied FLIC document")
  let bytesPerPixel = if source.depth == 8: 1 elif source.depth == 24: 3 else: 2
  let bufferBytes = source.width * source.height * bytesPerPixel
  var pixels = newSeq[byte](bufferBytes)
  var palette = newSeq[VextRgb](256)
  let autodeskFlx = source.fileMagic == FlicMagicFlc and source.depth in [15, 16] and
    source.creator == 0x30314c46'u32

  if source.depth == 8:
    var animation = VextIndexedAnimation(width: source.width, height: source.height)
    for frameIndex in 0 ..< source.frameCount:
      let frame = source.frames[frameIndex]
      if (frame.width != 0 and frame.width != source.width) or
          (frame.height != 0 and frame.height != source.height):
        raise newException(ValueError, "unsupported FLIC main-frame size override")
      var haveOrdinaryImage = false
      for chunk in frame.chunks:
        let chunkData = if usesEgiCompression and chunk.kind in [7, 15, 35]:
            (if chunk.kind == 7:
              block:
                need(chunk.data, 0, 2, "truncated compressed FLIC DELTA_FLC")
                var value = @[chunk.data[0], chunk.data[1]]
                if chunk.data.len > 2:
                  value.add expandEgi(chunk.data.toOpenArray(2, chunk.data.high), source)
                value
             else: expandEgi(chunk.data, source))
          else: chunk.data
        case chunk.kind
        of 4: applyPalette(chunkData, palette, false)
        of 11: applyPalette(chunkData, palette, true)
        of 13:
          for index in 0 ..< pixels.len: pixels[index] = 0
          haveOrdinaryImage = true
        of 15:
          decodeBrun(chunkData, pixels, source.width, source.height, 1, false)
          haveOrdinaryImage = true
        of 16:
          if chunk.data.len < pixels.len or chunk.data.len > pixels.len + 1 or
              (chunk.data.len == pixels.len + 1 and chunk.data[^1] != 0):
            raise newException(ValueError, "invalid FLIC COPY size")
          for index in 0 ..< pixels.len: pixels[index] = chunk.data[index]
          haveOrdinaryImage = true
        of 12:
          decodeDeltaFli(chunk.data, pixels, source.width, source.height)
          haveOrdinaryImage = true
        of 7:
          decodeDeltaFlc(chunkData, pixels, source.width, source.height, 1, false)
          haveOrdinaryImage = true
        of 35:
          if not haveOrdinaryImage:
            decodeBrun(chunkData, pixels, source.width, source.height, 1, false)
        of 36:
          if not haveOrdinaryImage: applyPalette(chunk.data, palette, false)
        of 42: applyFrameShift(chunkData, pixels, source.width, source.height, 1)
        else: discard
      animation.frames.add VextIndexedAnimationFrame(
        image: VextIndexedImage(width: source.width, height: source.height,
          palette: palette, pixels: pixels,
          alpha: if source.transparentIndex >= 0:
              block:
                var values = newSeq[uint8](pixels.len)
                for index, value in pixels:
                  values[index] = if int(value) == source.transparentIndex: 0 else: 255
                values
            else: @[]),
        durationMs: frameDuration(source, frame))
    return VextRaster(kind: vrkIndexedAnimation, animation: animation)

  var animation = VextTrueColourAnimation(width: source.width, height: source.height)
  for frameIndex in 0 ..< source.frameCount:
    let frame = source.frames[frameIndex]
    if (frame.width != 0 and frame.width != source.width) or
        (frame.height != 0 and frame.height != source.height):
      raise newException(ValueError, "unsupported FLIC main-frame size override")
    var haveOrdinaryImage = false
    for chunk in frame.chunks:
      let chunkData = if usesEgiCompression and chunk.kind in [7, 15, 35]:
          (if chunk.kind == 7:
            block:
              need(chunk.data, 0, 2, "truncated compressed FLIC DELTA_FLC")
              var value = @[chunk.data[0], chunk.data[1]]
              if chunk.data.len > 2:
                value.add expandEgi(chunk.data.toOpenArray(2, chunk.data.high), source)
              value
           else: expandEgi(chunk.data, source))
        else: chunk.data
      case chunk.kind
      of 13:
        for index in 0 ..< pixels.len: pixels[index] = 0
        haveOrdinaryImage = true
      of 15:
        decodeBrun(chunkData, pixels, source.width, source.height,
          bytesPerPixel, false)
        haveOrdinaryImage = true
      of 16, 26:
        if chunk.data.len < pixels.len or chunk.data.len > pixels.len + 1 or
            (chunk.data.len == pixels.len + 1 and chunk.data[^1] != 0):
          raise newException(ValueError, "invalid FLIC COPY size")
        for index in 0 ..< pixels.len: pixels[index] = chunk.data[index]
        haveOrdinaryImage = true
      of 7:
        decodeDeltaFlc(chunkData, pixels, source.width, source.height,
          bytesPerPixel, autodeskFlx)
        haveOrdinaryImage = true
      of 25:
        decodeBrun(chunk.data, pixels, source.width, source.height,
          bytesPerPixel, true)
        haveOrdinaryImage = true
      of 27:
        decodeDtaLc(chunk.data, pixels, source.width, source.height, bytesPerPixel)
        haveOrdinaryImage = true
      of 35:
        if not haveOrdinaryImage:
          decodeBrun(chunkData, pixels, source.width, source.height,
            bytesPerPixel, source.fileMagic == FlicMagicDta)
      of 42: applyFrameShift(chunkData, pixels, source.width, source.height,
          bytesPerPixel)
      else: discard
    var image = VextTrueColourImage(width: source.width, height: source.height,
      pixels: newSeq[VextRgb](source.width * source.height))
    for index in 0 ..< image.pixels.len:
      image.pixels[index] = decodeTruePixel(pixels, index * bytesPerPixel, source.depth)
    animation.frames.add VextTrueColourAnimationFrame(image: image,
      durationMs: frameDuration(source, frame))
  VextRaster(kind: vrkTrueColourAnimation, trueColourAnimation: animation)
