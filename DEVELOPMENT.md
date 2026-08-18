# Vexter development state

This document describes the repository as it exists now. It is the starting
point for maintenance and implementation work. [`PLAN.md`](PLAN.md) describes
the intended trajectory and must not be read as a list of implemented
features. [`docs/formats.md`](docs/formats.md) records current and historical
format coverage in greater detail.

## Current product surface

Vexter currently consists of a reusable Nim library and a thin command-line
client. It supports:

- detection and inspection of generic IFF FORM containers, indexed Amiga ILBM
  and ACBM images, IFF ANIM animations, PCX, BMP/DIB, and PNG images, AmigaDOS ADF filesystems, ZIP archives, ZX Spectrum raw screen dumps, SNA snapshots,
  TAP containers, tokenised BASIC resources, standalone AMOS banks, AMOS bank
  sets, and AMOS programs;
- a resource tree containing decoded indexed-raster or identified opaque
  resources, decoded text resources, and metadata;
- indexed still-image, indexed-animation, and true-colour image raster
  archetypes;
- PNG export for a still image or an animation's natural first frame; and
- animated GIF and APNG export.

The implemented command-line surface is:

```text
vexter inspect [--json] [--all-candidates] [--ignore-warnings]
               [--input-format FORMAT] [--pcx-channel-order rgb|bgr] INPUT

vexter export [--format png|gif|apng|txt] [--resource PATH]
              [--input-format FORMAT] [-o OUTPUT] [--force]
              [--ignore-warnings] [--pcx-channel-order rgb|bgr] INPUT
```

There is no GUI, fully generalized handler registry, `export-all`,
path-pattern selection, or generalized handler registry yet. ADF files do
perform bounded recursive inspection of recognized contained files. Those and the broader option
surface shown in `PLAN.md` are future work.

## Architectural flow

The currently implemented path through the application is:

```text
file bytes
  -> evidence-based detection or a validated forced format
  -> format-specific container parsing and resource extraction
  -> VextResourceTree
  -> raster, text, or identified opaque resources
  -> PNG/GIF raster export or plain-text export
  -> in-memory VextArtifactSet
  -> CLI-owned filesystem write
```

The library owns detection, forced-format validation, container inspection,
resource construction and selection, default output-format choice, and
exporter invocation. The CLI owns argument parsing, reading source files,
formatting inspection output, destination selection, collision policy, and
writing artifacts. Keep these responsibilities separated so a future GUI can
call `vexterlib` without reproducing CLI behavior.

## Source layout and responsibilities

`src/vexterlib.nim` is the public facade. It imports and re-exports the current
public library modules.

`src/vexter.nim` is the CLI. It should remain a thin client of the operations
API. In particular, format validation, resource selection, decoding, and
export-format defaults do not belong here.

`src/vexterlib/operations.nim` brokers high-level library work:

- `inspectSource` detects or validates a format and builds a decoded resource
  tree;
- `VextInspection` carries the selected candidate, all detected candidates,
  and the resource tree; and
- `exportResource` selects one raster resource, chooses PNG or GIF when no
  format was requested, and returns an in-memory artifact set.

`src/vexterlib/resource_tree.nim` defines `VextResourceTree` and
`VextResourceNode`. Nodes are reference objects and currently have the
`vrnkGroup`, `vrnkRaster`, `vrnkText`, or `vrnkOpaque` kind. `leafResources`
returns every
addressable non-group node, while `rasterResources` returns only raster nodes
in depth-first tree order. `findRasterResource` performs exact path lookup
over raster nodes. Groups are structural and opaque resources are inspectable
but neither is exportable through the current raster export operation.

`src/vexterlib/detection.nim` contains evidence-based detection. Candidates
are ordered strongest-first. Structurally valid AMOS banks with exact magic
identifiers are `vdcCertain`; current ZX Spectrum detectors are `vdcProbable`.
Matching case-insensitive extensions add supporting evidence.

