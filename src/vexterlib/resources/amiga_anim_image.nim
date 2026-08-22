## Raster reconstruction for IFF ANIM methods 1 through 5, 7, and 8.

import ../archetypes/raster
import ../containers/amiga_anim
import ./amiga_ilbm_image

const AmigaAnimResourcePath* = "/animation"

proc beUnit(data: openArray[byte], offset, size: int): uint32 =
  if offset < 0 or size notin [2, 4] or size > data.len - offset:
    raise newException(ValueError, "truncated ANIM delta value")
  if size == 2:
    return (uint32(data[offset]) shl 8) or uint32(data[offset + 1])
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc putUnit(planes: var seq[byte], offset, rowBytes, planeSize, plane,
    column, row, size: int, value: uint32, xorMode = false) =
  if row < 0 or column < 0 or column + size > rowBytes or
      row >= planeSize div rowBytes:
    raise newException(ValueError, "ANIM delta writes outside its bitmap")
  let target = plane * planeSize + row * rowBytes + column
  for byteIndex in 0 ..< size:
    let component = byte(value shr ((size - byteIndex - 1) * 8))
    if xorMode:
      planes[target + byteIndex] = planes[target + byteIndex] xor component
    else:
      planes[target + byteIndex] = component

proc putClippedUnit(planes: var seq[byte], rowBytes, planeSize, plane,
    column, row, encodedSize: int, value: uint32) =
  let writeSize = min(encodedSize, rowBytes - column)
  if row < 0 or column < 0 or writeSize <= 0 or row >= planeSize div rowBytes:
    raise newException(ValueError, "ANIM delta writes outside its bitmap")
  let target = plane * planeSize + row * rowBytes + column
  for byteIndex in 0 ..< writeSize:
    planes[target + byteIndex] =
      byte(value shr ((encodedSize - byteIndex - 1) * 8))

proc planePointer(delta: openArray[byte], index: int): int =
  int(beUnit(delta, index * 4, 4))

proc signedUnit(data: openArray[byte], offset, size: int): int =
  let value = beUnit(data, offset, size)
  if size == 2:
    int(cast[int16](uint16(value)))
  else:
    int(cast[int32](value))

