# Vexter plan

Vexter is a viewer and extractor for legacy file formats. Its name is a
portmanteau of “viewer” and “extractor”. This repository is a clean-room
implementation informed by requirements and lessons recovered from an earlier
implementation, without importing its source code or development notes.

The initial product is a command-line tool. A graphical interface will follow
later, using the same core library.

Implemented and historically supported formats are recorded separately in
[`docs/formats.md`](docs/formats.md).

This is the fourth major iteration of architecture since the project was
conceived.

## North star: a digital-archaeology workbench

Vexter's eventual scope is deliberately broad. It is not limited to raster
images, archives, or the media archetypes currently implemented. Documents,
outlines, tracker and sequenced music, interactive fiction, game resources,
vector drawings, CAD and 3D scenes, databases, presentations, hypermedia,
executables, filesystems, and formats not yet anticipated are all legitimate
subjects. Format work is selected according to current interest, available
evidence, and the architectural questions it can answer rather than a fixed
completion order.

The long-term goal is that an arbitrary legacy file produces something useful
even when Vexter cannot completely decode it. Understanding is graduated rather
than binary:

1. **Identify** a likely format, platform, era, encoding, compression, and the
   confidence and evidence supporting that conclusion.
2. **Describe** structural fields, offsets, checksums, strings, statistical
   properties, and anomalies without overstating uncertain interpretations.
3. **Inventory** members, chunks, tracks, resources, segments, scripts,
   embedded files, and external dependencies.
4. **Decode** semantic resources into reusable Vext archetypes.
5. **Render** useful previews of media, documents, interfaces, maps, scenes, or
   other representations.
6. **Export** recoverable content into durable or interoperable modern forms.
7. **Relate** companions, dependencies, nested containers, executables, and
   derived resources while retaining provenance.

A format handler need not reach every level before it is valuable. Partial
support should expose validated structure, retained raw data, and explicit
limitations so later work can deepen the same interpretation.

### Analysis and observations

Decoded resources are only one product of inspection. Vexter should eventually
carry structured analysis observations alongside them. An observation records
what was seen, where it was seen, how it was derived, and whether it is a fact
or a confidence-rated hypothesis. Candidate observations include:

- byte and value histograms, entropy maps, and repeating structures;
- strings, probable character encodings, filenames, and path-like values;
- magic values, embedded-file candidates, and chunk or record boundaries;
- probable byte order, word size, addresses, offsets, and checksums;
- compression, encryption, executable, filesystem, and platform indicators;
- annotated byte ranges and links between observations and resources; and
- carving suggestions and recoverable raw regions when semantic decoding is
  unavailable.

These observations should support human-readable and machine-readable reports,
an annotated hexadecimal or structural view, recursive inspection, and future
tools for investigating unknown files. Confidence and provenance must remain
visible: a statistical suggestion is not a detected format, and a carved
region is not necessarily an independent file.

The aspirational format and capability catalogue is maintained in
[`docs/candidate-formats.md`](docs/candidate-formats.md). It is a menu for
choosing interesting work and anticipating archetypes, not a roadmap or claim
of support. Implemented behavior remains documented in
[`docs/formats.md`](docs/formats.md), while gaps in already recognized formats
remain in [`docs/outstanding.md`](docs/outstanding.md).

## Source and research policy

Do not search the internet for Vexter research or implementation resources.
Format knowledge must come from established knowledge already available to the
developer or from documentation and samples supplied directly to the project.
If that information is insufficient or uncertain, stop and ask for the needed
documentation or clarification rather than looking it up externally.

User-supplied format documentation and fixtures should be recorded with enough
provenance to explain what informed the implementation and what behavior the
tests establish.

## Architectural model

Vexter separates format-specific input handling from generic transformations
and output encoding:

```text
source collection
  -> detected container
    -> resource tree
      -> in-memory Vext archetype
        -> optional transformation
          -> exporter
            -> in-memory artifact set
```

### Sources and containers

A source is not necessarily one file. It may be:

- a standalone file;
- an archive containing other containers;
- an index file referring to companion data files; or
- a directory-backed collection.

A container interprets a source and exposes resources. This accommodates
standalone images as well as collections such as SCUMM and SCI games, whose
central indexes refer to other files. Archives such as ZIP and LHA can expose
their members while allowing recognized members to be opened recursively as
containers.

Format detection is evidence-based. A detector returns candidates, confidence,
and the evidence used to reach that confidence. Evidence may include file size,
extension, magic bytes, structural validation, or some combination. Some
generic containers may later be identified more specifically after their
contents are inspected. Callers can bypass or constrain detection by supplying
an input format identifier.

Physical carrier detection and semantic package identification are separate
stages. A package handler declares its carrier by stable identifier; after the
carrier has been parsed, registered refiners may derive a more-specific format
from that parsed value. Derivations may contain multiple stages and are not
specific to ZIP. The carrier remains a valid candidate, and forcing its format
identifier deliberately requests generic carrier inspection.

Every supported type has a stable machine-readable identifier. The first is:

```text
zx-spectrum.screen
```

Identifiers are used by detection results, inspection JSON, handler
registration, diagnostics, tests, and `--input-format`.

### Resources and paths

Resources are addressable through canonical paths relative to their root
container. Paths express meaningful domain structure rather than host
filesystem locations. Examples recovered from the previous design include:

```text
/pic/1/visual
/view/1/2/3
```

The latter identifies view 1, loop 2, cel 3 in a Sierra SCI view. Composite
resources and their independently exportable children can both appear in the
tree.

Exact resource selection and pattern selection are distinct operations:

- `export --resource PATH` selects exactly one resource;
- `export-all --resource PATH-PATTERN` selects multiple resources;
- `*` matches exactly one complete path segment and never crosses `/`;
- recursive `**` matching is not supported;
- repeated `--resource` patterns form a union, with duplicate matches exported
  once; and
- omitting patterns from `export-all` selects all eligible resources.

Resource paths are structured Vexter identifiers. They are separate from
display names and exporter-generated filenames.

### Vext archetypes

Containers decode resources into generic in-memory data contracts called Vext
archetypes. They are loosely grouped, not arranged into a strict inheritance
hierarchy. The boundaries between media categories are deliberately flexible.

Expected archetypes include:

- indexed and true-colour raster images;
- collections of images;
- colours and palettes;
- animations, including frames, composition, and explicit durations;
- fonts with mono, indexed, or true-colour glyphs, metrics, and kerning;
- audio samples, buffers, sampled instruments, and sounds; and
- structured metadata associated with containers, resources, representations,
  frames, glyphs, or samples.

One source resource may support more than one useful interpretation. For
example, a ZX Spectrum screen can be represented as its natural indexed image
or as a two-frame animation when it contains FLASH attributes.

Transformations remain separate from exporters. Arranging an image collection
as a spritesheet produces another indexed or true-colour image, which is then
passed to an ordinary image exporter. Similarly, colour cycling or FLASH can be
rendered into animation frames before an APNG or GIF exporter sees the data.
Exporters do not need knowledge of the originating legacy format.

Metadata is orthogonal to media archetypes. It may be inspected, embedded by an
exporter, written as a JSON sidecar, used to guide a transformation, or omitted.

### Exporters and artifacts

Exporters accept generic Vext values and return artifacts in memory. An export
returns an artifact set because one logical output may require several files.
For example, BMFont output consists of a descriptor and a texture atlas even
though it is one atomic export operation.

The caller decides where artifacts are written and owns collision and overwrite
policy. Most exporters will return one artifact, but compound output is not a
special case in the core model.

## `vexterlib`, CLI, and GUI

All inspection, detection, container traversal, resource selection, decoding,
transformation, and export behavior is brokered through `vexterlib`.
`vexterlib` accepts requests and returns in-memory objects. The caller can
inspect those objects, choose resources and options, and pass decoded values to
an exporter.

The CLI is a thin client responsible for:

- parsing command-line arguments;
- reading sources and writing artifacts;
- selecting operations and passing requests to `vexterlib`;
- presenting progress and diagnostics; and
- formatting human-readable or JSON output.

The eventual GUI will call `vexterlib` directly rather than invoking the CLI.
The core API should consequently avoid terminal-specific assumptions and leave
room for structured diagnostics, progress reporting, cancellation, and
in-memory use.

Core behavior is developed through the CLI and its tests run on every routine
build. The later GUI will have a separate suite for GUI-specific and
platform-dependent behavior, which will not run on every build.

## Command-line interface

The intended command shape is:

```text
vexter inspect [--json] [--all-candidates] [--input-format FORMAT] INPUT

vexter export [--format png|gif|apng|bmfont|metadata-json] [--resource PATH]
              [--input-format FORMAT]
              [--pixel-aspect preserve|square]
              [--ilbm-mode indexed|ehb|ham6|ham8]
              [--pcx-channel-order rgb|bgr]
              [--workbench-palette auto|1.3|2.x]
              [--implied-transparency] [--drawing-progress] [--spritesheet]
              [--metadata-sidecar]
              [-o OUTPUT] [--force] INPUT

vexter export-all [--format png|gif|apng|bmfont|metadata-json]
                  [--resource PATH-PATTERN]...
                  [--input-format FORMAT]
                  [--pixel-aspect preserve|square]
                  [--ilbm-mode indexed|ehb|ham6|ham8]
                  [--pcx-channel-order rgb|bgr]
                  [--workbench-palette auto|1.3|2.x]
                  [--implied-transparency] [--drawing-progress]
                  [--spritesheet] [--metadata-sidecar]
                  -o DIRECTORY [--force] INPUT
```

Options fall into separate internal categories even if the CLI presents a flat
interface:

- input detection and override;
- decoder-specific interpretation;
- representation and transformation;
- exporter selection;
- supplementary artifacts;
- resource selection; and
- destination and overwrite policy.

Components should receive only options that apply to them. This will also let a
future GUI discover and display relevant controls without hard-coding every
format's settings.

## Tests, fixtures, and provenance

Fixtures are first-class correctness and provenance evidence. Each real fixture
should record, as applicable:

- its source and acquisition or generation procedure;
- its redistribution and licensing status;
- cryptographic hashes;
- expected dimensions, palettes, timing, or other relevant properties; and
- the specific behavior it proves.

Synthetic unit fixtures remain useful but should be distinguishable from
authentic compatibility fixtures and independently produced control outputs.

Control files may be optimized and their encoded structure need not be part of
the contract. Tests should compare semantic results, such as expanded pixel
colours and fully composited animation frames, while ignoring irrelevant
encoding choices. Fixture-specific provenance, coverage, and hashes should be
recorded alongside the files.

Decoded Vext objects are also tested directly so an importer and exporter defect
cannot accidentally cancel out. Timing is tested as archetype data rather than
being inferred from an optimized control file unless timing is explicitly part
of that fixture's contract.

## Near-term development

Near-term work is chosen from concrete formats and capabilities rather than a
fixed sequence. Small coverage additions that reuse existing archetypes are
useful, as are deliberate archetype probes and difficult containers that expose
architectural pressure. Abstractions should continue to be introduced in
response to those concrete requirements rather than designed to satisfy the
entire candidate catalogue in advance.