`src/vexterlib/containers/` contains source/container rules:

- `amiga_adf.nim` validates standard DD/HD AmigaDOS floppy images and walks
  OFS/FFS directory, file-header, extension, and data-block structures;
- `zip_archive.nim` validates single-volume ZIP central/local records, expands
  stored and DEFLATE entries, checks CRC-32, and exposes a host-independent
  archive hierarchy;
- `pcx.nim` validates ZSoft PCX headers, dimensions, plane layouts, and row
  storage before retaining the encoded image source;
- `bmp.nim` validates wrapped BMP files and standalone Windows or OS/2 DIBs,
  including palette, bitfield, compression, and pixel-data boundaries;
- `png_container.nim` validates PNG signatures, chunk framing/order, CRC-32,
  image properties, palettes, transparency, and concatenated IDAT data while
  retaining every known or unknown chunk for metadata;
- `amiga_iff.nim` validates generic IFF `FORM` lengths, chunk boundaries, and
  even-byte padding;
- `amiga_acbm.nim` interprets `FORM ACBM` properties and extracts its
  plane-contiguous `ABIT` image source;
- `amiga_ilbm.nim` interprets `FORM ILBM` properties and extracts the image
  source while leaving raster decoding separate;
- `amiga_anim.nim` parses nested ILBM frame forms and their ANHD/DLTA records;
- `amos_bank.nim` validates generic `AmBk` headers and lengths and identifies
  otherwise unsupported bank payloads, retaining those bytes so nested
  specialized bank resources can be decoded;
- `amos_packed_picture.nim` parses `Pac.Pic.` screen/picture headers and
  expands its nested PICDATA/RLEDATA/POINTS compression into planar bytes;
- `amos_bank_set.nim` validates `AmBs` collections and delimits their adjacent
  generic, sprite, and icon bank members;
- `amos_program.nim` validates AMOS Basic/Professional headers, locates the
  tokenised listing boundary, and parses the mandatory bank-set appendix;
- `amos_sprite_icon_bank.nim` validates standalone `AmSp` and `AmIc` banks,
  extracts their records and shared palette, and retains image hotspots;
- `zx_spectrum_screen_dump.nim` validates and extracts a standalone 6,912-byte
  screen dump;
- `zx_spectrum_snapshot.nim` validates supported SNA sizes, extracts the
  current 6,912-byte display-memory region, and locates BASIC in 48K RAM via
  the `PROG` system variable; and
- `zx_spectrum_tap.nim` validates TAP block framing/checksums and extracts
  qualifying CODE screen records and Program records.

Container modules deal in source structure and extracted resource bytes. They
must not own raster rendering or exporter behavior.

`src/vexterlib/resources/amos_planar_image.nim` defines reusable AMOS sprite
and icon image data and converts plane-major data into indexed rasters. The
bank parser and resource decoder are deliberately separate so ABS/program
containers can expose the same image resources later.

`src/vexterlib/resources/amos_packed_picture_image.nim` converts decompressed
Pac.Pic. planes and the screen header's `$0RGB` palette into an indexed raster.
Whole-screen one-through-five-plane pictures are supported. Partial pictures
without a screen header remain structurally parseable but cannot be rendered
without an external palette; six-plane Pac.Pic. modes also remain deferred.

`src/vexterlib/resources/pcx_image.nim` expands raw or PCX RLE scanlines and
renders one-through-four-bit indexed planar images, eight-bit indexed images,
and eight-bit three-plane true-colour images. The true-colour plane order is
selectable as RGB or BGR at the operations boundary.

`src/vexterlib/resources/bmp_image.nim` renders packed indexed BMP/DIB rows,
RLE4/RLE8 streams, BGR true-colour rows, and normalized 16/32-bit colour
bitfields. It handles bottom-up and uncompressed top-down storage.

`src/vexterlib/resources/png_image.nim` inflates and unfilters every PNG
scanline, expands all standard colour types and legal bit depths, applies
palette or `tRNS` alpha, and reconstructs Adam7 passes. APNG and unknown chunks
do not affect the decoded default image.

