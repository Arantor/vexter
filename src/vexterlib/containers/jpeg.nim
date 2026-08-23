## Native JPEG/JFIF framing and bounded EXIF orientation parsing.

import std/[strutils, sets]

const
  JpegTypeId* = "jpeg"
  JpegImageTypeId* = "jpeg.image"
  JpegImageResourcePath* = "/image"

type
  JpegComponent* = object
    identifier*: int
    horizontalSampling*, verticalSampling*: int
    quantizationTable*: int

  JpegExifEntry* = object
    key*, value*: string

  JpegSource* = object
    data*: seq[byte]
    width*, height*: int
    precision*: int
    frameMarker*: int
    components*: seq[JpegComponent]
    orientation*: int
    hasExif*: bool
    exifValid*: bool
    exifError*: string
    exifMetadata*: seq[JpegExifEntry]
    hasJfif*: bool
    jfifMajor*, jfifMinor*: int
    densityUnits*, xDensity*, yDensity*: int

proc beWord(data: openArray[byte], offset: int): int {.inline.} =
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc tiffWord(data: openArray[byte], offset: int, little: bool): int =
  if offset < 0 or offset + 2 > data.len:
    raise newException(ValueError, "truncated EXIF unsigned short")
  if little: int(data[offset]) or (int(data[offset + 1]) shl 8)
  else: (int(data[offset]) shl 8) or int(data[offset + 1])