proc applyMethod1(planes: var seq[byte], body: openArray[byte],
    header: AmigaAnimHeader, source: AmigaIlbmImageSource,
    rowBytes, height, planeCount: int) =
  if header.width <= 0 or header.height <= 0 or header.x < 0 or header.y < 0 or
      header.width > source.header.width - header.x or
      header.height > height - header.y:
    raise newException(ValueError, "ANIM-1 rectangle is outside its bitmap")
  var selectedPlanes: seq[int]
  for plane in 0 ..< planeCount:
    if (header.mask and (1 shl plane)) != 0:
      selectedPlanes.add plane
  if selectedPlanes.len == 0:
    raise newException(ValueError, "ANIM-1 plane mask selects no planes")
  var rectangle = source
  rectangle.header.width = header.width
  rectangle.header.height = header.height
  rectangle.header.planes = selectedPlanes.len
  rectangle.header.masking = AmigaIlbmMaskNone
  rectangle.body = @body
  rectangle.planarLayout = aplRowInterleaved
  let
    decoded = decodeAmigaIlbmPlanes(rectangle)
    rectangleRowBytes = ((header.width + 15) div 16) * 2
    rectanglePlaneSize = rectangleRowBytes * header.height
    planeSize = rowBytes * height
  for packedPlane, destinationPlane in selectedPlanes:
    for y in 0 ..< header.height:
      for x in 0 ..< header.width:
        let sourceByte = decoded[packedPlane * rectanglePlaneSize +
          y * rectangleRowBytes + x div 8]
        if (sourceByte and (0x80'u8 shr (x mod 8))) != 0:
          let
            destinationX = header.x + x
            destination = destinationPlane * planeSize +
              (header.y + y) * rowBytes + destinationX div 8
          planes[destination] = planes[destination] xor
            (0x80'u8 shr (destinationX mod 8))

proc applyMethod23(planes: var seq[byte], delta: openArray[byte],
    rowBytes, height, planeCount, unitSize: int) =
  if delta.len < 32:
    raise newException(ValueError,
      "ANIM-2/3 DLTA is shorter than its plane pointers")
  let planeSize = rowBytes * height
  if planeSize mod unitSize != 0:
    raise newException(ValueError,
      "ANIM-2/3 bitmap plane is not unit-aligned")
  for plane in 0 ..< planeCount:
    var stream = planePointer(delta, plane)
    if stream == 0:
      continue
    if stream < 32 or stream + 2 > delta.len:
      raise newException(ValueError, "invalid ANIM-2/3 plane pointer")
    var unitOffset = 0
    while true:
      if stream + 2 > delta.len:
        raise newException(ValueError, "truncated ANIM-2/3 offset")
      let encodedOffset = int(cast[int16](uint16(beUnit(delta, stream, 2))))
      stream += 2
      if encodedOffset == -1:
        break
      var count = 1
      if encodedOffset < 0:
        # A negative offset introduces a contiguous run. Its magnitude
        # includes the current word, so the run starts magnitude - 1 words
        # beyond the previous destination and leaves the cursor on its last
        # word. This is the convention used by VideoScape method-3 ANIMs.
        unitOffset += -encodedOffset - 1
        if stream + 2 > delta.len:
          raise newException(ValueError, "truncated ANIM-2/3 run count")
        count = int(beUnit(delta, stream, 2))
        stream += 2
      else:
        unitOffset += encodedOffset
      if count < 1 or count > (delta.len - stream) div unitSize or
          unitOffset < 0 or unitOffset + count > planeSize div unitSize:
        raise newException(ValueError, "invalid ANIM-2/3 change run")
      for index in 0 ..< count:
        let
          value = beUnit(delta, stream, unitSize)
          target = plane * planeSize + (unitOffset + index) * unitSize
        stream += unitSize
        for byteIndex in 0 ..< unitSize:
          planes[target + byteIndex] =
            byte(value shr ((unitSize - byteIndex - 1) * 8))
      unitOffset += count - 1

proc applyMethod4(planes: var seq[byte], delta: openArray[byte],
    header: AmigaAnimHeader, rowBytes, height, planeCount: int) =
  if delta.len < 64:
    raise newException(ValueError, "ANIM-4 DLTA is shorter than its pointers")
  if (header.bits and not 0x3f'u32) != 0:
    raise newException(ValueError, "ANIM-4 uses undefined option bits")
  let
    dataSize = if (header.bits and 1) != 0: 4 else: 2
    infoSize = if (header.bits and 0x20) != 0: 4 else: 2
    xorMode = (header.bits and 2) != 0
    runLength = (header.bits and 8) != 0
    vertical = (header.bits and 0x10) != 0
    planeSize = rowBytes * height
    unitsPerRow = rowBytes div dataSize
    unitsPerPlane = planeSize div dataSize
  if rowBytes mod dataSize != 0:
    raise newException(ValueError, "ANIM-4 bitmap row is not data-aligned")
  for plane in 0 ..< planeCount:
    # The reference routine addresses these as offsets from a WORD pointer.
    var dataStream = planePointer(delta, plane) * 2
    var infoStream = planePointer(delta, plane + 8) * 2
    if dataStream == 0:
      continue
    if dataStream < 64 or dataStream >= delta.len or
        infoStream < 64 or infoStream + infoSize > delta.len:
      raise newException(ValueError, "invalid ANIM-4 plane pointers")
    while true:
      let destinationOffset = signedUnit(delta, infoStream, infoSize)
      infoStream += infoSize
      if destinationOffset == -1:
        break
      if destinationOffset < 0 or infoStream + infoSize > delta.len:
        raise newException(ValueError, "invalid ANIM-4 destination offset")
      let encodedCount = signedUnit(delta, infoStream, infoSize)
      infoStream += infoSize
      if encodedCount < 0 and not runLength:
        raise newException(ValueError, "ANIM-4 repeat requires RLC option")
      let count = abs(encodedCount)
      if count == 0:
        continue
      let stride = if vertical: unitsPerRow else: 1
      if destinationOffset >= unitsPerPlane or
          count - 1 > (unitsPerPlane - 1 - destinationOffset) div stride:
        raise newException(ValueError, "ANIM-4 change run exceeds bitmap")
      let requiredData = if encodedCount < 0: dataSize else: count * dataSize
      if requiredData > delta.len - dataStream:
        raise newException(ValueError, "truncated ANIM-4 data stream")
      var repeatedValue: uint32
      if encodedCount < 0:
        repeatedValue = beUnit(delta, dataStream, dataSize)
        dataStream += dataSize
      for index in 0 ..< count:
        let value = if encodedCount < 0: repeatedValue
                    else: beUnit(delta, dataStream, dataSize)
        if encodedCount >= 0:
          dataStream += dataSize
        let target = plane * planeSize +
          (destinationOffset + index * stride) * dataSize
        for byteIndex in 0 ..< dataSize:
          let component = byte(value shr ((dataSize - byteIndex - 1) * 8))
          if xorMode:
            planes[target + byteIndex] = planes[target + byteIndex] xor component
          else:
            planes[target + byteIndex] = component

proc applyMethod5(planes: var seq[byte], delta: openArray[byte],
    header: AmigaAnimHeader, rowBytes, height, planeCount: int) =
  if delta.len < 64:
    raise newException(ValueError, "ANIM-5 DLTA is shorter than its pointers")
  let planeSize = rowBytes * height
  for plane in 0 ..< planeCount:
    var stream = planePointer(delta, plane)
    if stream == 0:
      continue
    if stream < 64 or stream >= delta.len:
      raise newException(ValueError, "invalid ANIM-5 plane pointer")
    for column in 0 ..< rowBytes:
      if stream >= delta.len:
        raise newException(ValueError, "truncated ANIM-5 column")
      let opCount = int(delta[stream])
      inc stream
      var row = 0
      for unused in 0 ..< opCount:
        if stream >= delta.len:
          raise newException(ValueError, "truncated ANIM-5 operation")
        let operation = int(delta[stream])
        inc stream
        if operation == 0:
          if delta.len - stream < 2:
            raise newException(ValueError, "truncated ANIM-5 repeat")
          let count = int(delta[stream])
          let value = delta[stream + 1]
          stream += 2
          for repeat in 0 ..< count:
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
              row, 1, uint32(value), (header.bits and 4) != 0)
            inc row
        elif (operation and 0x80) != 0:
          let count = operation and 0x7f
          if count > delta.len - stream:
            raise newException(ValueError, "truncated ANIM-5 literal")
          for literal in 0 ..< count:
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
              row, 1, uint32(delta[stream]), (header.bits and 4) != 0)
            inc stream
            inc row
        else:
          row += operation
        if row > height:
          raise newException(ValueError, "ANIM-5 column exceeds bitmap height")

proc applyMethod7(planes: var seq[byte], delta: openArray[byte],
    header: AmigaAnimHeader, rowBytes, height, planeCount: int) =
  if delta.len < 64:
    raise newException(ValueError, "ANIM-7 DLTA is shorter than its pointers")
  let
    planeSize = rowBytes * height
    unitSize = if (header.bits and 1) != 0: 4 else: 2
  for plane in 0 ..< planeCount:
    var opStream = planePointer(delta, plane)
    var dataStream = planePointer(delta, plane + 8)
    if opStream == 0 and dataStream == 0:
      continue
    if opStream < 64 or dataStream < 64:
      raise newException(ValueError, "invalid ANIM-7 plane pointers")
    for column in countup(0, rowBytes - 1, unitSize):
      if opStream >= delta.len:
        raise newException(ValueError, "truncated ANIM-7 column")
      let opCount = int(delta[opStream])
      inc opStream
      var row = 0
      for unused in 0 ..< opCount:
        if opStream >= delta.len:
          raise newException(ValueError, "truncated ANIM-7 operation")
        let operation = int(delta[opStream])
        inc opStream
        if operation == 0:
          if opStream >= delta.len:
            raise newException(ValueError, "truncated ANIM-7 repeat")
          let count = int(delta[opStream])
          inc opStream
          let value = beUnit(delta, dataStream, unitSize)
          dataStream += unitSize
          for repeat in 0 ..< count:
            putClippedUnit(planes, rowBytes, planeSize, plane, column,
              row, unitSize, value)
            inc row
        elif (operation and 0x80) != 0:
          let count = operation and 0x7f
          for literal in 0 ..< count:
            let value = beUnit(delta, dataStream, unitSize)
            dataStream += unitSize
            putClippedUnit(planes, rowBytes, planeSize, plane, column,
              row, unitSize, value)
            inc row
        else:
          row += operation
        if row > height:
          raise newException(ValueError, "ANIM-7 column exceeds bitmap height")

proc applyMethod8(planes: var seq[byte], delta: openArray[byte],
    header: AmigaAnimHeader, rowBytes, height, planeCount: int) =
  if delta.len < 64:
    raise newException(ValueError, "ANIM-8 DLTA is shorter than its pointers")
  let planeSize = rowBytes * height
  for plane in 0 ..< planeCount:
    var stream = planePointer(delta, plane)
    if stream == 0:
      continue
    var column = 0
    while column < rowBytes:
      let unitSize =
        if (header.bits and 1) != 0 and column + 4 <= rowBytes: 4 else: 2
      let highBit = if unitSize == 4: 0x80000000'u32 else: 0x8000'u32
      var opCount = int(beUnit(delta, stream, unitSize))
      stream += unitSize
      var row = 0
      while opCount > 0:
        let operation = beUnit(delta, stream, unitSize)
        stream += unitSize
        if operation == 0:
          let count = int(beUnit(delta, stream, unitSize))
          stream += unitSize
          let value = beUnit(delta, stream, unitSize)
          stream += unitSize
          for repeat in 0 ..< count:
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
              row, unitSize, value)
            inc row
        elif (operation and highBit) != 0:
          let count = int(operation and not highBit)
          for literal in 0 ..< count:
            let value = beUnit(delta, stream, unitSize)
            stream += unitSize
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
              row, unitSize, value)
            inc row
        else:
          row += int(operation)
        if row > height:
          raise newException(ValueError, "ANIM-8 column exceeds bitmap height")
        dec opCount
      column += unitSize

