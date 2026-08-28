# Candidate formats and archaeological capabilities

This is Vexter's non-binding catalogue of possible future work. Nothing here is
implemented merely because it is listed, and ordering does not express
priority. The catalogue exists to preserve interesting directions, anticipate
new Vext archetypes, and provide a menu when choosing what to investigate next.

Current and historical support is recorded in [`formats.md`](formats.md).
Concrete gaps in formats Vexter already recognizes are recorded in
[`outstanding.md`](outstanding.md). The wider digital-archaeology goal and
source policy are defined in [`../PLAN.md`](../PLAN.md). In particular, this
list is not authority for a file layout: implementation still requires
developer knowledge or documentation and samples supplied directly to the
project, with appropriate provenance.

The list is intentionally expandable and incomplete. No file, media category,
platform, or degree of obscurity is outside the project's potential scope.

## Choosing a piece of work

A candidate can be attractive for several independent reasons:

- a **coverage win** reuses established archetypes and exporters;
- an **archetype probe** makes Vexter represent a new kind of information;
- a **system stressor** exercises companions, recursion, composition,
  interactivity, version families, or large collections;
- a **recovery tool** makes damaged, obscure, or only partly understood files
  more useful;
- a **historical curiosity** is worthwhile without needing broader strategic
  importance; or
- a **compatibility target** is represented by available authentic material.

Useful catalogue details, as they become known, include platform and era,
extensions and identifiers, documentation and fixture provenance, likely
resources, required archetypes, plausible exports, implementation uncertainty,
and the useful understanding levels that can be reached without full decoding.

## Named areas of interest

### Tracker, sequenced, and game music

- Music formats and replay systems associated with David Whittaker, Jason
  Page, and Chris Huelsbeck, including relevant TFMX-family material.
- SoundTracker, NoiseTracker, ProTracker and other MOD-family formats.
- MED and OctaMED; AHX and HivelyTracker; Future Composer; SidMon; Delta Music;
  Digital Mugician; SoundMon; Hippel/COSO-family and other custom replay
  formats.
- S3M, XM and IT, AdLib/register-stream formats, MIDI and RIFF MIDI.

These formats may require sample and instrument banks, patterns, orders,
effects, tempo changes, channel state, loops, subsongs, synthesized voices, and
possibly retained or analysed replay code. A rendered audio buffer is a useful
representation but should not replace recoverable musical structure.

### Documents, outlines, and publishing

- WordStar and other control-code-oriented word-processing formats.
- GrandView, PC-OUTLINE, MORE!, and related outline and dot-command formats.
- Early WordPerfect and Microsoft Word generations.
- AmigaWriter, ProWrite, Final Writer, Excellence!, PageStream, Professional
  Page, AmigaGuide, and other Amiga document or publishing formats.
- Older RTF dialects and further word-processing, outliner, spreadsheet,
  database, desktop-publishing, and electronic-book formats.

These suggest both a hierarchical outline archetype and a broader structured
document archetype. Importers should preserve paragraphs, spans, hierarchy,
styles, tabs, layout, pagination, notes, links, embedded objects, source
controls, encodings, and uninterpreted data where applicable. Plain text,
Markdown, HTML, ODT, or DOCX are potential projections with different losses;
none should define the internal model.

### Animation, presentation, and hypermedia

- MovieSetter and other Amiga animation-authoring formats.
- CanDo, Scala and Scala Interactive/Multimedia, AmigaVision, Deluxe Video, and
  other presentation or kiosk systems.
- HyperCard and compatible stacks, Director/Shockwave, older PowerPoint
  generations, and other card, timeline, presentation, or multimedia formats.

Even without complete playback, useful inspection can expose scenes, pages,
cards, timelines, sprites, transitions, scripts, links, fonts, images, sounds,
external assets, and a navigation or dependency graph.

### Vector graphics, CAD, and 3D

- CorelDRAW version families.
- Art Expression, Professional Draw, GEM Draw, Windows Metafile, Computer
  Graphics Metafile, and other structured drawing formats.
