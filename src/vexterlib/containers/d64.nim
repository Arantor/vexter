## Read-only Commodore 1540/1541 D64 disk images.

import std/[sets, strutils]

const
  D64TypeId* = "commodore.d64"
  D64FileTypeId* = "commodore.d64-file"
  D64SectorSize* = 256
  D64StandardSize* = 174_848
  D64StandardErrorSize* = 175_531
  D64ExtendedSize* = 196_608
  D64ExtendedErrorSize* = 197_376

type
  D64FileKind* = enum
    dfkDeleted
    dfkSequential
    dfkProgram
    dfkUser
    dfkRelative

  D64Entry* = object
    name*: string
    kind*: D64FileKind
    closed*, locked*: bool
    startTrack*, startSector*: int
    declaredSectors*, actualSectors*: int
    sideTrack*, sideSector*, recordLength*: int
    data*: seq[byte]

  D64Disk* = object
    tracks*, sectorCount*: int
    hasErrorBytes*: bool
    name*, diskId*, dosType*: string
    dosVersion*: int
    entries*: seq[D64Entry]

proc sectorsOnTrack(track: int): int =
  if track in 1 .. 17: 21
  elif track in 18 .. 24: 19
  elif track in 25 .. 30: 18
  elif track in 31 .. 40: 17
  else: 0

proc sectorIndex(track, sector, tracks: int): int =
  if track < 1 or track > tracks or sector < 0 or
      sector >= sectorsOnTrack(track):
    raise newException(ValueError, "D64 track/sector pointer is out of range")
  for current in 1 ..< track: result += sectorsOnTrack(current)
  result += sector

proc sectorOffset(track, sector, tracks: int): int =
  sectorIndex(track, sector, tracks) * D64SectorSize

proc petsciiText(data: openArray[byte], offset, length: int): string =
  var last = length
  while last > 0 and data[offset + last - 1] in [0'u8, 0xa0'u8, 0x20'u8]:
    dec last
  for index in 0 ..< last:
    let value = data[offset + index]
    if value >= 0x20 and value <= 0x7e and value notin [byte('/'), byte('\\')]:
      result.add char(value)
    else:
      result.add "_" & toHex(int(value), 2)
  if result.len == 0: result = "unnamed"

proc fileKind(value: int): D64FileKind =
  case value
  of 0: dfkDeleted
  of 1: dfkSequential
  of 2: dfkProgram
  of 3: dfkUser
  of 4: dfkRelative
  else: raise newException(ValueError, "unsupported D64 directory file type")

proc extractChain(data: openArray[byte], tracks, startTrack, startSector: int):
    tuple[data: seq[byte], sectors: int] =
  if startTrack == 0: return
  var track = startTrack
  var sector = startSector
  var visited = initHashSet[int]()
  while track != 0:
    let identity = sectorIndex(track, sector, tracks)
    if identity in visited:
      raise newException(ValueError, "cyclic D64 file sector chain")
    visited.incl identity
    inc result.sectors
    let offset = identity * D64SectorSize
    let nextTrack = int(data[offset])
    let nextSector = int(data[offset + 1])
    let amount = if nextTrack == 0:
        if nextSector < 1: 0 else: nextSector - 1
      else: 254
    if amount < 0 or amount > 254:
      raise newException(ValueError, "invalid D64 final-sector length")
    if amount > 0: result.data.add data.toOpenArray(offset + 2, offset + 1 + amount)
    if nextTrack == 0: break
    discard sectorIndex(nextTrack, nextSector, tracks)
    track = nextTrack
    sector = nextSector
    if result.sectors > 768:
      raise newException(ValueError, "D64 file sector chain exceeds disk bounds")

proc parseD64*(data: openArray[byte]): D64Disk =
  case data.len
  of D64StandardSize:
    result.tracks = 35; result.sectorCount = 683
  of D64StandardErrorSize:
    result.tracks = 35; result.sectorCount = 683; result.hasErrorBytes = true
  of D64ExtendedSize:
    result.tracks = 40; result.sectorCount = 768
  of D64ExtendedErrorSize:
    result.tracks = 40; result.sectorCount = 768; result.hasErrorBytes = true
  else:
    raise newException(ValueError, "unsupported D64 image size")
  let bam = sectorOffset(18, 0, result.tracks)
  result.dosVersion = int(data[bam + 2])
  result.name = petsciiText(data, bam + 0x90, 16)
  result.diskId = petsciiText(data, bam + 0xa2, 2)
  result.dosType = petsciiText(data, bam + 0xa5, 2)
  if result.name == "unnamed":
    raise newException(ValueError, "invalid D64 BAM identity")
  for track in 1 .. min(result.tracks, 35):
    let entry = bam + 4 + (track - 1) * 4
    let declaredFree = int(data[entry])
    var bitmapFree = 0
    for sector in 0 ..< sectorsOnTrack(track):
      if (int(data[entry + 1 + sector div 8]) and
          (1 shl (sector mod 8))) != 0:
        inc bitmapFree
    if declaredFree != bitmapFree:
      raise newException(ValueError, "D64 BAM free-sector count disagrees with bitmap")

  var track = 18
  var sector = 1
  var visited = initHashSet[int]()
  var names = initHashSet[string]()
  while track != 0:
    let identity = sectorIndex(track, sector, result.tracks)
    if identity in visited:
      raise newException(ValueError, "cyclic D64 directory sector chain")
    visited.incl identity
    let offset = identity * D64SectorSize
    let nextTrack = int(data[offset])
    let nextSector = int(data[offset + 1])
    for slot in 0 ..< 8:
      let entryOffset = offset + slot * 32
      let encodedType = int(data[entryOffset + 2])
      if encodedType == 0: continue
      let kind = fileKind(encodedType and 0x0f)
      let name = petsciiText(data, entryOffset + 5, 16)
      if name in names:
        raise newException(ValueError, "duplicate D64 directory filename")
      names.incl name
      let startTrack = int(data[entryOffset + 3])
      let startSector = int(data[entryOffset + 4])
      let chain = extractChain(data, result.tracks, startTrack, startSector)
      let declared = int(data[entryOffset + 0x1e]) or
        (int(data[entryOffset + 0x1f]) shl 8)
      if declared > result.sectorCount or chain.sectors > result.sectorCount:
        raise newException(ValueError, "invalid D64 file sector count")
      result.entries.add D64Entry(name: name, kind: kind,
        closed: (encodedType and 0x80) != 0,
        locked: (encodedType and 0x40) != 0,
        startTrack: startTrack, startSector: startSector,
        declaredSectors: declared, actualSectors: chain.sectors,
        sideTrack: int(data[entryOffset + 0x15]),
        sideSector: int(data[entryOffset + 0x16]),
        recordLength: int(data[entryOffset + 0x17]), data: chain.data)
    if nextTrack == 0: break
    discard sectorIndex(nextTrack, nextSector, result.tracks)
    track = nextTrack
    sector = nextSector

proc hasD64Extension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".d64")

proc d64FileKindName*(kind: D64FileKind): string =
  case kind
  of dfkDeleted: "DEL"
  of dfkSequential: "SEQ"
  of dfkProgram: "PRG"
  of dfkUser: "USR"
  of dfkRelative: "REL"