proc durationMs(header: AmigaAnimHeader): int =
  max(1, (int(header.relativeTime) * 1000 + 30) div 60)

proc decodeAmigaAnim*(anim: AmigaAnim): VextRaster =
  let
    header = anim.initial.image.header
    rowBytes = ((header.width + 15) div 16) * 2
  var
    source = anim.initial.image
    planarFrames = @[decodeAmigaIlbmPlanes(source)]
    durations = @[if anim.hasInitialHeader: durationMs(anim.initialHeader)
                  else: 17]
    palettes = @[source.colourMap]

  for frameIndex, frame in anim.frames:
    let distance = if frame.header.interleave == 0: 2
                   else: frame.header.interleave
    let referenceIndex = max(0, frameIndex + 1 - distance)
    var planes = planarFrames[referenceIndex]
    if frame.hasColourMap:
      source.colourMap = frame.colourMap
    if frame.hasCamg and frame.camg != source.camg:
      raise newException(ValueError, "ANIM display mode changes are unsupported")
    case frame.header.operation
    of 0:
      source.body = frame.body
      planes = decodeAmigaIlbmPlanes(source)
    of 1:
      applyMethod1(planes, frame.body, frame.header, source, rowBytes,
        header.height, header.planes)
    of 2:
      applyMethod23(planes, frame.delta, rowBytes,
        header.height, header.planes, 4)
    of 3:
      applyMethod23(planes, frame.delta, rowBytes,
        header.height, header.planes, 2)
    of 4:
      applyMethod4(planes, frame.delta, frame.header, rowBytes,
        header.height, header.planes)
    of 5:
      applyMethod5(planes, frame.delta, frame.header, rowBytes,
        header.height, header.planes)
    of 7:
      applyMethod7(planes, frame.delta, frame.header, rowBytes,
        header.height, header.planes)
    of 8:
      applyMethod8(planes, frame.delta, frame.header, rowBytes,
        header.height, header.planes)
    else:
      raise newException(ValueError, "unsupported ANIM delta method: " &
        $frame.header.operation)
    planarFrames.add planes
    palettes.add source.colourMap
    durations.add durationMs(frame.header)

  if (source.camg and AmigaIlbmCamgHam) != 0:
    var animation = VextTrueColourAnimation(
      width: header.width, height: header.height)
    for index, planes in planarFrames:
      source.colourMap = palettes[index]
      animation.frames.add VextTrueColourAnimationFrame(
        image: renderAmigaIlbmHam(source, planes),
        durationMs: durations[index])
    return VextRaster(kind: vrkTrueColourAnimation,
      trueColourAnimation: animation)

  var animation = VextIndexedAnimation(
    width: header.width, height: header.height)
  for index, planes in planarFrames:
    source.colourMap = palettes[index]
    let image = renderAmigaIlbmImage(source, planes)
    animation.frames.add VextIndexedAnimationFrame(
      image: image, durationMs: durations[index])
  VextRaster(kind: vrkIndexedAnimation, animation: animation)
