import std/[strutils, unittest]
import vexterlib

proc addDword(data: var seq[byte], value: int) =
  for shift in [0, 8, 16, 24]:
    data.add byte(value shr shift)

proc fixture(): seq[byte] =
  let manifest = "{\"files\":{\"docs\":{\"files\":{\"readme.txt\":" &
    "{\"size\":5,\"offset\":\"0\",\"executable\":true}}}," &
    "\"empty\":{\"files\":{}},\".env\":{\"size\":0,\"offset\":\"5\"}," &
    "\"external.bin\":" &
    "{\"size\":9,\"unpacked\":true}}}"
  let payloadLength = (4 + manifest.len + 1 + 3) and not 3
  let headerSize = 4 + payloadLength
  result.addDword(4)
  result.addDword(headerSize)
  result.addDword(payloadLength)
  result.addDword(manifest.len)
  for value in manifest: result.add byte(value)
  result.add 0
  while result.len < 8 + headerSize: result.add 0
  for value in "hello": result.add byte(value)

suite "Electron ASAR archives":
  test "Pickle manifest indexes directories and bounded stored files":
    let data = fixture()
    let archive = parseElectronAsar(data)
    check archive.entries.len == 5
    check archive.payloadOffset == data.len - 5
    check archive.entries[1].name == "docs/readme.txt"
    check archive.entries[1].size == 5
    check archive.entries[1].executable
    check archive.entries[4].unpacked
    check isElectronAsar(data)
    check hasElectronAsarExtension("application.ASAR")
    let inspection = inspectSource("application.asar", data)
    check inspection.selectedFormat.typeId == ElectronAsarTypeId
    var readme: VextResourceNode
    for node in inspection.resources.allResources:
      if node.path == "/archive/docs/readme.txt": readme = node
    check not readme.isNil
    check readme.rawDataAvailable
    check readme.resourceBytes ==
      @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]

  test "sessions remain lazy and implement whole-archive extraction":
    let data = fixture()
    let payloadStart = data.len - 5
    var payloadRead = false
    let source = newByteSource(data.len,
      proc(offset, length: int): seq[byte] =
        if offset < data.len and offset + length > payloadStart:
          payloadRead = true
        result = data[offset ..< offset + length])
    let session = openInspectionSession("application.asar",
      newSourceCollection(source))
    check session.selectedFormat.typeId == ElectronAsarTypeId
    check vrcExtractTree in session.rootDescriptors[0].capabilities
    check not payloadRead
    let plan = session.extractionPlan()
    check not payloadRead
    check plan.entries.len == 4
    check plan.entries[0].relativePath == "docs"
    check plan.entries[1].relativePath == "docs/readme.txt"
    check plan.entries[2].relativePath == "empty"
    check plan.entries[3].relativePath == ".env"
    check plan.warnings.len == 1
    check "external.bin" in plan.warnings[0]
    let bytes = session.materializePayload(plan.entries[1].descriptor.id)
    check bytes == @[byte('h'), byte('e'), byte('l'), byte('l'), byte('o')]
    check payloadRead
    session.close()

  test "invalid Pickle framing and payload bounds are rejected":
    var badPickle = fixture()
    badPickle[0] = 3
    expect ValueError: discard parseElectronAsar(badPickle)
    var badOffset = fixture()
    let marker = "\"offset\":\"0\""
    var text = newString(badOffset.len)
    for index, value in badOffset: text[index] = char(value)
    let position = text.find(marker)
    check position >= 0
    badOffset[position + marker.len - 2] = byte('9')
    expect ValueError: discard parseElectronAsar(badOffset)
