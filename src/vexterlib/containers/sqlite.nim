## Read-only SQLite 3 database files.  This decoder intentionally exposes
## table b-trees only; index schema entries and index b-trees are not returned.

import std/[strutils, sets]

const
  SqliteTypeId* = "database.sqlite3"
  SqliteTableTypeId* = "database.sqlite3-table"
  SqliteSchemaTypeId* = "database.sqlite3-schema"
  SqliteRowsTypeId* = "database.sqlite3-rows"
  SqliteSignature = "SQLite format 3\0"

type
  SqliteValueKind* = enum
    svkNull, svkInteger, svkFloat, svkText, svkBlob

  SqliteValue* = object
    case kind*: SqliteValueKind
    of svkNull: discard
    of svkInteger: integer*: int64
    of svkFloat: floating*: float64
    of svkText: text*: string
    of svkBlob: blob*: seq[byte]

  SqliteRow* = object
    rowid*: int64
    hasRowid*: bool
    values*: seq[SqliteValue]

  SqliteTable* = object
    name*, sql*: string
    rootPage*: int
    withoutRowid*: bool
    rows*: seq[SqliteRow]

  SqliteDatabase* = object
    pageSize*, usablePageSize*, encoding*, schemaFormat*: int
    userVersion*, applicationId*: int64
    tables*: seq[SqliteTable]

proc be16(data: openArray[byte], offset: int): int =
  if offset < 0 or offset > data.len - 2:
    raise newException(ValueError, "truncated SQLite integer")
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc be32(data: openArray[byte], offset: int): int64 =
  if offset < 0 or offset > data.len - 4:
    raise newException(ValueError, "truncated SQLite integer")
  (int64(data[offset]) shl 24) or (int64(data[offset + 1]) shl 16) or
    (int64(data[offset + 2]) shl 8) or int64(data[offset + 3])

proc readVarint(data: openArray[byte], offset: var int, limit: int): uint64 =
  var value: uint64
  for index in 0 ..< 9:
    if offset >= limit or offset >= data.len:
      raise newException(ValueError, "truncated SQLite varint")
    let current = data[offset]
    inc offset
    if index == 8:
      return (value shl 8) or uint64(current)
    value = (value shl 7) or uint64(current and 0x7f)
    if (current and 0x80) == 0: return value
  raise newException(ValueError, "invalid SQLite varint")