`src/vexterlib/resources/amiga_ilbm_image.nim` decodes uncompressed or
ByteRun1-compressed planar data: scanline-interleaved planes from ILBM `BODY`
chunks and whole sequential planes from ACBM `ABIT` chunks. It produces
indexed images for one through five ordinary planes and six-plane EHB, and
true-colour images for HAM/HAM8. Legacy CMAPs whose component low nibbles are
uniformly zero are expanded by nibble replication. The raster archetypes now
support alpha, but ILBM mask and transparent-colour decoding remains pending.

`src/vexterlib/resources/amiga_anim_image.nim` reconstructs retained planar
buffers with ANIM delta methods 5, 7, and 8, including interleave references
and method-5 XOR used by Deluxe Paint animation brushes. It then renders each
frame through the same indexed/EHB/HAM ILBM path as still images. Methods 1–4,
6, and 74 are identified but report explicit unsupported-method errors.

`src/vexterlib/resources/amos_listing.nim` reconstructs diagnostic AMOS source
text from line records and complex tokens. `amos_listing_tokens.nim` contains
the imported simple-symbol and recognized-extension mappings. Unknown tokens
remain visible as bracketed hexadecimal. Encrypted procedure bodies are
decrypted in a preprocessing pass using the evolving AMOS procedure keys;
restored lines then use the ordinary diagnostic token decoder.
The `Fold.Acc` accessory on the locally supplied AMOS source disk confirmed
this layout: it has an ordinary `AMOS Basic V1.00` program container and a
656-byte encrypted procedure implementing its procedure-locking behavior.
There is not yet structural evidence for a separate accessory container type;
`.Acc` alone is not used as one.
The decrypted accessory also confirmed the core token mappings `$011c`
`Border$`, `$0cd8` `Default Palette`, `$220a` `Bset`, `$2296` `Areg`, and
`$22a2` `Dreg`. With these mappings its listing decodes without diagnostic
unknown-token forms.

`src/vexterlib/resources/zx_spectrum_screen.nim` defines the reusable
`zx-spectrum.screen` resource and its decoder. A standalone screen dump is a
container whose type identifier currently aliases this resource identifier;
snapshots and TAP files expose the same resource type from within different
container types. The decoder returns a `VextIndexedImage` when no FLASH bits
are present and a two-frame `VextIndexedAnimation` when FLASH is present.

`src/vexterlib/resources/zx_spectrum_basic.nim` reconstructs readable UTF-8
source from tokenised Spectrum BASIC line records. Fixed block graphics use
Unicode quadrant/block characters. Runtime-defined UDGs and embedded display
controls use reversible `⟦UDG A⟧` and `⟦INK 2⟧`-style annotations, preceded
by explanatory `REM VEXTER:` lines only when required. Unknown bytes use
`⟦ZX:$HH⟧`. A line number at or above 32768 marks the variables boundary.

`src/vexterlib/archetypes/raster.nim` contains the generic indexed image,
indexed animation, true-colour image, and true-colour animation contracts.
Indexed and true-colour images may carry an orthogonal per-pixel eight-bit
alpha channel; an omitted channel means fully opaque. `alphaAt`, `rgbaAt`, and
`hasAlpha` provide representation-independent access and validation.
`src/vexterlib/exporters/` consumes those contracts and
has no ZX Spectrum-specific knowledge. `src/vexterlib/artifacts.nim` defines
the in-memory output contract; callers, not exporters, write files.
`src/vexterlib/metadata.nim` defines typed key/value metadata currently used
for signed AMOS hotspot coordinates.

The former `containers/zx_spectrum_screen.nim` and top-level
`vexterlib/resources.nim` screen-dispatch module have been replaced by the
container/resource split, generic resource tree, and operations layer. Do not
reintroduce type-switching resource dispatch into the CLI.

## Current format and resource behavior

