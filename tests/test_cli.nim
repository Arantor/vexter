import std/[json, os, osproc, strutils, unittest]

const
  VexterCliPath {.strdefine.} = "build/vexter"
  FixturePath = "tests/fixtures/zx-spectrum.screen/colours.scr"
  SnapshotFixturePath = "tests/fixtures/zx-spectrum.snapshot/colours.sna"
  AmosFixturePath = "tests/fixtures/amos.sprite-bank/DRAGON.Abk"
  AmosProgramFixturePath =
    "tests/fixtures/amos.program/Xerxes' Revenge.AMOS"

proc run(arguments: varargs[string]): tuple[output: string, exitCode: int] =
  var command = quoteShell(VexterCliPath)
  for argument in arguments:
    command.add " " & quoteShell(argument)
  execCmdEx(command, options = {poUsePath, poStdErrToStdOut})

suite "vexter CLI":
  test "ignore-warnings is accepted for recursive inspection":
    let inspected = run("inspect", "--ignore-warnings", FixturePath)
    check inspected.exitCode == 0
    check "Format: zx-spectrum.screen" in inspected.output

  test "AMOS programs expose listings and attached bank resources":
    let inspected = run("inspect", "--json", AmosProgramFixturePath)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["selectedFormat"].getStr == "amos.program"
    check document["resources"].len == 32
    check document["resources"][0]["path"].getStr == "/listing"
    check document["resources"][0]["kind"].getStr == "text"
    check document["resources"][0]["metadata"]["amos.header"].getStr ==
      "AMOS Basic V1.00"
    check document["resources"][0]["metadata"]["data.length"].getInt == 6264
    check document["resources"][1]["path"].getStr ==
      "/banks/0/sprite/0"
    check document["resources"][^1]["path"].getStr == "/banks/3"

    let destination = getTempDir() / "vexter-cli-xerxes-sprite.png"
    if fileExists(destination):
      removeFile(destination)
    defer:
      if fileExists(destination):
        removeFile(destination)
    let exported = run("export", "--resource", "/banks/0/sprite/0", "-o",
      destination, AmosProgramFixturePath)
    check exported.exitCode == 0
    check readFile(destination).startsWith("\x89PNG\r\n\x1a\n")

    let listingDestination = getTempDir() / "vexter-cli-xerxes.txt"
    if fileExists(listingDestination):
      removeFile(listingDestination)
    defer:
      if fileExists(listingDestination):
        removeFile(listingDestination)
    let listingExport = run("export", "--resource", "/listing", "-o",
      listingDestination, AmosProgramFixturePath)
    check listingExport.exitCode == 0
    let listing = readFile(listingDestination)
    check listing.startsWith("'            Xerxes' Revenge")
    check "SHIP$=SHIP$+\" Begin:" in listing
    check "Bob Clear" in listing

  test "generic AMOS banks inspect as opaque resources":
    let source = getTempDir() / "vexter-cli-music.Abk"
    let destination = getTempDir() / "vexter-cli-music.bin"
    writeFile(source, "AmBk\x00\x07\x12\x34\xd0\x00\x00\x0b" &
      "Music   \x01\x02\x03")
    if fileExists(destination): removeFile(destination)
    defer:
      if fileExists(source):
        removeFile(source)
      if fileExists(destination):
        removeFile(destination)

    let inspected = run("inspect", "--json", source)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["selectedFormat"].getStr == "amos.bank"
    check document["resources"].len == 1
    check document["resources"][0]["path"].getStr == "/bank"
    check document["resources"][0]["type"].getStr == "amos.bank-data"
    check document["resources"][0]["kind"].getStr == "opaque"
    check document["resources"][0]["metadata"]["bank.number"].getInt == 7
    check document["resources"][0]["metadata"]["bank.type"].getStr == "Music"
    check document["resources"][0]["metadata"]["data.length"].getInt == 3

    let exported = run("export", source)
    check exported.exitCode == 0
    check exported.output.strip == destination
    check readFile(destination) == "\x01\x02\x03"

  test "export-all writes a resource hierarchy and preflights collisions":
    let
      source = getTempDir() / "vexter-cli-export-all.Abk"
      destination = getTempDir() / "vexter-cli-export-all-output"
      artifact = destination / "bank.bin"
    writeFile(source, "AmBk\x00\x07\x12\x34\xd0\x00\x00\x0b" &
      "Music   \x01\x02\x03")
    if fileExists(artifact): removeFile(artifact)
    if dirExists(destination): removeDir(destination)
    defer:
      if fileExists(source): removeFile(source)
      if fileExists(artifact): removeFile(artifact)
      if dirExists(destination): removeDir(destination)

    let missingOutput = run("export-all", source)
    check missingOutput.exitCode == 1
    check "export-all requires -o DIRECTORY" in missingOutput.output

    let exported = run("export-all", "-o", destination, source)
    check exported.exitCode == 0
    check readFile(artifact) == "\x01\x02\x03"

    writeFile(artifact, "keep")
    let refused = run("export-all", "-o", destination, source)
    check refused.exitCode == 1
    check "output already exists" in refused.output
    check readFile(artifact) == "keep"

    let forced = run("export-all", "--force", "-o", destination, source)
    check forced.exitCode == 0
    check readFile(artifact) == "\x01\x02\x03"

  test "AMOS banks expose selectable sprites and hotspot metadata":
    let inspected = run("inspect", "--json", AmosFixturePath)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["selectedFormat"].getStr == "amos.sprite-bank"
    check document["candidates"][0]["confidence"].getStr == "certain"
    check document["resources"].len == 10
    check document["resources"][0]["path"].getStr == "/sprite/0"
    check document["resources"][0]["type"].getStr == "amos.sprite"
    check document["resources"][0]["metadata"]["hotspot.x"].getInt == 0
    check document["resources"][0]["metadata"]["hotspot.y"].getInt == 0

    let destination = getTempDir() / "vexter-cli-dragon.png"
    if fileExists(destination):
      removeFile(destination)
    defer:
      if fileExists(destination):
        removeFile(destination)
    let ambiguous = run("export", "-o", destination, AmosFixturePath)
    check ambiguous.exitCode == 1
    check "more than one exportable resource is available" in ambiguous.output
    let exported = run("export", "--resource", "/sprite/0", "-o",
      destination, AmosFixturePath)
    check exported.exitCode == 0
    check readFile(destination).startsWith("\x89PNG\r\n\x1a\n")

  test "inspect reports probable format and screen resource":
    let inspected = run("inspect", FixturePath)
    check inspected.exitCode == 0
    check "Format: zx-spectrum.screen (probable)" in inspected.output
    check "/screen  zx-spectrum.screen -> VextIndexedAnimation 256x192, " &
      "2 frame(s)" in
      inspected.output

  test "JSON inspection is structured":
    let inspected = run("inspect", "--json", FixturePath)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["selectedFormat"].getStr == "zx-spectrum.screen"
    check document["candidates"][0]["confidence"].getStr == "probable"
    check document["resources"][0]["path"].getStr == "/screen"
    check document["resources"][0]["type"].getStr == "zx-spectrum.screen"
    check document["resources"][0]["frames"].getInt == 2

  test "export defaults a FLASH screen to GIF":
    let destination = getTempDir() / "vexter-cli-colours.gif"
    if fileExists(destination):
      removeFile(destination)
    defer:
      if fileExists(destination):
        removeFile(destination)

    let exported = run("export", "-o", destination, FixturePath)
    check exported.exitCode == 0
    check fileExists(destination)
    check readFile(destination).startsWith("GIF89a")

    let refused = run("export", "-o", destination, FixturePath)
    check refused.exitCode == 1
    check "output already exists" in refused.output

    let forced = run("export", "--force", "-o", destination, FixturePath)
    check forced.exitCode == 0

  test "FLASH animation can be explicitly exported as a real PNG":
    let destination = getTempDir() / "vexter-cli-colours.png"
    if fileExists(destination):
      removeFile(destination)
    defer:
      if fileExists(destination):
        removeFile(destination)

    let exported = run("export", "--resource", "/screen", "--format",
      "png", "-o", destination, FixturePath)
    check exported.exitCode == 0
    let contents = readFile(destination)
    check contents.len > 8
    check contents[0 .. 7] == "\x89PNG\r\n\x1a\n"

    let missing = run("export", "--resource", "/missing", "-o",
      destination, FixturePath)
    check missing.exitCode == 1
    check "resource was not found: /missing" in missing.output

  test "FLASH animation can be explicitly exported as APNG":
    let destination = getTempDir() / "vexter-cli-colours-apng.png"
    if fileExists(destination): removeFile(destination)
    defer:
      if fileExists(destination): removeFile(destination)
    let exported = run("export", "--resource", "/screen", "--format",
      "apng", "-o", destination, FixturePath)
    check exported.exitCode == 0
    let contents = readFile(destination)
    check contents.startsWith("\x89PNG\r\n\x1a\n")
    check "acTL" in contents
    check "fcTL" in contents

  test "snapshot inspection and screen export use the same pathway":
    let inspected = run("inspect", SnapshotFixturePath)
    check inspected.exitCode == 0
    check "Format: zx-spectrum.snapshot (probable)" in inspected.output
    check "/screen  zx-spectrum.screen -> VextIndexedAnimation 256x192, " &
      "2 frame(s)" in
      inspected.output

    let
      rawDestination = getTempDir() / "vexter-cli-raw-screen.gif"
      snapshotDestination = getTempDir() / "vexter-cli-snapshot-screen.gif"
    for destination in [rawDestination, snapshotDestination]:
      if fileExists(destination):
        removeFile(destination)
    defer:
      for destination in [rawDestination, snapshotDestination]:
        if fileExists(destination):
          removeFile(destination)

    let rawExport = run("export", "--resource", "/screen", "-o",
      rawDestination, FixturePath)
    let snapshotExport = run("export", "--resource", "/screen", "-o",
      snapshotDestination, SnapshotFixturePath)
    check rawExport.exitCode == 0
    check snapshotExport.exitCode == 0
    check readFile(snapshotDestination) == readFile(rawDestination)

  test "non-FLASH snapshot inspects and defaults to PNG":
    let
      listingSnapshot =
        "tests/fixtures/zx-spectrum.snapshot/colours-listing.sna"
      listingScreen =
        "tests/fixtures/zx-spectrum.screen/colours-listing.scr"
      snapshotDestination = getTempDir() / "vexter-listing-snapshot.png"
      screenDestination = getTempDir() / "vexter-listing-screen.png"
    for destination in [snapshotDestination, screenDestination]:
      if fileExists(destination):
        removeFile(destination)
    defer:
      for destination in [snapshotDestination, screenDestination]:
        if fileExists(destination):
          removeFile(destination)

    let inspected = run("inspect", "--json", listingSnapshot)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["resources"][0]["archetype"].getStr ==
      "VextIndexedImage"
    check not document["resources"][0].hasKey("frames")

    let snapshotExport = run("export", "--resource", "/screen", "-o",
      snapshotDestination, listingSnapshot)
    let screenExport = run("export", "--resource", "/screen", "-o",
      screenDestination, listingScreen)
    check snapshotExport.exitCode == 0
    check screenExport.exitCode == 0
    check readFile(snapshotDestination).startsWith("\x89PNG\r\n\x1a\n")
    check readFile(snapshotDestination) == readFile(screenDestination)