proc signed(value: uint64, bytes: int): int64 =
  if bytes == 8: return cast[int64](value)
  let bits = bytes * 8
  if (value and (1'u64 shl (bits - 1))) != 0:
    int64(value) - int64(1'u64 shl bits)
  else: int64(value)

proc decodeRecord(payload: openArray[byte], encoding: int): seq[SqliteValue] =
  var headerOffset = 0
  let headerSize = int(readVarint(payload, headerOffset, payload.len))
  if headerSize < headerOffset or headerSize > payload.len:
    raise newException(ValueError, "invalid SQLite record header size")
  var serialTypes: seq[uint64]
  while headerOffset < headerSize:
    serialTypes.add readVarint(payload, headerOffset, headerSize)
  if headerOffset != headerSize:
    raise newException(ValueError, "SQLite record header does not end on a field boundary")
  var bodyOffset = headerSize
  for serialType in serialTypes:
    var length = 0
    case serialType
    of 0: result.add SqliteValue(kind: svkNull); continue
    of 1: length = 1
    of 2: length = 2
    of 3: length = 3
    of 4: length = 4
    of 5: length = 6
    of 6, 7: length = 8
    of 8: result.add SqliteValue(kind: svkInteger, integer: 0); continue
    of 9: result.add SqliteValue(kind: svkInteger, integer: 1); continue
    of 10, 11: raise newException(ValueError, "reserved SQLite serial type")
    else: length = int((serialType - 12) div 2)
    if length < 0 or bodyOffset > payload.len - length:
      raise newException(ValueError, "truncated SQLite record body")
    if serialType in 1'u64 .. 6'u64:
      var value: uint64
      for index in 0 ..< length:
        value = (value shl 8) or uint64(payload[bodyOffset + index])
      result.add SqliteValue(kind: svkInteger, integer: signed(value, length))
    elif serialType == 7:
      var bits: uint64
      for index in 0 ..< 8: bits = (bits shl 8) or uint64(payload[bodyOffset + index])
      result.add SqliteValue(kind: svkFloat, floating: cast[float64](bits))
    elif (serialType and 1) == 0:
      var blob = newSeq[byte](length)
      for index in 0 ..< length: blob[index] = payload[bodyOffset + index]
      result.add SqliteValue(kind: svkBlob, blob: blob)
    else:
      if encoding != 1:
        raise newException(ValueError, "only UTF-8 SQLite text encoding is currently supported")
      var text = newString(length)
      for index in 0 ..< length: text[index] = char(payload[bodyOffset + index])
      result.add SqliteValue(kind: svkText, text: text)
    bodyOffset += length
  if bodyOffset != payload.len:
    raise newException(ValueError, "SQLite record has trailing body bytes")

proc parseSqliteData(data: seq[byte]): SqliteDatabase =
  if data.len < 100: raise newException(ValueError, "truncated SQLite database header")
  for index, value in SqliteSignature:
    if data[index] != byte(value): raise newException(ValueError, "invalid SQLite signature")
  let encodedPageSize = be16(data, 16)
  result.pageSize = if encodedPageSize == 1: 65536 else: encodedPageSize
  if result.pageSize < 512 or result.pageSize > 65536 or
      (result.pageSize and (result.pageSize - 1)) != 0:
    raise newException(ValueError, "invalid SQLite page size")
  if data[18] != 1 or data[19] != 1:
    raise newException(ValueError, "unsupported SQLite read/write version")
  if data[21] != 64 or data[22] != 32 or data[23] != 32:
    raise newException(ValueError, "unsupported SQLite payload fractions")
  result.usablePageSize = result.pageSize - int(data[20])
  if result.usablePageSize < 480:
    raise newException(ValueError, "invalid SQLite reserved space")
  if data.len mod result.pageSize != 0:
    raise newException(ValueError, "SQLite file is not a whole number of pages")
  let pageCount = data.len div result.pageSize
  let declaredPages = int(be32(data, 28))
  if declaredPages != 0 and declaredPages != pageCount:
    raise newException(ValueError, "SQLite page count does not match file size")
  result.schemaFormat = int(be32(data, 44))
  result.encoding = int(be32(data, 56))
  result.userVersion = be32(data, 60)
  result.applicationId = be32(data, 68)
  if result.schemaFormat notin 1 .. 4:
    raise newException(ValueError, "unsupported SQLite schema format")
  if result.encoding == 0: result.encoding = 1
  if result.encoding != 1:
    raise newException(ValueError, "only UTF-8 SQLite databases are currently supported")
  let databasePageSize = result.pageSize
  let databaseUsablePageSize = result.usablePageSize
  let databaseEncoding = result.encoding

  proc pageOffset(page: int): int =
    if page < 1 or page > pageCount: raise newException(ValueError, "SQLite page number is out of range")
    (page - 1) * databasePageSize

  proc payloadBytes(cellOffset: var int, payloadSize: int,
      tableLeaf: bool, cellLimit: int): seq[byte] =
    if payloadSize < 0 or payloadSize > data.len:
      raise newException(ValueError, "invalid SQLite cell payload size")
    let maximumLocal = if tableLeaf: databaseUsablePageSize - 35
      else: ((databaseUsablePageSize - 12) * 64 div 255) - 23
    let minimumLocal = ((databaseUsablePageSize - 12) * 32 div 255) - 23
    var local = payloadSize
    if payloadSize > maximumLocal:
      let candidate = minimumLocal + (payloadSize - minimumLocal) mod
        (databaseUsablePageSize - 4)
      local = if candidate <= maximumLocal: candidate else: minimumLocal
    if cellOffset > cellLimit - local:
      raise newException(ValueError, "truncated SQLite local payload")
    if local > 0:
      result.add data.toOpenArray(cellOffset, cellOffset + local - 1)
    cellOffset += local
    if local == payloadSize: return
    if cellOffset > cellLimit - 4:
      raise newException(ValueError, "missing SQLite overflow pointer")
    var overflow = int(be32(data, cellOffset))
    var visited = initHashSet[int]()
    while result.len < payloadSize:
      if overflow in visited: raise newException(ValueError, "cyclic SQLite overflow chain")
      visited.incl overflow
      let offset = pageOffset(overflow)
      let following = int(be32(data, offset))
      let amount = min(payloadSize - result.len, databaseUsablePageSize - 4)
      if offset + 4 > data.len - amount: raise newException(ValueError, "truncated SQLite overflow page")
      result.add data.toOpenArray(offset + 4, offset + 3 + amount)
      overflow = following
      if overflow == 0 and result.len < payloadSize:
        raise newException(ValueError, "short SQLite overflow chain")

  proc readBtree(rootPage: int, withoutRowid: bool): seq[SqliteRow] =
    var visited = initHashSet[int]()
    var rows: seq[SqliteRow]
    proc visit(page, depth: int) =
      if depth > min(pageCount, 1024):
        raise newException(ValueError, "SQLite b-tree nesting is excessive")
      if page in visited: raise newException(ValueError, "cyclic SQLite b-tree")
      visited.incl page
      let base = pageOffset(page)
      let header = base + (if page == 1: 100 else: 0)
      if header >= data.len: raise newException(ValueError, "truncated SQLite b-tree page")
      let kind = int(data[header])
      let interior = kind in [2, 5]
      let expected = if withoutRowid: [2, 10] else: [5, 13]
      if kind notin expected:
        raise newException(ValueError, "table root has an unexpected SQLite b-tree page kind")
      let headerSize = if interior: 12 else: 8
      let cells = be16(data, header + 3)
      if header + headerSize + cells * 2 > base + databasePageSize:
        raise newException(ValueError, "SQLite cell pointer array is out of range")
      for index in 0 ..< cells:
        let relative = be16(data, header + headerSize + index * 2)
        var cursor = base + relative
        if relative < (if page == 1: 100 else: 0) or cursor >= base + databaseUsablePageSize:
          raise newException(ValueError, "SQLite cell offset is out of range")
        if interior:
          let child = int(be32(data, cursor)); cursor += 4
          visit(child, depth + 1)
          if kind == 5: discard readVarint(data, cursor, base + databaseUsablePageSize)
        if kind in [10, 13] or (kind == 2 and withoutRowid):
          let payloadSize = int(readVarint(data, cursor, base +
              databaseUsablePageSize))
          var row = SqliteRow(hasRowid: not withoutRowid)
          if kind == 13:
            row.rowid = cast[int64](readVarint(data, cursor, base +
                databaseUsablePageSize))
          let payload = payloadBytes(cursor, payloadSize, kind == 13,
            base + databaseUsablePageSize)
          row.values = decodeRecord(payload, databaseEncoding)
          rows.add row
      if interior: visit(int(be32(data, header + 8)), depth + 1)
    visit(rootPage, 1)
    result = move(rows)

  let schemaRows = readBtree(1, false)
  for row in schemaRows:
    if row.values.len != 5 or row.values[0].kind != svkText or
        row.values[0].text != "table": continue
    if row.values[1].kind != svkText or row.values[3].kind !=
        svkInteger: continue
    let sql = if row.values[4].kind == svkText: row.values[4].text else: ""
    let rootPage = int(row.values[3].integer)
    if rootPage == 0: continue # Virtual tables have no on-disk table b-tree.
    let withoutRowid = sql.toUpperAscii.contains("WITHOUT ROWID")
    result.tables.add SqliteTable(name: row.values[1].text, sql: sql,
      rootPage: rootPage, withoutRowid: withoutRowid,
      rows: readBtree(rootPage, withoutRowid))

proc parseSqlite*(data: openArray[byte]): SqliteDatabase =
  ## Copies the source once so bounded recursive b-tree readers can safely
  ## retain it in closures under Nim's memory-safety rules.
  parseSqliteData(@data)

proc isSqlite*(data: openArray[byte]): bool =
  if data.len < SqliteSignature.len: return false
  for index, value in SqliteSignature:
    if data[index] != byte(value): return false
  true

proc hasSqliteExtension*(filename: string): bool =
  filename.toLowerAscii.endsWith(".sqlite") or
    filename.toLowerAscii.endsWith(".sqlite3") or
    filename.toLowerAscii.endsWith(".db")

proc sqliteValueText*(value: SqliteValue): string =
  case value.kind
  of svkNull: result = "NULL"
  of svkInteger: result = $value.integer
  of svkFloat: result = $value.floating
  of svkText: result = value.text
  of svkBlob:
    result = "x'"
    for item in value.blob: result.add item.int.toHex(2)
    result.add "'"
