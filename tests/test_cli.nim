import std/[json, os, osproc, strutils, unittest]

const
  VexterCliPath {.strdefine.} = "build/vexter"
  FixturePath = "tests/fixtures/zx-spectrum.screen/colours.scr"

proc run(arguments: varargs[string]): tuple[output: string, exitCode: int] =
  var command = quoteShell(VexterCliPath)
  for argument in arguments:
    command.add " " & quoteShell(argument)
  execCmdEx(command, options = {poUsePath, poStdErrToStdOut})

suite "vexter CLI":
  test "inspect reports probable format and screen resource":
    let inspected = run("inspect", FixturePath)
    check inspected.exitCode == 0
    check "Format: zx-spectrum.screen (probable)" in inspected.output
    check "/screen  VextIndexedAnimation 256x192, 2 frame(s)" in
      inspected.output

  test "JSON inspection is structured":
    let inspected = run("inspect", "--json", FixturePath)
    check inspected.exitCode == 0
    let document = parseJson(inspected.output)
    check document["selectedFormat"].getStr == "zx-spectrum.screen"
    check document["candidates"][0]["confidence"].getStr == "probable"
    check document["resources"][0]["path"].getStr == "/screen"
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

  test "export accepts an exact resource and explicit PNG format":
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
