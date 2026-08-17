# Vexter plan

Vexter is a viewer and extractor for legacy file formats. Its name is a
portmanteau of “viewer” and “extractor”. This repository is a clean-room
implementation informed by requirements and lessons recovered from an earlier
implementation, without importing its source code or development notes.

The initial product is a command-line tool. A graphical interface will follow
later, using the same core library.

This is the fourth major iteration of architecture since the project was
conceived.

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

The initial CLI implements the useful subset required by the first format:

```text
vexter inspect [--json] [--all-candidates] [--input-format FORMAT] INPUT

vexter export [--format png|gif] [--resource PATH]
              [--input-format FORMAT] [-o OUTPUT] [--force] INPUT
```

## First format: ZX Spectrum raw screen

A raw ZX Spectrum screen is a 1:1 dump of Spectrum display memory:

- 6,144 bytes of non-linearly arranged bitmap data;
- 768 bytes of colour attributes;
- exactly 6,912 bytes in total;
- a 256 x 192 display; and
- commonly, but not necessarily, a `.scr` extension.

It has no magic signature. An exact size match, strengthened by a `.scr`
extension, identifies `zx-spectrum.screen` as **probable**, not certain. The
container exposes one resource:

```text
/screen
```

The current decoder produces a `VextIndexedAnimation`. Its first frame is the
natural display state. If any attribute has its FLASH bit set, a second frame
swaps ink and paper in flashing cells. Both frames currently have a duration of
320 milliseconds. A screen without FLASH has one frame.

Default output is selected through the archetype content:

```text
non-FLASH screen -> one-frame indexed animation -> PNG
FLASH screen     -> two-frame indexed animation -> GIF
```

An explicit `--format png` exports the natural first frame. The PNG and animated
GIF encoders have no external dependencies. Their first versions favor simple,
deterministic correctness over file size: PNG uses stored DEFLATE blocks and
GIF uses valid low-compression LZW output.

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

The first fixture set is stored under:

```text
tests/fixtures/zx-spectrum.screen/
```

It contains `.scr` dumps with PNG controls showing their natural states and GIF
controls showing their animated states. The primary `colours` fixture was
freshly produced for this project using a Spectrum program. Its attribute grid
exhaustively exercises ink, paper, BRIGHT, and FLASH values. The control images
may be optimized and their encoded structure is not part of the contract. Tests
compare expanded pixel colours and positions, and animated controls are compared
as fully composited frames. Palette ordering, compression, chunk layout, frame
cropping, and other encoding choices are ignored. Fixture-specific provenance,
coverage, and hashes are recorded alongside the files.

Decoded Vext objects are also tested directly so an importer and exporter defect
cannot accidentally cancel out. Timing is tested as archetype data rather than
being inferred from an optimized control file unless timing is explicitly part
of that fixture's contract.

## Historical compatibility targets

The previous implementation covered formats including:

- IFF ILBM, ACBM, ANIM3, ANIM5, ANIM7, ANIM8, and 8SVX;
- PCX, QOI, TGA, NetPBM, BMP, ICO, and CUR images;
- Commodore 64 Koala Painter;
- AMOS sprite banks, icon banks, bank sets, and programs with paired banks;
- AmigaDOS `.info` files and diskfonts;
- Atari DEGAS and NEOchrome;
- DOOM WAD sprites and textures;
- ZX Spectrum screens from raw dumps, SNA snapshots, and TAP images, plus FZX
  fonts;
- SCUMM versions 3 through 8 rooms, room objects, and costumes;
- SCI0 through SCI2 pictures, views, sound effects, and speech; and
- ZIP and LHA archives with recursive container inspection.

This list is a compatibility target and architectural test matrix, not an
immediate implementation schedule. Early interfaces should be checked against
representative hard cases so they do not preclude nested containers, companion
files, composite resources, animation, palettes, audio, metadata, or compound
artifact output.

## Near-term development

The first vertical slice now establishes:

- the `vexterlib` public entry point;
- indexed image and indexed animation values;
- evidence-based detection for `zx-spectrum.screen`;
- `/screen` resource inspection;
- correct Spectrum bitmap, colour, BRIGHT, and FLASH decoding;
- dependency-free PNG and animated GIF artifacts;
- human-readable and JSON inspection;
- exact resource selection and overwrite protection in `export`; and
- library and CLI regression tests against the supplied controls.

Likely next steps are to formalize common request, container, resource-tree, and
diagnostic types before adding enough formats to make premature abstractions
visible. `export-all`, segment-based wildcard matching, metadata sidecars,
transformations, recursive containers, and richer exporter selection can then
be added against concrete format requirements.
