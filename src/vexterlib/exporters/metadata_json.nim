## Machine-readable metadata export for any resource node.

import std/json
import ../archetypes/[audio, font, palette, raster]
import ../[artifacts, metadata, resource_tree]

proc textBytes(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for index, character in value: result[index] = byte(character)

proc metadataNode(entries: openArray[VextMetadataEntry]): JsonNode =
  result = newJArray()
  for entry in entries:
    result.add case entry.value.kind
      of vmvkInteger:
        %*{"key": entry.key, "kind": "integer",
          "value": entry.value.integerValue}
      of vmvkString:
        %*{"key": entry.key, "kind": "string",
          "value": entry.value.stringValue}

proc cyclesNode(cycles: openArray[VextColourCycleRange]): JsonNode =
  result = newJArray()
  for cycle in cycles:
    result.add %*{"low": cycle.low, "high": cycle.high,
      "direction": cycle.direction, "stepDurationMs": cycle.stepDurationMs}

proc paletteNode(palette: VextPalette): JsonNode =
  result = %*{"archetype": "VextPalette",
    "colourCycles": cyclesNode(palette.colourCycles)}
  var colours = newJArray()
  for index, colour in palette.colours:
    colours.add %*{"r": colour.r, "g": colour.g, "b": colour.b,
      "a": (if palette.alpha.len == 0: 255 else: int(palette.alpha[index]))}
  result["colours"] = colours

proc rasterNode(raster: VextRaster): JsonNode =
  result = %*{"archetype": raster.archetypeName,
    "width": raster.width, "height": raster.height}
  case raster.kind
  of vrkIndexedImage:
    result["paletteSize"] = %raster.image.palette.len
    result["hasAlpha"] = %raster.image.hasAlpha
    result["colourCycles"] = cyclesNode(raster.image.colourCycles)
  of vrkIndexedAnimation:
    result["paletteSize"] = %(if raster.animation.frames.len == 0: 0
      else: raster.animation.frames[0].image.palette.len)
    result["frames"] = %raster.animation.frames.len
    var durations = newJArray()
    for frame in raster.animation.frames: durations.add %frame.durationMs
    result["frameDurationsMs"] = durations
    result["colourCycles"] = cyclesNode(raster.animation.colourCycles)
  of vrkTrueColourImage:
    result["hasAlpha"] = %raster.trueColourImage.hasAlpha
  of vrkTrueColourAnimation:
    result["frames"] = %raster.trueColourAnimation.frames.len
    var durations = newJArray()
    for frame in raster.trueColourAnimation.frames: durations.add %frame.durationMs
    result["frameDurationsMs"] = durations

proc fontNode(font: VextBitmapFont): JsonNode =
  result = %*{"archetype": "VextBitmapFont", "name": font.name,
    "lineHeight": font.lineHeight, "baseline": font.baseline,
    "ascent": font.ascent, "descent": font.descent,
    "leading": font.leading, "fallbackCodePoint": font.fallbackCodePoint}
  var glyphs = newJArray()
  for glyph in font.glyphs:
    glyphs.add %*{"name": glyph.name, "sourceIndex": glyph.sourceIndex,
      "bitmapKind": (case glyph.bitmap.kind
        of vgbkMonochrome: "monochrome"
        of vgbkIndexed: "indexed"
        of vgbkTrueColour: "true-colour"),
      "width": width(glyph.bitmap), "height": height(glyph.bitmap),
      "bearingX": glyph.bearingX, "bearingY": glyph.bearingY,
      "advanceX": glyph.advanceX, "advanceY": glyph.advanceY}
  result["glyphs"] = glyphs
  var mappings = newJArray()
  for mapping in font.mappings:
    mappings.add %*{"codePoint": mapping.codePoint,
      "glyphIndex": mapping.glyphIndex}
  result["mappings"] = mappings
  var kernings = newJArray()
  for pair in font.kerning:
    kernings.add %*{"leftCodePoint": pair.leftCodePoint,
      "rightCodePoint": pair.rightCodePoint,
      "amountX": pair.amountX, "amountY": pair.amountY}
  result["kerning"] = kernings
  var substitutions = newJArray()
  for substitution in font.substitutions:
    substitutions.add %*{"sourceCodePoint": substitution.sourceCodePoint,
      "replacementCodePoint": substitution.replacementCodePoint}
  result["substitutions"] = substitutions
  var ligatures = newJArray()
  for ligature in font.ligatures:
    ligatures.add %*{"components": ligature.components,
      "glyphIndex": ligature.glyphIndex}
  result["ligatures"] = ligatures

proc audioNode(resource: VextResourceNode): JsonNode =
  let sound = resource.audioSound
  result = %*{"archetype": (if resource.audioKind == varkSound:
      "VextSound" else: "VextSampledInstrument"),
    "sampleRate": sound.sampleRate,
    "bitsPerSample": sound.buffer.bitsPerSample,
    "channels": sound.buffer.channels.len,
    "samplesPerChannel": sound.buffer.sampleCount}
  if resource.audioKind == varkSampledInstrument:
    result["oneShotSamples"] = %resource.instrument.oneShotSamples
    result["repeatSamples"] = %resource.instrument.repeatSamples
    result["samplesPerHighCycle"] = %resource.instrument.samplesPerHighCycle
    result["volume"] = %resource.instrument.volume
    result["pan"] = %resource.instrument.pan

proc exportMetadataJson*(resource: VextResourceNode,
    suggestedFilename = "metadata.json"): VextArtifactSet =
  if resource.isNil:
    raise newException(ValueError, "cannot export metadata for a missing resource")
  let kind = case resource.kind
    of vrnkGroup: "group"
    of vrnkRaster: "raster"
    of vrnkText: "text"
    of vrnkAudio: "audio"
    of vrnkFont: "font"
    of vrnkPalette: "palette"
    of vrnkOpaque: "opaque"
  var document = %*{"schema": "vexter.resource-metadata.v1",
    "path": resource.path, "type": resource.typeId, "kind": kind,
    "metadata": metadataNode(resource.metadata)}
  if resource.failureMessage.len > 0:
    document["failure"] = %*{
      "format": resource.failureFormat,
      "message": resource.failureMessage
    }
  var children = newJArray()
  for child in resource.children: children.add %child.path
  document["children"] = children
  document["resource"] = case resource.kind
    of vrnkGroup: %*{"children": resource.children.len}
    of vrnkRaster: rasterNode(resource.raster)
    of vrnkFont: fontNode(resource.font)
    of vrnkPalette: paletteNode(resource.palette)
    of vrnkAudio: audioNode(resource)
    of vrnkText: %*{"archetype": "text", "utf8Bytes": resource.text.len}
    of vrnkOpaque: %*{"archetype": "opaque",
      "rawDataAvailable": resource.rawDataAvailable,
      "bytes": (if resource.rawDataAvailable: resource.data.len else: 0)}
  result.artifacts.add VextArtifact(suggestedFilename: suggestedFilename,
    mediaType: "application/json", data: textBytes(document.pretty & "\n"))
