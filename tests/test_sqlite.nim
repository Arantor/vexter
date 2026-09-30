import std/[strutils, unittest]
import vexterlib

proc putBe16(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value)

proc putBe32(data: var seq[byte], offset, value: int) =
  data[offset] = byte(value shr 24)
  data[offset + 1] = byte(value shr 16)
  data[offset + 2] = byte(value shr 8)
  data[offset + 3] = byte(value)

proc varint(value: int): seq[byte] =
  if value < 128: return @[byte(value)]
  result = @[byte((value shr 7) or 0x80), byte(value and 0x7f)]

proc rowRecord(name: string, age: int): seq[byte] =
  result = @[3'u8, byte(13 + name.len * 2), 1'u8]
  for character in name: result.add byte(character)
  result.add byte(age)

proc schemaRecord(name: string, rootPage: int, sql: string): seq[byte] =
  result = @[6'u8, 23'u8, byte(13 + name.len * 2),
    byte(13 + name.len * 2), 1'u8, byte(13 + sql.len * 2)]
  for value in ["table", name, name]:
    for character in value: result.add byte(character)
  result.add byte(rootPage)
  for character in sql: result.add byte(character)

proc addLeafCell(data: var seq[byte], pageBase: int, cells: var seq[int],
    cursor: var int, rowid: int, payload: seq[byte]) =
  let cell = varint(payload.len) & varint(rowid) & payload
  cursor -= cell.len
  for index, value in cell: data[pageBase + cursor + index] = value
  cells.add cursor

proc sqliteFixture(): seq[byte] =
  const pageSize = 512
  result = newSeq[byte](pageSize * 3)
  for index, value in "SQLite format 3\0": result[index] = byte(value)
  putBe16(result, 16, pageSize)
  result[18] = 1; result[19] = 1
  result[21] = 64; result[22] = 32; result[23] = 32
  putBe32(result, 28, 3)
  putBe32(result, 44, 4)
  putBe32(result, 56, 1)

  let sql = "CREATE TABLE people(name TEXT, age INTEGER)"
  var schemaCells: seq[int]
  var schemaCursor = pageSize
  addLeafCell(result, 0, schemaCells, schemaCursor, 1,
    schemaRecord("people", 2, sql))
  addLeafCell(result, 0, schemaCells, schemaCursor, 2,
    schemaRecord("empty", 3, "CREATE TABLE empty(value TEXT)"))
  result[100] = 13
  putBe16(result, 103, schemaCells.len)
  putBe16(result, 105, schemaCursor)
  for index, cell in schemaCells:
    putBe16(result, 108 + index * 2, cell)

  var rowCells: seq[int]
  var rowCursor = pageSize
  addLeafCell(result, pageSize, rowCells, rowCursor, 1, rowRecord("Ada", 36))
  addLeafCell(result, pageSize, rowCells, rowCursor, 2, rowRecord("Lin", 29))
  result[pageSize] = 13
  putBe16(result, pageSize + 3, rowCells.len)
  putBe16(result, pageSize + 5, rowCursor)
  for index, cell in rowCells:
    putBe16(result, pageSize + 8 + index * 2, cell)
  result[pageSize * 2] = 13
  putBe16(result, pageSize * 2 + 5, pageSize)

suite "SQLite 3 databases":
  test "table schemas and typed rows are exposed without indexes":
    let database = parseSqlite(sqliteFixture())
    check database.pageSize == 512
    check database.tables.len == 2
    check database.tables[0].name == "people"
    check database.tables[0].sql ==
      "CREATE TABLE people(name TEXT, age INTEGER)"
    check database.tables[0].rows.len == 2
    check database.tables[0].rows[0].rowid == 1
    check database.tables[0].rows[0].values[0].text == "Ada"
    check database.tables[0].rows[0].values[1].integer == 36

    let inspection = inspectSource("people.sqlite", sqliteFixture())
    check inspection.selectedFormat.typeId == SqliteTypeId
    check inspection.resources.roots.len == 1
    check inspection.resources.roots[0].path == "/table"
    check inspection.resources.roots[0].children.len == 2
    let table = inspection.resources.roots[0].children[0]
    check table.path == "/table/people"
    check table.kind == vrnkGroup
    check table.children.len == 2
    check table.children[0].path == "/table/people/schema"
    check table.children[0].text ==
      "CREATE TABLE people(name TEXT, age INTEGER)"
    check table.children[1].path == "/table/people/rows"
    check table.children[1].text.contains("Ada")
    let empty = inspection.resources.roots[0].children[1]
    check empty.path == "/table/empty"
    check empty.children.len == 1
    check empty.children[0].path == "/table/empty/schema"

  test "invalid page counts are rejected":
    var fixture = sqliteFixture()
    putBe32(fixture, 28, 4)
    expect ValueError: discard parseSqlite(fixture)
