## GIMP Palette export with automatic Aseprite RGBA extension selection.

import std/[strutils, unicode]
import ../archetypes/palette
import ../artifacts

proc usesGplRgbaExtension*(palette: VextPalette): bool =
  for colour in palette.colours:
    if colour.a != 255: return true

proc exportGpl*(palette: VextPalette, name = "",
    suggestedFilename = "palette.gpl"): VextArtifactSet =
  palette.validate
  if validateUtf8(name) != -1:
    raise newException(ValueError, "GIMP palette name must be valid UTF-8")
  let cleanName = name.replace('\r', ' ').replace('\n', ' ').strip
  let rgba = palette.usesGplRgbaExtension
  var contents = "GIMP Palette\n"
  if cleanName.len > 0:
    contents.add "Name: " & cleanName & "\n"
  if rgba:
    contents.add "Channels: RGBA\n"
  for colour in palette.colours:
    contents.add $colour.r & "\t" & $colour.g & "\t" & $colour.b
    if rgba: contents.add "\t" & $colour.a
    contents.add "\n"
  var data = newSeq[byte](contents.len)
  for index, character in contents: data[index] = byte(character)
  result.artifacts.add VextArtifact(suggestedFilename: suggestedFilename,
    mediaType: "application/x-gimp-palette", data: data)
