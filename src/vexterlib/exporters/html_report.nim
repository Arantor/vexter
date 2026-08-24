## Self-contained, dependency-free HTML report for one resource.

import std/base64
import ../archetypes/[font, raster]
import ../artifacts
import ../resource_tree
import ../resources/font_preview
import ../transformations/palette_swatch
import ./[metadata_json, png, wav]

proc textBytes(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for index, character in value: result[index] = byte(character)

proc bytesText(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

proc escaped(value: string): string =
  for character in value:
    case character
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add character

proc dataUrl(artifact: VextArtifact): string =
  "data:" & artifact.mediaType & ";base64," & encode(artifact.data)

proc imageSection(label: string, artifact: VextArtifact): string =
  "<section><h2>" & label.escaped & "</h2><div class=\"checker\">" &
    "<img src=\"" & artifact.dataUrl & "\" alt=\"" & label.escaped &
    "\"></div></section>"

proc rasterArtifact(resource: VextResourceNode): VextArtifact =
  let exported = case resource.raster.kind
    of vrkIndexedImage: exportPng(resource.raster.image, "preview.png")
    of vrkIndexedAnimation:
      exportApng(resource.raster.animation, "preview.png")
    of vrkTrueColourImage:
      exportPng(resource.raster.trueColourImage, "preview.png")
    of vrkTrueColourAnimation:
      exportApng(resource.raster.trueColourAnimation, "preview.png")
  exported.artifacts[0]

proc exportHtmlReport*(resource: VextResourceNode,
    suggestedFilename = "report.html"): VextArtifactSet =
  if resource.isNil:
    raise newException(ValueError, "cannot report a missing resource")
  let metadataArtifact = exportMetadataJson(resource, "metadata.json").artifacts[0]
  let title = (if resource.path.len > 0: resource.path else: resource.typeId)
  var body = "<header><h1>" & title.escaped & "</h1><p><code>" &
    resource.typeId.escaped & "</code></p></header>"
  case resource.kind
  of vrnkRaster:
    body.add imageSection("Preview", resource.rasterArtifact)
  of vrnkFont:
    let width = 800
    let sample = exportPng(renderBitmapFontText(resource.font,
      resource.font.defaultPreviewText, width), "sample.png").artifacts[0]
    let grid = exportPng(renderBitmapFontGlyphGrid(resource.font, width),
      "glyphs.png").artifacts[0]
    body.add imageSection("Sample text", sample)
    body.add imageSection("Glyph grid", grid)
  of vrnkPalette:
    let swatch = exportPng(renderPaletteSwatch(resource.palette),
      "palette.png").artifacts[0]
    body.add imageSection("Palette swatch", swatch)
  of vrnkAudio:
    let audio = exportWav(resource.audioSound, "audio.wav").artifacts[0]
    body.add "<section><h2>Audio</h2><audio controls src=\"" &
      audio.dataUrl & "\"></audio></section>"
  of vrnkText:
    body.add "<section><h2>Text</h2><pre>" & resource.text.escaped &
      "</pre></section>"
  of vrnkGroup:
    body.add "<section><h2>Children</h2><ul>"
    for child in resource.children:
      body.add "<li><code>" & child.path.escaped & "</code> — " &
        child.typeId.escaped & "</li>"
    if resource.children.len == 0: body.add "<li>None</li>"
    body.add "</ul></section>"
  of vrnkOpaque:
    if resource.failureMessage.len > 0:
      body.add "<section><h2>Decode failure</h2><p>Suspected format: <code>" &
        resource.failureFormat.escaped & "</code></p><pre>" &
        resource.failureMessage.escaped & "</pre><p>"
    else:
      body.add "<section><h2>Opaque resource</h2><p>"
    if resource.rawDataAvailable:
      body.add $resource.retainedByteLength & " retained byte(s)."
    else:
      body.add "No retained byte payload is available."
    body.add "</p></section>"
  body.add "<section><details open><summary>Metadata JSON</summary><pre>" &
    metadataArtifact.data.bytesText.escaped & "</pre></details></section>"
  let document = "<!doctype html><html lang=\"en\"><head>" &
    "<meta charset=\"utf-8\"><meta name=\"viewport\" " &
    "content=\"width=device-width,initial-scale=1\">" &
    "<title>Vexter — " & title.escaped & "</title><style>" &
    ":root{color-scheme:dark;font-family:system-ui,sans-serif;background:#181a1f;color:#eee}" &
    "body{max-width:1100px;margin:auto;padding:1.5rem}header,section{margin-bottom:1.5rem}" &
    "h1{overflow-wrap:anywhere}code,pre{font-family:ui-monospace,monospace}" &
    "pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#101216;padding:1rem;border-radius:.4rem}" &
    ".checker{padding:1rem;overflow:auto;border-radius:.4rem;" &
    "background-color:rgb(56,56,56);background-image:linear-gradient(45deg,rgb(88,88,88) 25%,transparent 25%)," &
    "linear-gradient(-45deg,rgb(88,88,88) 25%,transparent 25%)," &
    "linear-gradient(45deg,transparent 75%,rgb(88,88,88) 75%)," &
    "linear-gradient(-45deg,transparent 75%,rgb(88,88,88) 75%);" &
    "background-size:20px 20px;background-position:0 0,0 10px,10px -10px,-10px 0}" &
    "img{display:block;max-width:100%;height:auto;image-rendering:pixelated}" &
    "audio{width:min(100%,40rem)}summary{cursor:pointer;font-size:1.25rem;font-weight:600}" &
    "a{color:#8fc7ff}</style></head><body>" & body &
    "<footer><p>Generated by Vexter. This report has no external dependencies.</p></footer>" &
    "</body></html>\n"
  result.artifacts.add VextArtifact(suggestedFilename: suggestedFilename,
    mediaType: "text/html; charset=utf-8", data: textBytes(document))