- AutoCAD DXF/DWG generations and other CAD formats.
- Imagine, LightWave, Sculpt 3D, TurboSilver, Real3D, Vista/Dem, OBJ, 3DS, and
  other object, scene, material, landscape, or interchange formats.

Likely archetypes include vector paths and paint, pages and layers, meshes,
materials, cameras, lights, animation, spatial hierarchies, and external asset
references. A product name may cover substantially different on-disk
generations and therefore several separate implementation projects.

### Interactive fiction and game systems

- Z-machine story files and Blorb resource containers.
- TADS 2 and TADS 3 files.
- Sierra AGI and SCI resources and games.
- SCUMM resource families and games.
- Magnetic Scrolls, Level 9, Infocom auxiliary graphics and sound, Adventure
  Game Studio, and other engine-specific archives, scripts, and data.

Useful early support need not include an interpreter. Headers, version and
platform evidence, memory or resource maps, dictionaries, strings, object and
room inventories, scripts or bytecode, images, animation, fonts, audio, music,
and companion relationships can all be exposed incrementally. AGI, SCI, and
SCUMM are especially valuable tests of multi-file source collections and
cross-resource relationships.

### Sampled audio and related media

- Sun/NeXT AU/SND as a bounded follow-up to Creative Voice and WAV.
- Additional legacy sampled-audio, instrument, speech, chip-sound, music, and
  streaming formats across supported and future platforms.
- Animation, video, subtitle, and multiplexed-media containers whose useful
  resources can be inventoried before every codec is available.

## The arbitrary Aminet-file goal

A long-term compatibility target is to download an arbitrary file from Aminet
and obtain useful information or recoverable content. This does not require
every application format to be completely decoded. It does require broad
support for the layers commonly surrounding that content:

- additional LHA methods and headers, XPK compressors, historical archives,
  disk images, filesystems, installers, packages, and self-extractors;
- Amiga Hunk variants, libraries, devices, datatypes, overlays, resident
  modules, executable packers, and embedded data;
- CrunchMania, StoneCracker, Imploder, PowerPacker variants, and other common
  compressors or wrappers when sufficient references are supplied;
- common Amiga image, animation, sample, module, font, document, object, and
  application-resource formats; and
- bounded recursive identification and extraction with exact provenance at
  every layer.

The desired progression is:

```text
wrapper, archive, filesystem, or executable recognition
  -> bounded recursive unpacking and inventory
  -> platform and structural analysis
  -> known-format decoding
  -> embedded-resource discovery
  -> generic archaeological observations
  -> provenance-preserving raw extraction
```

## Workbench capabilities

Format handlers alone cannot make unknown material useful. Candidate generic
analysis and investigation facilities include:

- byte, word, symbol, and value histograms;
- rolling or region-based entropy and compressibility views;
- string extraction with explicit encoding hypotheses;
- magic and embedded-format scanning without treating every byte coincidence
  as a valid container;
- repeating-record, stride, delimiter, padding, and alignment suggestions;
- endian-aware numeric, offset, address, timestamp, colour, and checksum views;
- annotated hexadecimal and structural views linked to resources and metadata;
- bounded file carving with source offsets and confidence retained;
- comparison and structural diffing between related files;
- companion-name, path, executable, library, and platform indicators;
- optional architecture-aware disassembly hooks separated from file-format
  facts; and
- exportable machine-readable observation reports for further analysis.

Observations must distinguish validated facts, handler interpretations, and
heuristic hypotheses. They should record byte ranges, derivation, confidence,
warnings, and source ancestry. Unknown and opaque regions remain first-class
recoverable resources rather than disappearing when a partial decoder succeeds.

## Further families to grow

The catalogue should continue to expand across raster and vector graphics,
fonts, palettes, animation and video, sampled and synthesized audio, tracker and
sequenced music, documents and publishing, spreadsheets and databases, archive
and compression formats, disk and tape images, filesystems, executables and
object files, firmware, source and tokenized languages, game engines and asset
collections, CAD and 3D, scientific and geographic data, communications and
capture formats, hypermedia, and platform-specific application resources.

Breadth is a source of architectural evidence, not a reason to design every
archetype in advance. Each implemented format should deepen the model only as
far as concrete supplied evidence requires.