Stable type identifiers are:

```text
amiga.adf
amiga.adf-directory
amiga.adf-file
amiga.adf-link
archive.zip
archive.zip-directory
archive.zip-file
pcx
pcx.image
windows.bmp
windows.dib
windows.bitmap
png
png.image
amiga.iff
amiga.acbm
amiga.ilbm
amiga.ilbm-image
amiga.anim
amos.bank
amos.bank-data
amos.bank-set
amos.packed-picture
amos.program
amos.tokenised-listing
amos.sprite-bank
amos.icon-bank
amos.sprite
amos.icon
zx-spectrum.screen
zx-spectrum.snapshot
zx-spectrum.tap
zx-spectrum.basic
```

Generic IFF forms expose an inspectable `/chunks` group with opaque numbered
chunk resources. Supported ILBMs and ACBMs instead expose one raster at
`/image` with header and CAMG metadata. Unknown bitmap chunks remain
structurally valid and are ignored by the current image decoder. HAM/HAM8
bitmaps expose a
`VextTrueColourImage` at the same path. True-colour PNG export is supported;
GIF export requires a future colour-quantization stage.

ADF volumes expose `/disk`, with filesystem directories represented as nested
groups. Unrecognized files are opaque leaves retaining their reconstructed
bytes. Recognized contained formats become groups whose normal decoded
resources are rebased below the file path, such as
`/disk/display.scr/screen`. Traversal is bounded to eight nested containers.
OFS, FFS, international, and directory-cache flag variants are recognized;
hard and soft links are identified but not followed. A failure while decoding
a recognized contained format reports the nested resource path before the
underlying decoder diagnostic. With `--ignore-warnings`, a failed child remains
available as an opaque file, successful siblings are retained, and structured
path/format/message warnings are returned and displayed.

ZIP archives expose `/archive`. Entry paths are interpreted as logical archive
paths rather than host paths: slash and backslash separators are canonicalized,
absolute, empty, dot, parent, duplicate, and file/directory-conflicting paths
are rejected, and complete entry names are capped at 255 Unicode characters.
Legacy names use ZIP's CP437 mapping and names marked UTF-8 are validated.
Stored and DEFLATE entries are supported with size and CRC-32 checks. Encrypted,
ZIP64, unsupported-compression, and classic multi-volume archives are rejected.
Recognized files open recursively using the same eight-layer bound and warning
behavior as ADF files. The library also supplies conservative cross-platform
filename normalization for eventual bulk export; collision suffixing remains
part of the future `export-all` work.

PCX images expose `/image`. One-, two-, and four-bit samples across up to four
planes use the 16-colour header palette; eight-bit single-plane images use the
mandatory trailing 256-colour palette. Eight-bit three-plane images produce a
true-colour raster. Scanline padding is excluded from output pixels and RLE
runs are bounded to individual scanlines. RGB plane order is the default;
`--pcx-channel-order bgr` selects files written in the alternate order.

BMP files and standalone DIBs expose `/image`. OS/2 core and Windows INFO,
V2/V3, V4, and V5 headers are recognized. Uncompressed 1/4/8-bit indexed,
16/24/32-bit true-colour, RLE4/RLE8, and 16/32-bit bitfield images are
supported. Palette and scanline padding are removed, bottom-up rows are
inverted, and top-down rows retain their order. Declared contiguous alpha
masks, including `BI_ALPHABITFIELDS`, populate the raster's per-pixel alpha
channel. Legacy 32-bit BI_RGB data without an alpha mask remains opaque.

PNG files expose `/image`. All five filters, Adam7 interlacing, standard
grayscale/indexed/true-colour colour types, 1/2/4/8/16-bit legal depths,
palettes, and transparency are decoded into indexed or true-colour rasters.
Every chunk's type and size is retained in inspection metadata. APNG chunks
and unknown standard/private chunks are reported there but ignored for static
default-image decoding; their presence is not an import failure.