proc tiffDword(data: openArray[byte], offset: int, little: bool): uint32 =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "truncated EXIF unsigned long")
  if little:
    uint32(data[offset]) or (uint32(data[offset + 1]) shl 8) or
      (uint32(data[offset + 2]) shl 16) or (uint32(data[offset + 3]) shl 24)
  else:
    (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
      (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc signedWord(value: int): int =
  if value > 0x7fff: value - 0x10000 else: value

proc signedDword(value: uint32): int64 =
  if value > 0x7fffffff'u32: int64(value) - 0x1_0000_0000'i64
  else: int64(value)

proc exifTagName(tag: int, prefix: string): string =
  if prefix == "exif.gps.":
    return case tag
      of 0x0000: "version"
      of 0x0001: "latitude-reference"
      of 0x0002: "latitude"
      of 0x0003: "longitude-reference"
      of 0x0004: "longitude"
      of 0x0005: "altitude-reference"
      of 0x0006: "altitude"
      of 0x0007: "time-stamp"
      of 0x0008: "satellites"
      of 0x0009: "status"
      of 0x000a: "measurement-mode"
      of 0x000b: "dilution-of-precision"
      of 0x000c: "speed-reference"
      of 0x000d: "speed"
      of 0x000e: "track-reference"
      of 0x000f: "track"
      of 0x0010: "image-direction-reference"
      of 0x0011: "image-direction"
      of 0x0012: "map-datum"
      of 0x001b: "processing-method"
      of 0x001c: "area-information"
      of 0x001d: "date-stamp"
      of 0x001e: "differential"
      of 0x001f: "horizontal-positioning-error"
      else: "tag-0x" & toHex(tag, 4)
  case tag
  of 0x0001: "interoperability-index"
  of 0x0002: "interoperability-version"
  of 0x0100: "image-width"
  of 0x0101: "image-height"
  of 0x0102: "bits-per-sample"
  of 0x0103: "compression"
  of 0x0106: "photometric-interpretation"
  of 0x010e: "image-description"
  of 0x010f: "make"
  of 0x0110: "model"
  of 0x0112: "orientation"
  of 0x011a: "x-resolution"
  of 0x011b: "y-resolution"
  of 0x0128: "resolution-unit"
  of 0x0131: "software"
  of 0x0132: "date-time"
  of 0x013b: "artist"
  of 0x0201: "jpeg-thumbnail-offset"
  of 0x0202: "jpeg-thumbnail-length"
  of 0x0213: "ycbcr-positioning"
  of 0x8298: "copyright"
  of 0x829a: "exposure-time"
  of 0x829d: "f-number"
  of 0x8769: "photo-ifd-offset"
  of 0x8822: "exposure-program"
  of 0x8825: "gps-ifd-offset"
  of 0x8827: "iso-speed"
  of 0x8830: "sensitivity-type"
  of 0x8832: "recommended-exposure-index"
  of 0x9000: "exif-version"
  of 0x9003: "date-time-original"
  of 0x9004: "date-time-digitized"
  of 0x9101: "components-configuration"
  of 0x9102: "compressed-bits-per-pixel"
  of 0x9201: "shutter-speed-value"
  of 0x9202: "aperture-value"
  of 0x9203: "brightness-value"
  of 0x9204: "exposure-bias-value"
  of 0x9205: "maximum-aperture-value"
  of 0x9206: "subject-distance"
  of 0x9207: "metering-mode"
  of 0x9208: "light-source"
  of 0x9209: "flash"
  of 0x920a: "focal-length"
  of 0x927c: "maker-note"
  of 0x9286: "user-comment"
  of 0x9290: "subsecond-time"
  of 0x9291: "subsecond-time-original"
  of 0x9292: "subsecond-time-digitized"
  of 0xa000: "flashpix-version"
  of 0xa001: "colour-space"
  of 0xa002: "image-width"
  of 0xa003: "image-height"
  of 0xa005: "interoperability-ifd-offset"
  of 0xa20e: "focal-plane-x-resolution"
  of 0xa20f: "focal-plane-y-resolution"
  of 0xa210: "focal-plane-resolution-unit"
  of 0xa215: "exposure-index"
  of 0xa217: "sensing-method"
  of 0xa300: "file-source"
  of 0xa301: "scene-type"
  of 0xa401: "custom-rendered"
  of 0xa402: "exposure-mode"
  of 0xa403: "white-balance"
  of 0xa404: "digital-zoom-ratio"
  of 0xa405: "focal-length-35mm"
  of 0xa406: "scene-capture-type"
  of 0xa407: "gain-control"
  of 0xa408: "contrast"
  of 0xa409: "saturation"
  of 0xa40a: "sharpness"
  of 0xa40c: "subject-distance-range"
  of 0xa434: "lens-model"
  else: "tag-0x" & toHex(tag, 4)

proc rationalText(numerator, denominator: int64, tag: int): string =
  if denominator == 0: return $numerator & "/0"
  var common = 0'i64
  var left = abs(numerator)
  var right = abs(denominator)
  while right != 0:
    common = left mod right
    left = right
    right = common
  let divisor = max(1'i64, left)
  let reducedNumerator = numerator div divisor
  let reducedDenominator = denominator div divisor
  let value = float(numerator) / float(denominator)
  case tag
  of 0x829a:
    if reducedNumerator == 1: "1/" & $reducedDenominator & " s"
    else: $reducedNumerator & "/" & $reducedDenominator & " s (" &
      formatFloat(value, ffDecimal, 6).strip(leading = false, chars = {'0'}) & ")"
  of 0x829d: "f/" & formatFloat(value, ffDecimal, 2).strip(
    leading = false, chars = {'0'}).strip(chars = {'.'})
  of 0x920a: formatFloat(value, ffDecimal, 3).strip(
    leading = false, chars = {'0'}).strip(chars = {'.'}) & " mm"
  else: $reducedNumerator & "/" & $reducedDenominator & " (" &
    formatFloat(value, ffDecimal, 6).strip(leading = false, chars = {'0'}).
      strip(chars = {'.'}) & ")"

proc enumText(tag, value: int64): string =
  var description = ""
  case tag
  of 0x0112:
    description = case value
      of 1: "top-left"
      of 2: "top-right"
      of 3: "bottom-right"
      of 4: "bottom-left"
      of 5: "left-top"
      of 6: "right-top"
      of 7: "right-bottom"
      of 8: "left-bottom"
      else: "unknown"
  of 0x0128, 0xa210:
    description = case value
      of 1: "none"
      of 2: "inch"
      of 3: "centimetre"
      else: "unknown"
  of 0x8822:
    description = case value
      of 0: "not defined"
      of 1: "manual"
      of 2: "normal program"
      of 3: "aperture priority"
      of 4: "shutter priority"
      of 5: "creative program"
      of 6: "action program"
      of 7: "portrait mode"
      of 8: "landscape mode"
      else: "unknown"
  of 0x9207:
    description = case value
      of 0: "unknown"
      of 1: "average"
      of 2: "centre-weighted average"
      of 3: "spot"
      of 4: "multi-spot"
      of 5: "pattern"
      of 6: "partial"
      of 255: "other"
      else: "unknown"
  of 0x0103:
    description = if value == 1: "uncompressed"
      elif value == 6: "JPEG" else: "unknown"
  of 0x0213:
    description = if value == 1: "centred"
      elif value == 2: "co-sited" else: "unknown"
  of 0x9208:
    description = if value == 0: "unknown"
      elif value == 1: "daylight" elif value == 4: "flash" else: "other"
  of 0x9209:
    description = if (value and 1) != 0: "fired" else: "did not fire"
  of 0xa001:
    description = if value == 1: "sRGB"
      elif value == 65535: "uncalibrated" else: "unknown"
  of 0xa217:
    description = if value == 2: "one-chip colour area sensor" else: "other"
  of 0xa401:
    description = if value == 0: "normal"
      elif value == 1: "custom" else: "unknown"
  of 0xa402:
    description = case value
      of 0: "auto exposure"
      of 1: "manual exposure"
      of 2: "auto bracket"
      else: "unknown"
  of 0xa403:
    description = if value == 0: "auto"
      elif value == 1: "manual" else: "unknown"
  of 0xa406:
    description = case value
      of 0: "standard"
      of 1: "landscape"
      of 2: "portrait"
      of 3: "night scene"
      else: "unknown"
  of 0xa408, 0xa409, 0xa40a:
    description = case value
      of 0: "normal"
      of 1: "soft/low"
      of 2: "hard/high"
      else: "unknown"
  of 0xa40c:
    description = case value
      of 0: "unknown"
      of 1: "macro"
      of 2: "close"
      of 3: "distant"
      else: "unknown"
  else: discard
  if description.len == 0: $value else: $value & " (" & description & ")"

type ExifParseResult = object
  orientation: int
  metadata: seq[JpegExifEntry]

proc parseExif(payload: seq[byte]): ExifParseResult =
  if payload.len < 14:
    raise newException(ValueError, "EXIF APP1 segment is too short")
  let little = if payload[6] == byte('I') and payload[7] == byte('I'): true
    elif payload[6] == byte('M') and payload[7] == byte('M'): false
    else: raise newException(ValueError, "invalid EXIF TIFF byte order")
  if payload.tiffWord(8, little) != 42:
    raise newException(ValueError, "invalid EXIF TIFF identifier")
  var parsed = ExifParseResult(orientation: 1)
  var visited = initHashSet[int]()
  proc readIfd(relative: uint32, prefix: string, depth: int): uint32 =
    if depth > 4 or relative > uint32(high(int) - 6):
      raise newException(ValueError, "EXIF IFD nesting or offset is invalid")
    let ifd = 6 + int(relative)
    if ifd in visited:
      raise newException(ValueError, "cyclic EXIF IFD reference")
    visited.incl ifd
    let count = payload.tiffWord(ifd, little)
    if count > 4096 or ifd + 2 > payload.len - count * 12:
      raise newException(ValueError, "invalid EXIF IFD bounds")
    for index in 0 ..< count:
      let entry = ifd + 2 + index * 12
      let tag = payload.tiffWord(entry, little)
      let kind = payload.tiffWord(entry + 2, little)
      let itemCount = payload.tiffDword(entry + 4, little)
      let sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8]
      if kind notin 1 .. 12: continue
      if itemCount > 1_000_000'u32 div uint32(sizes[kind]):
        raise newException(ValueError, "oversized EXIF field")
      let byteCount = int(itemCount) * sizes[kind]
      var valueOffset = entry + 8
      if byteCount > 4:
        let relativeValue = payload.tiffDword(entry + 8, little)
        if relativeValue > uint32(high(int) - 6):
          raise newException(ValueError, "EXIF value offset is too large")
        valueOffset = 6 + int(relativeValue)
      if valueOffset < 0 or byteCount > payload.len or
          valueOffset > payload.len - byteCount:
        raise newException(ValueError, "EXIF field is outside APP1 bounds")
      if tag in [0x8769, 0x8825, 0xa005] and kind == 4 and itemCount == 1:
        let target = payload.tiffDword(valueOffset, little)
        let targetPrefix = if tag == 0x8769: "exif.photo."
          elif tag == 0x8825: "exif.gps."
          else: "exif.interoperability."
        discard readIfd(target, targetPrefix, depth + 1)
        continue
      let name = prefix & exifTagName(tag, prefix)
      var text = ""
      case kind
      of 2:
        for position in valueOffset ..< valueOffset + byteCount:
          if payload[position] == 0: break
          if payload[position] >= 0x20 and payload[position] < 0x7f:
            text.add char(payload[position])
        text = text.strip
      of 1, 3, 4, 6, 8, 9:
        var values: seq[string]
        for item in 0 ..< min(int(itemCount), 32):
          let position = valueOffset + item * sizes[kind]
          let value = case kind
            of 1: int64(payload[position])
            of 3: int64(payload.tiffWord(position, little))
            of 4: int64(payload.tiffDword(position, little))
            of 6: int64(cast[int8](payload[position]))
            of 8: int64(signedWord(payload.tiffWord(position, little)))
            else: signedDword(payload.tiffDword(position, little))
          values.add(if itemCount == 1: enumText(tag, value) else: $value)
        text = values.join(", ")
      of 5, 10:
        var values: seq[string]
        for item in 0 ..< min(int(itemCount), 16):
          let position = valueOffset + item * 8
          let numerator = if kind == 5: int64(payload.tiffDword(position, little))
            else: signedDword(payload.tiffDword(position, little))
          let denominator = if kind == 5:
              int64(payload.tiffDword(position + 4, little))
            else: signedDword(payload.tiffDword(position + 4, little))
          values.add rationalText(numerator, denominator, tag)
        text = values.join(", ")
      of 7:
        if tag in [0x9000, 0xa000, 0x0002] and byteCount <= 16:
          for position in valueOffset ..< valueOffset + byteCount:
            if payload[position] >= 0x20 and payload[position] < 0x7f:
              text.add char(payload[position])
        elif tag == 0x9101 and byteCount <= 4:
          let names = ["", "Y", "Cb", "Cr", "R", "G", "B"]
          var components: seq[string]
          for position in valueOffset ..< valueOffset + byteCount:
            let component = int(payload[position])
            if component in 1 .. 6: components.add names[component]
          text = components.join(", ")
        elif tag == 0xa300 and byteCount == 1:
          text = $payload[valueOffset] & (if payload[valueOffset] == 3:
            " (digital still camera)" else: "")
        elif tag == 0xa301 and byteCount == 1:
          text = $payload[valueOffset] & (if payload[valueOffset] == 1:
            " (directly photographed)" else: "")
        else:
          text = "binary data (" & $byteCount & " bytes)"
      else:
        text = "binary numeric data (" & $byteCount & " bytes)"
      if text.len > 0:
        parsed.metadata.add JpegExifEntry(key: name, value: text)
      if tag == 0x0112 and prefix == "exif.ifd0." and kind == 3 and
          itemCount == 1:
        parsed.orientation = payload.tiffWord(valueOffset, little)
        if parsed.orientation notin 1 .. 8:
          raise newException(ValueError, "EXIF orientation is outside 1 through 8")
    let nextOffsetPosition = ifd + 2 + count * 12
    if nextOffsetPosition > payload.len - 4:
      raise newException(ValueError, "truncated EXIF next-IFD offset")
    payload.tiffDword(nextOffsetPosition, little)
  let ifd0Relative = payload.tiffDword(10, little)
  let thumbnailOffset = readIfd(ifd0Relative, "exif.ifd0.", 0)
  if thumbnailOffset != 0:
    discard readIfd(thumbnailOffset, "exif.thumbnail.", 0)
  result = parsed

proc parseJpeg*(data: openArray[byte]): JpegSource =
  if data.len < 4 or data[0] != 0xff or data[1] != 0xd8:
    raise newException(ValueError, "invalid JPEG start-of-image marker")
  result.data = @data
  result.orientation = 1
  var offset = 2
  var sawFrame, sawScan, sawEnd: bool
  while offset < data.len:
    if data[offset] != 0xff:
      if sawScan:
        inc offset
        continue
      raise newException(ValueError, "JPEG marker prefix was expected")
    while offset < data.len and data[offset] == 0xff: inc offset
    if offset >= data.len:
      raise newException(ValueError, "truncated JPEG marker")
    let marker = int(data[offset]); inc offset
    if marker == 0x00:
      if sawScan: continue
      raise newException(ValueError, "unexpected stuffed JPEG byte")
    if marker == 0xd9:
      sawEnd = true
      if offset != data.len:
        raise newException(ValueError, "JPEG has data after end-of-image")
      break
    if marker in 0xd0 .. 0xd8 or marker == 0x01:
      continue
    if offset + 2 > data.len:
      raise newException(ValueError, "truncated JPEG segment length")
    let length = data.beWord(offset)
    if length < 2 or offset > data.len - length:
      raise newException(ValueError, "invalid JPEG segment bounds")
    let start = offset + 2
    let finish = offset + length
    case marker
    of 0xe0:
      if length >= 16 and data[start] == byte('J') and
          data[start + 1] == byte('F') and data[start + 2] == byte('I') and
          data[start + 3] == byte('F') and data[start + 4] == 0:
        result.hasJfif = true
        result.jfifMajor = int(data[start + 5])
        result.jfifMinor = int(data[start + 6])
        result.densityUnits = int(data[start + 7])
        result.xDensity = data.beWord(start + 8)
        result.yDensity = data.beWord(start + 10)
    of 0xe1:
      if length >= 8 and data[start] == byte('E') and
          data[start + 1] == byte('x') and data[start + 2] == byte('i') and
          data[start + 3] == byte('f') and data[start + 4] == 0 and
          data[start + 5] == 0 and not result.hasExif:
        result.hasExif = true
        var payload: seq[byte]
        payload.add data.toOpenArray(start, finish - 1)
        try:
          let exif = parseExif(payload)
          result.orientation = exif.orientation
          result.exifMetadata = exif.metadata
          result.exifValid = true
        except ValueError as error:
          result.exifError = error.msg
    of 0xc0, 0xc1, 0xc2:
      if sawFrame or length < 8:
        raise newException(ValueError, "invalid or duplicate JPEG frame header")
      sawFrame = true
      result.frameMarker = marker
      result.precision = int(data[start])
      result.height = data.beWord(start + 1)
      result.width = data.beWord(start + 3)
      let count = int(data[start + 5])
      if count notin [1, 3] or length != 8 + count * 3 or
          result.width <= 0 or result.height <= 0 or
          result.width > 65535 or result.height > 65535 or
          result.width > 100_000_000 div result.height:
        raise newException(ValueError, "invalid or unsupported JPEG frame dimensions")
      for index in 0 ..< count:
        let item = start + 6 + index * 3
        let sampling = int(data[item + 1])
        let horizontal = sampling shr 4
        let vertical = sampling and 0x0f
        if horizontal notin 1 .. 4 or vertical notin 1 .. 4:
          raise newException(ValueError, "invalid JPEG component sampling")
        result.components.add JpegComponent(identifier: int(data[item]),
          horizontalSampling: horizontal, verticalSampling: vertical,
          quantizationTable: int(data[item + 2]))
    of 0xda:
      sawScan = true
    else: discard
    offset = finish
  if not sawFrame or not sawScan or not sawEnd:
    raise newException(ValueError, "JPEG is missing a frame, scan, or end marker")
  if result.precision != 8 or result.frameMarker notin [0xc0, 0xc1, 0xc2]:
    raise newException(ValueError, "unsupported JPEG coding process")

proc hasJpegExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".jpg") or
    filename.toLowerAscii.endsWith(".jpeg") or
    filename.toLowerAscii.endsWith(".jpe")
