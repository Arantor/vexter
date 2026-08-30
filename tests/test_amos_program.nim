import std/[strutils, unittest]
import vexterlib

const FixturePath = "tests/fixtures/amos.program/Xerxes' Revenge.AMOS"

proc readBytes(path: string): seq[byte] =
  let contents = readFile(path)
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc addDword(data: var seq[byte], value: int) =
  data.add byte((value shr 24) and 0xff)
  data.add byte((value shr 16) and 0xff)
  data.add byte((value shr 8) and 0xff)
  data.add byte(value and 0xff)

proc emptyProgram(header: string): seq[byte] =
  check header.len == AmosProgramHeaderSize
  for value in header:
    result.add byte(value)
  result.addDword(0)
  for value in AmosBankSetMagic:
    result.add byte(value)
  result.add @[0'u8, 0]

suite "AMOS programs":
  test "encrypted procedure bodies are decrypted before token decoding":
    var listing = @[
      8'u8, 1, 0x03, 0x76, 0, 0, 0, 8, 0, 0, 0xa0, 0,
      0, 0, 0, 0,
      3, 1, 0x03, 0x90, 0, 0,
      3, 1, 0x03, 0x90, 0, 0]
    let plaintext = listing
    decryptAmosProcedures(listing) # XOR is symmetric: produce ciphertext.
    listing[10] = listing[10] or 0x20
    check listing != plaintext
    check decodeAmosListing(listing) ==
      "Procedure \nEnd Proc\nEnd Proc\n"

  test "Xerxes' Revenge exposes its listing and attached banks":
    let
      data = readBytes(FixturePath)
      program = parseAmosProgram(data)
      candidates = detectFormats(FixturePath, data)
      inspection = inspectSource(FixturePath, data)
      leaves = inspection.resources.leafResources
      rasters = inspection.resources.rasterResources

    check program.header == "AMOS Basic V1.00"
    check program.listingLength == 6264
    check program.bankSet.banks.len == 4
    check program.bankSet.banks[0].kind == absekSprite
    check program.bankSet.banks[0].spriteIconBank.images.len == 28
    check program.bankSet.banks[1].genericBank.bankType == "Datas"
    check program.bankSet.banks[2].genericBank.bankType == "Datas"
    check program.bankSet.banks[3].genericBank.bankType == "Pac.Pic."
    check candidates.len == 1
    check candidates[0].typeId == AmosProgramTypeId
    check candidates[0].confidence == vdcCertain
    check candidates[0].evidence.len == 2
    check leaves.len == 32
    check leaves[0].path == "/listing"
    check leaves[0].kind == vrnkText
    check leaves[0].metadata[0].value.stringValue == "AMOS Basic V1.00"
    check leaves[0].metadata[1].value.integerValue == 6264
    check rasters.len == 29
    check rasters[0].path == "/banks/0/sprite/0"
    check rasters[^1].path == "/banks/3"
    check rasters[^1].typeId == AmosPackedPictureResourceTypeId
    check leaves[^1].path == "/banks/3"
    check leaves[0].text.startsWith("'            Xerxes' Revenge")
    check "SHIP$=SHIP$+\" Begin:" in leaves[0].text
    check "   Bob Clear" in leaves[0].text
    check leaves[0].text.endsWith("End \n")

    let listingExport = exportResource(inspection.resources,
      VextExportRequest(
        resourcePath: "/listing",
        suggestedName: "xerxes"))
    check listingExport.outputFormat == "txt"
    check listingExport.artifacts.artifacts[0].suggestedFilename == "xerxes.txt"
    check listingExport.artifacts.artifacts[0].mediaType ==
      "text/plain; charset=utf-8"

    let exported = exportResource(inspection.resources,
      VextExportRequest(
        resourcePath: "/banks/0/sprite/0",
        suggestedName: "xerxes-sprite"))
    check exported.outputFormat == "png"

  test "professional headers and empty mandatory appendices are valid":
    for header in ["AMOS Pro101     ", "AMOS Pro        "]:
      let data = emptyProgram(header)
      let program = parseAmosProgram(data)
      check program.header == header.strip(leading = false)
      check program.listingLength == 0
      check program.bankSet.banks.len == 0
      let listing = inspectSource("empty.amos", data).resources.leafResources[0]
      check listing.kind == vrnkText
      check listing.text.len == 0

  test "headers, listing boundaries, and appendices are validated":
    var badHeader = emptyProgram("AMOS Pro101     ")
    badHeader[0] = byte('X')
    check not isAmosProgram(badHeader)

    var badLength = emptyProgram("AMOS Pro101     ")
    badLength[19] = 1
    check not isAmosProgram(badLength)

    var missingAppendix = emptyProgram("AMOS Pro101     ")
    missingAppendix[22] = byte('X')
    check not isAmosProgram(missingAppendix)

  test "complex and unknown tokens retain diagnostic text":
    check decodeAmosLine(@[0x01'u8, 0x1c, 0, 0]) == "Border$"
    check decodeAmosLine(@[0x0c'u8, 0xd8, 0, 0]) == "Default Palette "
    check decodeAmosLine(@[0x22'u8, 0x0a, 0, 0]) == "Bset"
    check decodeAmosLine(@[0x22'u8, 0x96, 0, 0]) == "Areg"
    check decodeAmosLine(@[0x22'u8, 0xa2, 0, 0]) == "Dreg"
    check decodeAmosLine(@[
      0x00'u8, 0x1e, 0, 0, 0, 5,
      0x00, 0x36, 0, 0, 0, 0xff,
      0x00, 0x3e, 0, 0, 0, 42,
      0, 0]) == "%101$FF42"
    check decodeAmosLine(@[0x12'u8, 0x34, 0, 0]) == "[12340000]"
    check decodeAmosLine(@[
      0x00'u8, 0x4e, 9, 0, 0x12, 0x34, 0, 0]) ==
      "[ext 9 1234]"
    check decodeAmosLine(@[
      0x03'u8, 0x76, 0, 0, 0, 10, 0, 0, 0x20, 0, 0, 0]) ==
      "Procedure [encrypted procedure]"
    check decodeAmosLine(@[0x03'u8, 0x86, 0, 0]) == "Proc "

    expect ValueError:
      discard decodeAmosListing(@[2'u8, 0, 1, 0])