Generic `AmBk` containers continue to expose unknown bank types as opaque bank
data. A `Pac.Pic.` bank with its screen palette instead exposes an indexed
`amos.packed-picture` raster at `/picture`; the same bank nested in an `AmBs`
or AMOS program uses its numbered `/banks/N` resource path.

ANIM containers expose `/animation`. Indexed animations that share an opaque
palette default to GIF, while HAM animations produce
`VextTrueColourAnimation` and default to APNG. Indexed images and animations
can also be explicitly exported as APNG; frames are expanded through their own
palettes, so palette changes and per-pixel alpha are preserved. When an
indexed animation cannot be represented by GIF because of palette changes or
alpha, APNG becomes its natural default. Delta-compressed first frames remain
deferred pending authentic samples.

Raw screen dumps expose one raster at `/screen`. A 48K SNA additionally exposes
decoded BASIC at `/listing` when `PROG` points to a valid listing; 128K BASIC
extraction is pending confirmed paging semantics. A TAP with
one qualifying screen exposes `/screen`. A TAP with multiple qualifying
screens has a `/screen` group and raster children `/screen/1`, `/screen/2`, and
so on. Program TAP records analogously expose `/listing` or numbered listing
children. A structurally valid TAP with no supported records has an empty tree.

Standalone AMOS banks expose a structural `/sprite` or `/icon` group and
zero-based numbered raster children. Hotspots are attached to each child as
`hotspot.x` and `hotspot.y` integer metadata. The current parser accepts both
the described header-palette layout and the fixture-confirmed trailing-palette
layout.

Generic `AmBk` files expose one opaque `/bank` resource with header metadata.
Their payload is deliberately not decoded or exported yet. This preserves an
identifiable resource in the tree for bank types that are not otherwise
supported.

AMOS `AmBs` sets expose a `/banks` group. Generic members are opaque
`/banks/N` leaves; sprite and icon members expose numbered raster children
beneath their member path. Prefix-aware member and set parsers also delimit
the `AmBs` appendix inside an AMOS program. `/listing` is decoded into an
exportable text resource, while attached banks retain the standalone set's
`/banks/N` hierarchy. The decoder is intentionally textual/diagnostic rather
than an AST and preserves unsupported tokens as hexadecimal.

When `--input-format` or the corresponding `inspectSource` argument is used,
the library still validates the bytes against that format. It does not merely
label arbitrary data. Unsupported identifiers and invalid data raise
`ValueError`; the CLI catches library errors and presents them with its normal
`vexter:` diagnostic prefix.

Single-resource export selects the requested exact raster path. When the path
is omitted, it succeeds only if exactly one raster is available. It fails for
zero or multiple raster resources. The natural default is GIF for a
GIF-compatible indexed animation, APNG for an indexed animation with changing
palettes or alpha, and PNG for an indexed image. Explicit PNG export of an
animation uses its natural first frame; explicit APNG is available for every
indexed raster that can be sent to GIF.

## Tests and fixtures

The routine suites are:

- `tests/test_amiga_adf.nim`: synthetic FFS directory traversal, OFS and FFS
  file reconstruction, nested format decoding, and structural corruption;
- `tests/test_zip_archive.nim`: stored/DEFLATE expansion, hierarchy and nested
  decoding, unsafe/duplicate/overlong path rejection, and portable export-name
  normalization;
- `tests/test_pcx.nim`: planar/header palettes, 256-colour trailing palettes,
  true-colour RGB/BGR order, row padding, RLE, and malformed input;
- `tests/test_bmp.nim`: Windows and OS/2 DIBs, wrapped BMP offsets, indexed and
  true-colour rows, top-down orientation, bitfields, RLE4/RLE8, and failures;
- `tests/test_png.nim`: RGBA and indexed transparency, grayscale and 16-bit
  samples, filters, Adam7 reconstruction, APNG/private chunk tolerance,
  metadata retention, CRCs, malformed required chunks, and every existing
  independently encoded PNG control;
