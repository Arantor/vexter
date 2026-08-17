## Raster reconstruction for IFF ANIM methods 5, 7, and 8.

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

proc planePointer(delta: openArray[byte], index: int): int =
  int(beUnit(delta, index * 4, 4))

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
  if rowBytes mod unitSize != 0:
    raise newException(ValueError, "ANIM-7 row width is not unit-aligned")
  for plane in 0 ..< planeCount:
    var opStream = planePointer(delta, plane)
    var dataStream = planePointer(delta, plane + 8)
    if opStream == 0 and dataStream == 0:
      continue
    if opStream < 64 or dataStream < 64:
      raise newException(ValueError, "invalid ANIM-7 plane pointers")
    for column in countup(0, rowBytes - unitSize, unitSize):
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
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
              row, unitSize, value)
            inc row
        elif (operation and 0x80) != 0:
          let count = operation and 0x7f
          for literal in 0 ..< count:
            let value = beUnit(delta, dataStream, unitSize)
            dataStream += unitSize
            putUnit(planes, 0, rowBytes, planeSize, plane, column,
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
    if animation.frames.len > 0 and
        image.palette != animation.frames[0].image.palette:
      raise newException(ValueError,
        "indexed ANIM palette changes are not supported for GIF export")
    animation.frames.add VextIndexedAnimationFrame(
      image: image, durationMs: durations[index])
  VextRaster(kind: vrkIndexedAnimation, animation: animation)
