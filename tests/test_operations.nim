import std/[json, strutils, unittest]
import vexterlib

proc asString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data: result[index] = char(value)

suite "vexterlib operations":
  test "format handlers are unique and cover detected formats":
    for index, handler in FormatHandlers:
      check handler.typeId.len > 0
      check not formatHandler(handler.typeId).isNil
      check formatHandler(handler.typeId)[].kind == handler.kind
      for otherIndex in index + 1 .. FormatHandlers.high:
        check handler.typeId != FormatHandlers[otherIndex].typeId

    let candidates = detectFormats("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))
    check candidates.len == 1
    check not formatHandler(candidates[0].typeId).isNil

  test "detected and forced handlers retain checked parsed containers":
    let data = newSeq[byte](ZxSpectrumScreenSize)
    let detected = detectParsedFormats("display.scr", data)
    check detected.len == 1
    check detected[0].candidate.typeId == ZxSpectrumScreenDumpTypeId
    check parsedValue[seq[byte]](detected[0].parsed,
      vhkZxSpectrumScreen) == data
    expect Defect:
      discard parsedValue[seq[byte]](detected[0].parsed,
        vhkZxSpectrumSnapshot)

    let handler = formatHandler(ZxSpectrumScreenDumpTypeId)
    let forced = handler[].parse(data)
    check parsedValue[seq[byte]](forced, vhkZxSpectrumScreen) == data

  test "inspection returns a decoded resource tree":
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))

    check inspection.selectedFormat.typeId == ZxSpectrumScreenDumpTypeId
    check inspection.candidates.len == 1
    check inspection.resources.roots.len == 1
    let resources = inspection.resources.rasterResources
    check resources.len == 1
    check resources[0].path == ZxSpectrumScreenResourcePath
    check resources[0].typeId == ZxSpectrumScreenTypeId
    check resources[0].raster.kind == vrkIndexedImage

  test "forced formats are validated by the library":
    expect ValueError:
      discard inspectSource("short.scr", newSeq[byte](1),
        ZxSpectrumScreenDumpTypeId)
    expect ValueError:
      discard inspectSource("unknown.bin", newSeq[byte](1), "unknown")

  test "export selects resources and chooses a natural output format":
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))
    let exported = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "display"))

    check exported.resourcePath == ZxSpectrumScreenResourcePath
    check exported.outputFormat == "png"
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].suggestedFilename == "display.png"
    expect ValueError:
      discard exportResource(inspection.resources,
        VextExportRequest(resourcePath: "/missing"))

  test "export formats are discoverable from resource archetypes":
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize))
    let resource = inspection.resources.rasterResources[0]
    let formats = resource.exportFormatsFor
    check formats.len == 4
    check formats[0].id == "png"
    check formats[0].isDefault
    check formats[1].id == "gif"
    check formats[2].id == "metadata-json"
    check formats[3].id == "html-report"
    check resource.defaultExportFormat == "png"

    let opaque = VextResourceNode(path: "/raw", kind: vrnkOpaque,
      rawDataAvailable: true)
    check opaque.exportFormatsFor.len == 3
    check opaque.defaultExportFormat == "bin"
    check VextResourceNode(path: "/group", kind: vrnkGroup).
      exportFormatsFor.len == 2

  test "inspection reports structured progress and supports cancellation":
    var events: seq[VextProgressEvent]
    let inspection = inspectSource("display.scr",
      newSeq[byte](ZxSpectrumScreenSize), progress =
        proc(event: VextProgressEvent): bool =
          events.add event
          true)
    check inspection.resources.roots.len == 1
    check events.len == 5
    check events[0].phase == vppDetecting
    check events[2].phase == vppDecoding
    check events[^1].phase == vppComplete
    check events[^2].completed == 1
    check events[^2].total == 1

    expect VextOperationCancelledError:
      discard inspectSource("display.scr", newSeq[byte](ZxSpectrumScreenSize),
        progress = proc(event: VextProgressEvent): bool =
          event.phase != vppInspecting)

  test "GIF-capable indexed rasters also export as APNG without changing defaults":
    var screen = newSeq[byte](ZxSpectrumScreenSize)
    screen[6144] = 0x80 # FLASH makes the natural raster an indexed animation.
    let inspection = inspectSource("flash.scr", screen)
    let defaultExport = exportResource(inspection.resources,
      VextExportRequest(suggestedName: "flash"))
    let apngExport = exportResource(inspection.resources,
      VextExportRequest(outputFormat: "apng", suggestedName: "flash"))
    check defaultExport.outputFormat == "gif"
    check defaultExport.artifacts.artifacts[0].mediaType == "image/gif"
    check apngExport.outputFormat == "apng"
    check apngExport.artifacts.artifacts[0].mediaType == "image/apng"
    let parsed = parsePng(apngExport.artifacts.artifacts[0].data)
    var animationControl = false
    for chunk in parsed.chunks:
      if chunk.kind == "acTL": animationControl = true
    check animationControl
    let decoded = decodePng(parsed).trueColourImage
    let natural = inspection.resources.rasterResources[0].raster.animation.
      frames[0].image
    check decoded.width == natural.width
    check decoded.height == natural.height
    check decoded.colourAt(0, 0) == natural.colourAt(0, 0)

  test "indexed APNG permits frame palettes to differ and preserves alpha":
    let animation = VextIndexedAnimation(width: 1, height: 1, frames: @[
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 1, height: 1,
        palette: @[VextRgb(r: 255, g: 0, b: 0)], pixels: @[0'u8],
        alpha: @[128'u8]), durationMs: 10),
      VextIndexedAnimationFrame(image: VextIndexedImage(width: 1, height: 1,
        palette: @[VextRgb(r: 0, g: 0, b: 255)], pixels: @[0'u8]),
        durationMs: 20)])
    let artifact = exportApng(animation).artifacts[0]
    let first = decodePng(parsePng(artifact.data)).trueColourImage
    check first.rgbaAt(0, 0) == VextRgba(r: 255, g: 0, b: 0, a: 128)
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/animation",
      typeId: "test.animation", kind: vrnkRaster,
      raster: VextRaster(kind: vrkIndexedAnimation, animation: animation))])
    let natural = exportResource(tree, VextExportRequest(suggestedName: "test"))
    check natural.outputFormat == "apng"
    check natural.artifacts.artifacts[0].mediaType == "image/apng"

  test "colour cycling is optional and bounded before animated export":
    let image = VextIndexedImage(width: 1, height: 1,
      palette: @[
        VextRgb(r: 1), VextRgb(r: 2), VextRgb(r: 3),
        VextRgb(r: 4), VextRgb(r: 5)],
      pixels: @[0'u8],
      colourCycles: @[
        VextColourCycleRange(low: 0, high: 1, direction: 1,
          stepDurationMs: 100),
        VextColourCycleRange(low: 2, high: 4, direction: -1,
          stepDurationMs: 150)])
    let raster = VextRaster(kind: vrkIndexedImage, image: image)
    let expanded = expandColourCycles(raster,
      allowLargeAnimation = true)
    check expanded.frames.len == 24
    check colourCyclePeriodMs(image.colourCycles) == 1800
    check colourCycleNextBoundaryMs(image.colourCycles, 0) == 100
    check colourCycleNextBoundaryMs(image.colourCycles, 100) == 150
    check colourCycledImageAt(image, image.colourCycles, 100).palette[0].r == 2
    check expanded.frames[0].image.palette[0].r == 1
    check expanded.frames[1].image.palette[0].r == 2
    expect ValueError:
      discard expandColourCycles(raster, frameLimit = 10)

    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/cycled",
      typeId: "test.cycled", kind: vrnkRaster, raster: raster)])
    let formats = tree.roots[0].exportFormatsFor
    check formats.len == 6
    check formats[0].id == "png"
    check formats[2].id == "gif-cycled"
    check exportResource(tree, VextExportRequest(outputFormat: "png",
      suggestedName: "still")).artifacts.artifacts[0].mediaType == "image/png"
    check exportResource(tree, VextExportRequest(outputFormat: "apng-cycled",
      suggestedName: "cycled", allowLargeAnimation: true)).artifacts.
      artifacts[0].mediaType == "image/apng"

  test "opaque resources with retained bytes export exactly as BIN":
    let tree = VextResourceTree(roots: @[
      VextResourceNode(path: "/raw", typeId: "test.raw", kind: vrnkOpaque,
        data: @[0'u8, 1, 0xff], rawDataAvailable: true),
      VextResourceNode(path: "/empty", typeId: "test.empty", kind: vrnkOpaque,
        rawDataAvailable: true),
      VextResourceNode(path: "/identified", typeId: "test.identified",
        kind: vrnkOpaque)])
    let exported = exportResource(tree, VextExportRequest(
      resourcePath: "/raw", suggestedName: "payload"))
    check exported.outputFormat == "bin"
    check exported.artifacts.artifacts.len == 1
    check exported.artifacts.artifacts[0].suggestedFilename == "payload.bin"
    check exported.artifacts.artifacts[0].mediaType == "application/octet-stream"
    check exported.artifacts.artifacts[0].data == @[0'u8, 1, 0xff]
    check exportResource(tree, VextExportRequest(resourcePath: "/empty",
      suggestedName: "empty")).artifacts.artifacts[0].data.len == 0
    expect ValueError:
      discard exportResource(tree, VextExportRequest(
        resourcePath: "/identified", suggestedName: "identified"))

  test "resource traversal preserves tree order and exact lookup":
    let raster = decodeZxSpectrumScreen(newSeq[byte](ZxSpectrumScreenSize))
    let tree = VextResourceTree(roots: @[VextResourceNode(
      path: "/screens",
      kind: vrnkGroup,
      children: @[
        VextResourceNode(path: "/screens/1", typeId: ZxSpectrumScreenTypeId,
          kind: vrnkRaster, raster: raster),
        VextResourceNode(path: "/screens/2", typeId: ZxSpectrumScreenTypeId,
          kind: vrnkRaster, raster: raster)
      ])])

    check tree.rasterResources.len == 2
    check tree.rasterResources[0].path == "/screens/1"
    check tree.rasterResources[1].path == "/screens/2"
    check tree.findRasterResource("/screens/2").path == "/screens/2"
    check tree.findRasterResource("/screens").isNil

  test "metadata JSON retains typed metadata and rich font features":
    let font = VextBitmapFont(name: "rich", lineHeight: 3, baseline: 2,
      ascent: 2, descent: 1, leading: 1, fallbackCodePoint: 65,
      glyphs: @[VextBitmapGlyph(name: "A", sourceIndex: 7,
        bitmap: VextGlyphBitmap(kind: vgbkTrueColour,
          trueColourImage: VextTrueColourImage(width: 1, height: 1,
            pixels: @[VextRgb(r: 255, g: 255, b: 255)])),
        bearingX: -1, bearingY: 2,
        advanceX: 3, advanceY: 4)],
      mappings: @[VextGlyphMapping(codePoint: 65, glyphIndex: 0)],
      kerning: @[VextFontKerning(leftCodePoint: 65, rightCodePoint: 65,
        amountX: -1, amountY: 2)],
      substitutions: @[VextFontSubstitution(sourceCodePoint: 97,
        replacementCodePoint: 65)],
      ligatures: @[VextFontLigature(components: @[65, 65], glyphIndex: 0)])
    let child = VextResourceNode(path: "/fonts/rich", typeId: "test.font",
      kind: vrnkFont, font: font,
      metadata: @[stringMetadata("source", "synthetic")])
    let tree = VextResourceTree(roots: @[VextResourceNode(path: "/fonts",
      typeId: "test.group", kind: vrnkGroup,
      metadata: @[integerMetadata("count", 1)], children: @[child])])
    check tree.allResources.len == 2
    let exported = exportResource(tree, VextExportRequest(
      resourcePath: child.path, outputFormat: "metadata-json",
      suggestedName: "rich"))
    check exported.artifacts.artifacts[0].suggestedFilename == "rich.json"
    check exported.artifacts.artifacts[0].mediaType == "application/json"
    let document = parseJson(exported.artifacts.artifacts[0].data.asString)
    check document["schema"].getStr == "vexter.resource-metadata.v1"
    check document["metadata"][0]["kind"].getStr == "string"
    check document["resource"]["glyphs"][0]["advanceY"].getInt == 4
    check document["resource"]["glyphs"][0]["bitmapKind"].getStr ==
      "true-colour"
    check document["resource"]["glyphs"][0]["width"].getInt == 1
    check document["resource"]["mappings"][0]["codePoint"].getInt == 65
    check document["resource"]["kerning"][0]["amountY"].getInt == 2
    check document["resource"]["substitutions"].len == 1
    check document["resource"]["ligatures"][0]["components"].len == 2
    check exportResource(tree, VextExportRequest(resourcePath: "/fonts",
      outputFormat: "metadata-json", suggestedName: "fonts")).artifacts.
      artifacts[0].suggestedFilename == "fonts.json"
    check exportAllResources(tree, VextExportAllRequest(
      outputFormat: "metadata-json")).exports.len == 2
    let report = exportResource(tree, VextExportRequest(
      resourcePath: child.path, outputFormat: "html-report",
      suggestedName: "rich-report")).artifacts.artifacts[0]
    check report.suggestedFilename == "rich-report.html"
    check report.mediaType == "text/html; charset=utf-8"
    let html = report.data.asString
    check html.startsWith("<!doctype html>")
    check "data:image/png;base64," in html
    check "vexter.resource-metadata.v1" in html
    check "This report has no external dependencies" in html

  test "HTML reports embed audio and safely present text and groups":
    let tree = VextResourceTree(roots: @[
      VextResourceNode(path: "/group", typeId: "test.group",
        kind: vrnkGroup, children: @[
          VextResourceNode(path: "/group/text", typeId: "test.text",
            kind: vrnkText, text: "<script>alert('&')</script>")]),
      VextResourceNode(path: "/audio", typeId: "test.audio",
        kind: vrnkAudio, audioKind: varkSound,
        sound: VextSound(sampleRate: 8000,
          buffer: VextAudioBuffer(bitsPerSample: 8,
            channels: @[@[0'i32]]))),
      VextResourceNode(path: "/identified", typeId: "test.opaque",
        kind: vrnkOpaque)])
    let textReport = exportResource(tree, VextExportRequest(
      resourcePath: "/group/text", outputFormat: "html-report",
      suggestedName: "text")).artifacts.artifacts[0].data.asString
    check "&lt;script&gt;alert(&#39;&amp;&#39;)&lt;/script&gt;" in textReport
    check "<script>alert" notin textReport
    let audioReport = exportResource(tree, VextExportRequest(
      resourcePath: "/audio", outputFormat: "html-report",
      suggestedName: "audio")).artifacts.artifacts[0].data.asString
    check "data:audio/wav;base64," in audioReport
    let groupReport = exportResource(tree, VextExportRequest(
      resourcePath: "/group", outputFormat: "html-report",
      suggestedName: "group")).artifacts.artifacts[0].data.asString
    check "/group/text" in groupReport
    let opaqueReport = exportResource(tree, VextExportRequest(
      resourcePath: "/identified", outputFormat: "html-report",
      suggestedName: "identified")).artifacts.artifacts[0].data.asString
    check "No retained byte payload is available" in opaqueReport

  test "bulk export matches path segments, deduplicates, and names safely":
    let tree = VextResourceTree(roots: @[
      VextResourceNode(path: "/group", kind: vrnkGroup, children: @[
        VextResourceNode(path: "/group/x:y", typeId: "test.raw",
          kind: vrnkOpaque, data: @[1'u8], rawDataAvailable: true),
        VextResourceNode(path: "/group/x?y", typeId: "test.raw",
          kind: vrnkOpaque, data: @[2'u8], rawDataAvailable: true),
        VextResourceNode(path: "/group/deeper", kind: vrnkGroup, children: @[
          VextResourceNode(path: "/group/deeper/item", typeId: "test.raw",
            kind: vrnkOpaque, data: @[3'u8], rawDataAvailable: true)])]),
      VextResourceNode(path: "/other", typeId: "test.raw",
        kind: vrnkOpaque, data: @[4'u8], rawDataAvailable: true),
      VextResourceNode(path: "/identified", typeId: "test.identified",
        kind: vrnkOpaque)])

    let matched = exportAllResources(tree, VextExportAllRequest(
      resourcePatterns: @["/group/*", "/group/x:y"]))
    check matched.exports.len == 2
    check matched.exports[0].resourcePath == "/group/x:y"
    check matched.exports[1].resourcePath == "/group/x?y"
    check matched.exports[0].artifacts.artifacts[0].suggestedFilename ==
      "group/x_y.bin"
    check matched.exports[1].artifacts.artifacts[0].suggestedFilename ==
      "group/x_y-2.bin"

    let all = exportAllResources(tree, VextExportAllRequest())
    check all.exports.len == 4
    check all.exports[2].resourcePath == "/group/deeper/item"
    check all.exports[2].artifacts.artifacts[0].suggestedFilename ==
      "group/deeper/item.bin"
    check all.exports[3].resourcePath == "/other"

    expect ValueError:
      discard exportAllResources(tree, VextExportAllRequest(
        resourcePatterns: @["/group/**"]))
    expect ValueError:
      discard exportAllResources(tree, VextExportAllRequest(
        resourcePatterns: @["/group/x*"]))
    expect ValueError:
      discard exportAllResources(tree, VextExportAllRequest(
        resourcePatterns: @["/missing/*"]))