- `tests/test_amiga_iff_ilbm.nim`: FORM/chunk validation, ILBM planar and
  ByteRun1 decoding, legacy palette expansion, EHB, focused HAM6/HAM8 cases,
  and authentic Deluxe Paint HAM6/HAM8 controls;
- `tests/test_amiga_acbm.nim`: ACBM detection, plane-contiguous raw and
  ByteRun1 ABIT decoding, and structural failure modes;
- `tests/test_amiga_anim.nim`: nested ANIM structure, methods 5/7/8, animation
  brush XOR behavior, timing, GIF routing, APNG output, the authentic TheTour
  method-5 control, and failure modes;
- `tests/test_zx_spectrum_screen.nim`: screen decoding, palette/pixel
  correctness, FLASH behavior, and encoder smoke tests;
- `tests/test_zx_spectrum_snapshot.nim`: SNA detection and screen extraction;
- `tests/test_zx_spectrum_basic.nim`: token, graphics, annotation, boundary,
  and 48K SNA BASIC extraction behavior;
- `tests/test_zx_spectrum_tap.nim`: TAP validation, extraction, and resource
  tree shapes;
- `tests/test_amos_sprite_icon_bank.nim`: AMOS bank parsing, icon/sprite
  distinctions, planar rendering against controls, hotspots, and malformed
  input;
- `tests/test_amos_bank.nim`: generic bank length masking, labels, opaque
  resources, metadata, and malformed input;
- `tests/test_amos_packed_picture.nim`: authentic two-stage decompression and
  planar rendering against the Castle AMOS PNG control, nested `AmBs`
  exposure, PNG export, and palette-less partial-picture behavior;
- `tests/test_amos_bank_set.nim`: mixed adjacent members, nested resource
  paths, prefix length reporting, export, and structural failures;
- `tests/test_amos_program.nim`: real Basic and synthetic Professional
  headers, listing boundaries, mandatory appendices, nested bank resources,
  export, and malformed input;
- `tests/test_operations.nim`: direct high-level library and resource-tree
  behavior; and
- `tests/test_cli.nim`: end-to-end CLI inspection, export, defaults, and file
  collision behavior.

`vx4.nimble` builds the CLI before running these suites. Authentic and
project-produced fixtures live under `tests/fixtures/`, with provenance and
hash records alongside them.

The current machine must run sustained work at low priority and with at most
two concurrent processes. A suitable full run is:

```sh
nice -n 15 nimble test
```

If Nimble attempts to manage or download a compiler, or cannot write its user
configuration/cache in a restricted environment, invoke the `nim c` commands
from the `test` task directly. Use a writable per-target cache such as
`--nimcache:/tmp/vx4-nimcache-operations`. Run the commands sequentially and
keep `nice -n 15` on each invocation. CLI tests accept a separately built
binary with:

```text
-d:VexterCliPath=/path/to/vexter
```

Generated test executables are ignored in `.gitignore`; add new test binary
names there when adding suites, or direct their output into `/tmp`.

## Constraints and near-term maintenance notes

- Preserve the clean-room source policy in `PLAN.md`. Do not browse for
  Vexter research or format implementation details.
- Preserve stable type identifiers and canonical resource paths unless a
  deliberate compatibility change is agreed.
- Prefer generic resource/archetype operations over format-specific branches
  in frontends and exporters.
- Resource nodes currently carry already-decoded raster values; opaque ADF and
  ZIP file leaves additionally retain their reconstructed bytes. Lazy decoding,
  alternate representations, structured metadata, and handler registration
  are not implemented yet. Recursive decoding is currently specific to ADF.
- Export currently expects one artifact at the CLI boundary. The artifact API
  already permits multiple files, but CLI directory handling for compound
  exports is future work.
- Recursive decoding is shared by ADF and ZIP, with a fixed eight-layer bound;
  it is not yet a handler registry. Detection currently parses some inputs again during inspection. There is no
  parsed-container cache or registry abstraction yet.
