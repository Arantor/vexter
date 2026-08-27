# Vexter development state

This document describes the repository as it exists now. It is the starting
point for maintenance and implementation work. [`PLAN.md`](PLAN.md) describes
the intended trajectory and must not be read as a list of implemented
features. [`docs/formats.md`](docs/formats.md) records current and historical
format coverage in greater detail. [`docs/outstanding.md`](docs/outstanding.md)
is the single concise index of known gaps in formats already recognized.

## Current product surface

Vexter currently consists of a reusable Nim library, a thin command-line
client, and a dependency-free native Windows GUI. It supports:

- classic Amiga Workbench `.info` DiskObjects, including metadata and both
  planar icon states;
- detection and inspection of generic IFF FORM containers, indexed Amiga ILBM
  and ACBM images, provisional packed-pixel IFF PBM images, IFF ANIM
  animations, IFF 8SVX and 16SV sampled audio,
  integer PCM WAV sounds, PCX, TGA, BMP/DIB,
  static DOS ANSI art with optional SAUCE metadata,
  classic DOOM IWAD/PWAD containers with palettes, flats, sprites, patches,
  composited wall textures, sampled sound effects, and other patch-format
  graphics,
  PNG, baseline/extended-sequential Huffman JPEG with EXIF orientation,
  OpenRaster layered documents, Windows ICO/CUR collections (including PNG and DIB entries), QOI,
  Commodore 64 KoalaPainter images,
  Netpbm P1–P7, GIF87a/GIF89a, and FLI/FLC-family animations,
  AmigaDOS ADF filesystems, DMS disk archives, PowerPacker and XPK/SHRI
  wrappers, ZIP archives, ISO 9660 data-CD filesystems, level-0/1 LHA/LZH archives using LH0 or LH5,
  minimally structured Amiga Hunk executables and LHA self-extractors,
  ZX Spectrum raw screen dumps, SNA snapshots,
  TAP containers, tokenised BASIC resources, BMFont text descriptors, FZX and Amiga bitmap diskfonts
  (including ColorFonts), standalone AMOS banks, AMOS bank
  sets, and AMOS programs;
- a resource tree containing decoded raster, palette, bitmap-font, audio, and text resources,
  identified opaque resources, and metadata;
- indexed still-image, indexed-animation, and true-colour image raster
  archetypes;
- a bitmap-font archetype with mono, indexed, or true-colour glyphs, explicit
  Unicode mappings, bearings, advances, line metrics, kerning, substitutions,
  and ligatures;
- PNG export for a still image or an animation's natural first frame, plus
  ordered palette swatches for palette resources and indexed rasters;
- animated GIF and APNG export;
- BMFont text export with one or more PNG atlas pages;
- metadata JSON export for every resource kind, including groups;
- self-contained HTML reports with embedded normalized media and metadata;
- optional CRNG/CCRT colour-cycle expansion with a 1,000-frame safety limit;
- byte-identical BIN export for opaque resources that retain raw data; and
- bulk export of all exportable leaves or a union of segment-wildcard resource
  patterns, preserving a safe resource-path hierarchy.

The implemented command-line surface is:

```text
vexter inspect [--json] [--all-candidates] [--ignore-warnings]
               [--input-format FORMAT] [--pcx-channel-order rgb|bgr]
               [--ansi-letter-spacing auto|8|9]
               [--ansi-aspect auto|legacy|square] INPUT

vexter export [--format png|gif|apng|gif-cycled|apng-cycled|bmfont|txt|wav|bin]
              [--resource PATH] [--allow-large-animation]
              [--input-format FORMAT] [-o OUTPUT] [--force]
              [--ignore-warnings] [--pcx-channel-order rgb|bgr]
              [--ansi-letter-spacing auto|8|9]
              [--ansi-aspect auto|legacy|square] INPUT

vexter export-all [--format png|gif|apng|gif-cycled|apng-cycled|bmfont|txt|wav|bin]
                  [--resource PATH-PATTERN]... [--input-format FORMAT]
                  -o DIRECTORY [--force] [--ignore-warnings]
                  [--pcx-channel-order rgb|bgr] [--allow-large-animation]
                  [--ansi-letter-spacing auto|8|9]
                  [--ansi-aspect auto|legacy|square]
                  INPUT
```

The Windows GUI is a Unicode Win32/common-controls client of `vexterlib`. It
loads files on a worker thread, exposes the complete resource hierarchy and
metadata leaves, previews raster animations, static-image colour cycling, and
sampled audio, and exports
through the library's discoverable per-resource format list. It targets the
Windows 7 API baseline and cross-compiles from Linux with MinGW-w64:

Contained resources carrying decode failures use the standard Windows warning
icon in the TreeView. Their ancestor groups expand automatically, and selecting
one shows its suspected format and decoder message in the text view.

```sh
nice -n 15 nimble gui
```

This writes `build/win32/vexter-gui.exe`. Build both command-line targets with:

```sh
nice -n 15 nimble cli
```

The CLI artifacts are `build/linux/vexter` and
`build/win32/vexter-cli.exe`. The task builds them sequentially.

The handler registry is authoritative for physical format identifiers and parser
dispatch. It also exposes a carrier-refinement registry for semantic package
formats: a handler can declare that it is carried by another registered format,
and its refiner receives the already parsed carrier. No semantic package
refiners are registered yet. ADF, ZIP, and LHA files also perform bounded
recursive inspection of recognized contained files. The broader option surface
shown in `PLAN.md` remains future work.

## Architectural flow

The currently implemented path through the application is:

```text
source file bytes plus an optional bounded companion resolver
  -> evidence-based physical-format detection or a validated forced format
  -> optional semantic refinements of the parsed carrier
  -> format-specific container parsing and resource extraction
  -> VextResourceTree
  -> raster, font, text, or identified opaque resources
  -> PNG/GIF raster, BMFont, WAV audio, plain-text, or raw BIN export
  -> in-memory VextArtifactSet
  -> frontend-owned filesystem write
```

The library owns detection, safe companion-name validation, forced-format validation, container inspection,
resource construction and selection, default output-format choice, and
exporter invocation. Frontends own input reading, presentation, destination
selection, collision policy, and artifact writing. The GUI calls `vexterlib`

Each detection candidate carries a derivation. A physical format has a
single-stage derivation such as `archive.zip`; a semantic package discovered
inside that carrier appends its stable identifier. Refiners are keyed by their
declared carrier identifier, can themselves be refined, and receive the exact
parsed value produced for the carrier rather than reparsing its bytes. Detection
keeps both the more-specific candidate and its generic carrier, ordering the
refinement first. Explicitly forcing the carrier bypasses refinement, preserving
generic inspection even when a package profile also matches.
directly and does not reproduce CLI behavior.

## Source layout and responsibilities

`src/vexterlib.nim` is the public facade. It imports and re-exports the current
public library modules.

`src/vexter.nim` is the CLI. It should remain a thin client of the operations
API. In particular, format validation, resource selection, decoding, and
export-format defaults do not belong here.

`src/vexter_gui.nim` is the native Windows GUI. It uses direct Win32, common
controls, GDI, common dialogs, and `waveOut`; it has no third-party GUI or media
dependencies. Presentation is selected only from generic resource and raster
archetype kinds, never from source format identifiers. The GUI is built with
Nim's ARC memory manager because decoded acyclic resource trees cross from its
inspection worker to the UI thread; ORC's thread-local cycle tracking must not
be used for that transfer.

`src/vexterlib/operations.nim` brokers high-level library work:

- `inspectSource` detects or validates a format and builds a decoded resource
  tree; callers may provide a companion resolver for validated multi-file
  indexes while retaining ownership of filesystem reads;
- `VextInspection` carries the selected candidate, all detected candidates,
  and the resource tree; and
- inspection optionally reports structured progress and supports cooperative
  cancellation through a callback;
- `exportFormatsFor` describes the formats and natural default supported by a
  resource archetype, so frontends need not duplicate exporter rules;
- `exportResource` selects one exportable resource, chooses its natural raster,
  text, audio, or raw format when none was requested, and returns an in-memory
  artifact set; and
- `exportAllResources` selects every exportable leaf or the deduplicated union
  of resource patterns, assigns safe hierarchical names, resolves normalized
  filename collisions deterministically, and returns all artifacts in memory.

`src/vexterlib/byte_sources.nim` defines bounded random-access byte sources and
source collections. A collection owns its primary source and any companions
opened through its resolver, so an inspection session has one explicit
lifetime without requiring the complete input to be retained in memory.

`src/vexterlib/inspection_sessions.nim` is the incremental container API. It
separates stable resource descriptors from payload materialization, exposes
independent child enumeration and load operations, applies depth/resource/
manifest/working-memory limits, and reports progress whose total is explicitly
unknown, growing, or final. ZIP/OpenRaster, ISO 9660, LHA, and ADF use indexed
random-access providers: opening validates only the carrier or manifest,
expanding reads one directory, and loading reads one member. Packed wrappers
defer their unpacking until their synthetic content root is expanded or loaded.
Callers own each loaded result and may discard it independently of the session.

The CLI uses a session walk for inspection. The Windows GUI retains the session
for the open document, adds descriptor children on demand, and performs expand
and load requests on a worker thread so message processing is not blocked.

`src/vexterlib/transformations/colour_cycle.nim` combines up to six effective
palette ranges with a still image or source animation timeline. It uses the
least common multiple of the source and range periods, emits only at actual
frame/range boundaries, and enforces the default 1,000-frame expansion guard.

`src/vexterlib/handler_registry.nim` is the authoritative registry of supported
input type identifiers. Each entry binds a stable identifier to its validation
and inspection handler kind. Registry parsing returns a checked, type-erased
`VextParsedContainer`; detected and forced formats retain that value so
inspection decodes the selected container without parsing the source again.
Detection results are required to resolve through the registry, and inspection
selects format-specific decoding by handler kind rather than repeating a
parallel type-identifier list.

`src/vexterlib/resource_tree.nim` defines `VextResourceTree` and
`VextResourceNode`. Nodes are reference objects and currently have the
`vrnkGroup`, `vrnkRaster`, `vrnkFont`, `vrnkText`, `vrnkAudio`, or
`vrnkOpaque` kind. `leafResources`
returns every
addressable non-group node, while `rasterResources` and `fontResources` return
their respective media nodes in depth-first tree order. Exact-path helpers are
available for both. Groups are structural. Opaque resources with explicitly
retained bytes are BIN-exportable; identification-only opaque nodes are not.

`src/vexterlib/detection.nim` contains evidence-based detection. Candidates
are ordered strongest-first. Structurally valid AMOS banks with exact magic
identifiers are `vdcCertain`; current ZX Spectrum detectors are `vdcProbable`.
Matching case-insensitive extensions add supporting evidence.

`src/vexterlib/containers/` contains source/container rules:

- `ansi_art.nim` validates presentation-affecting ANSI control streams and
  optional trailing SAUCE records and comment blocks;

- `amiga_workbench_icon.nim` validates classic big-endian Workbench
  DiskObjects, their serialized planar images, counted strings, and tool
  types; it also decodes NewIcons `IM1`/`IM2` tool-type imagery and appended
  OS 3.5 GlowIcons `FORM ICON` chunks;
- `amiga_adf.nim` validates standard DD/HD AmigaDOS floppy images and walks
  OFS/FFS directory, file-header, extension, and data-block structures;
- `amiga_dms.nim` validates DMS information/track CRCs and reconstructs
  NOCOMP, SIMPLE, HEAVY1, and HEAVY2 track streams for the ADF handler;
- `xpk_shri.nim` validates XPK master/chunk framing and checksums, reconstructs
  raw and stateful SHRI arithmetic/LZ chunks, and exposes recognized unpacked
  content through bounded recursive inspection;
- `powerpacker.nim` validates standalone PP11/PP20 headers and efficiency
  tables, decodes their backwards literal/LZ bitstream, and exposes recognized
  unpacked content through bounded recursive inspection;
- `doom_wad.nim` validates classic IWAD/PWAD headers, bounded ordered lump
  directories, PLAYPAL palettes, flat namespaces, and column/post patch
  graphics with transparent gaps and signed placement offsets. It also parses
  PNAMES and TEXTURE1/TEXTURE2 recipes and composites clipped transparent wall
  textures in declared patch order. Sound-card `DS*` lumps decode from their
  eight-byte headers and unsigned eight-bit mono samples into generic sounds;
- `zip_archive.nim` validates single-volume ZIP central/local records, expands
  stored and raw-DEFLATE members on demand, and retains physical member offsets
  needed by package-profile refiners;
- `iso9660.nim` validates ISO 9660 primary volume descriptors and directory
  records in cooked 2048-byte images and raw Mode 1/2352 tracks. File extents
  are extracted on demand so parsing does not duplicate an entire disc image;
- `openraster.nim` refines a parsed ZIP carrier through the baseline MIME and
  required-member rules, parses its layer-stack XML, and validates referenced
  PNG layers, canonical merged image, and thumbnail;
  stored and DEFLATE entries, checks CRC-32, and exposes a host-independent
  archive hierarchy;
- `lha_archive.nim` validates level-0/1 LHA member headers and checksums, expands
  stored LH0 and static-Huffman/LZ LH5 members, checks CRC-16, canonicalizes
  Amiga path separators, and exposes a host-independent archive hierarchy;
  structural detection remains available for unsupported member methods so
  frontends can report the specific codec limitation;
- `amiga_hunk_executable.nim` validates enough classic load-file Hunk framing
  to identify CODE, DATA, BSS, relocation, symbol, debug, END, and the supplied
  length-delimited overlay arrangement while retaining loadable bytes;
- `amiga_lha_sfx.nim` recognizes the supplied Amiga LHA self-extractor layout,
  separates its usage record and main appended archive, and routes both through
  the ordinary LHA parser and recursive inspection path;
- `pcx.nim` validates ZSoft PCX headers, dimensions, plane layouts, and row
  storage before retaining the encoded image source;
- `tga.nim` validates Truevision TGA headers, optional identification and
  colour-map fields, raw pixels, and complete RLE packet coverage;
- `bmp.nim` validates wrapped BMP files and standalone Windows or OS/2 DIBs,
  including palette, bitfield, compression, and pixel-data boundaries;
- `png_container.nim` validates PNG signatures, chunk framing/order, CRC-32,
  image properties, palettes, transparency, and concatenated IDAT data while
  retaining every known or unknown chunk for metadata;
- `jpeg.nim` validates JPEG marker framing, eight-bit DCT frame dimensions and
  component sampling, retains JFIF density information, and parses bounded
  little- or big-endian EXIF IFD0, photographic, GPS, interoperability, and
  thumbnail directories, including orientation and readable standard fields;
- `windows_icon.nim` validates ICO/CUR directories and bounded image entries,
  distinguishes embedded PNG, icon-style DIB, and unknown payloads, separates
  DIB XOR imagery from its doubled-height one-bit AND mask, and retains CUR
  hotspots plus both directory and payload dimensions;
- `qoi.nim` validates QOI headers, dimensions, channel and colour-space
  descriptors, chunk framing and pixel coverage, and the exact end marker;
- `koala_painter.nim` validates the 10,003-byte KoalaPainter payload and
  bounded component ranges while retaining its little-endian load address,
  bitmap, screen RAM, colour RAM, global background byte, and tolerated
  trailing data;
- `netpbm.nim` validates and extracts plain/raw PBM, PGM, and PPM plus PAM,
  including comments, multi-image raw streams, 16-bit big-endian samples,
  PAM headers, sample bounds, and exact raster sizes;
- `gif_container.nim` validates GIF87a/GIF89a logical screens, global/local
  colour tables, extensions, image descriptors, and LZW data sub-blocks;
- `flic.nim` validates 128-byte FLIC-family headers, main chunks, frame and
  prefix subchunks, declared frame counts, CEL registration metadata, and EGI
  Huffman code tables;
- `fzx.nim` validates signatureless FZX v1.0 metrics, relative character-table
  offsets, packed universal kern values, shifts and widths, terminal extent,
  row alignment, definition order, and the specified size limits;
- `bmfont.nim` decodes text, XML, and binary-v3 BMFont descriptors and
  validates their records, declared counts, page table, Unicode
  IDs, metrics, and atlas rectangles;
- `amiga_diskfont.nim` validates plain/tagged bitmap `.font` indexes and
  recognizes loadable size descriptors by DFH_ID, validates TextFont glyph
  tables and strike bounds, and retains ColorTextFont planes, plane-selection
  fields, and xRGB palettes;
- `amiga_iff.nim` validates generic IFF `FORM` lengths, chunk boundaries, and
  even-byte padding;
- `amiga_8svx.nim` interprets `FORM 8SVX` voice headers, channels, loop and
  playback metadata, and raw or Fibonacci-delta sample bodies;
- `amiga_16sv.nim` interprets the compatible `FORM 16SV` structure and its
  uncompressed signed 16-bit big-endian sample bodies;
- `wav.nim` validates RIFF/WAVE chunk framing and decodes 8-, 16-, 24-, and
  32-bit integer PCM into a generic sound;
- `amiga_acbm.nim` interprets `FORM ACBM` properties and extracts its
  plane-contiguous `ABIT` image source;
- `amiga_ilbm.nim` interprets `FORM ILBM` properties and extracts the image
  source while leaving raster decoding separate;
- `amiga_pbm.nim` provisionally interprets `FORM PBM ` as an eight-bit chunky
  indexed image using BMHD, CMAP, and BODY chunks;
- `amiga_anim.nim` parses nested ILBM frame forms, their ANHD/DLTA records,
  and DPAN logical frame-count and playback-rate metadata;
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

`src/vexterlib/resources/amiga_workbench_icon_image.nim` renders the normal
and selected classic planar images using the initial Workbench 1.3
blue/white/black/orange interpretation and converts decoded NewIcons and
GlowIcons chunky images into indexed rasters with transparency.

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

`src/vexterlib/resources/tga_image.nim` expands raw or cross-scanline TGA RLE
packets, normalizes bottom-origin storage, and renders colour-mapped, grayscale,
and 16/24/32-bit true-colour sources. Palette origins are normalized into the
generic indexed raster, and specified pixel or palette attributes populate
per-pixel alpha.

`src/vexterlib/resources/bmp_image.nim` renders packed indexed BMP/DIB rows,
RLE4/RLE8 streams, BGR true-colour rows, and normalized 16/32-bit colour
bitfields. It handles bottom-up and uncompressed top-down storage.

`src/vexterlib/resources/png_image.nim` inflates and unfilters every PNG
scanline, expands all standard colour types and legal bit depths, applies
palette or `tRNS` alpha, and reconstructs Adam7 passes. APNG and unknown chunks
are distinguished: valid APNG frame streams are decomposed and composited into
a true-colour animation, while unknown chunks remain metadata-only.

`src/vexterlib/resources/jpeg_image.nim` natively decodes eight-bit baseline
and extended-sequential Huffman scans, including quantization and Huffman
tables, restart intervals, grayscale and YCbCr component sampling, and inverse
DCT reconstruction. It applies EXIF orientations 1 through 8 to the decoded
image before preview or export. No JPEG C library or runtime dependency is
linked into Vexter.

`src/vexterlib/resources/qoi_image.nim` decodes every QOI RGB, RGBA, INDEX,
DIFF, LUMA, and RUN operation into a true-colour image with optional alpha,
including the specified modulo-256 channel arithmetic and 64-entry colour
index.

`src/vexterlib/resources/koala_painter_image.nim` expands the C64 multicolour
bitmap's four two-bit selectors per attribute cell into doubled 320×200 indexed
pixels. It uses Pepto's Colodore RGB values, supplied through the Lospec
Paint.NET palette and reordered into VIC-II hardware colour-index order.

`src/vexterlib/resources/netpbm_image.nim` maps PBM and defined visual PAM
tuple types to monochrome, grayscale, RGB, or alpha-bearing rasters. Samples
with arbitrary legal maxvals are normalized to eight-bit Vext components;
extra PAM planes are retained structurally and ignored for defined tuple types.

`src/vexterlib/resources/gif_image.nim` expands GIF LZW codes, restores
interlaced rows, applies global/local palettes and binary transparency, and
composites frame rectangles using GIF disposal rules into full indexed frames.

`src/vexterlib/resources/flic_animation.nim` reconstructs FLI/FLC-family frame
buffers and changing palettes from copy, black, BYTE_RUN, DELTA_FLI,
DELTA_FLC, and DTA copy/RLE/delta chunks. It renders eight-bit sources as
indexed animations and 15/16/24-bit FLX/FLH/FLT sources as true-colour
animations, applies CEL transparent indices, omits ring frames, and converts
FLI tick timing or FLC/Pro Motion millisecond timing to frame durations.
AF30 Huffman/BWT blocks and AF31 frame shifts are also decoded from the
separately supplied EGI compression specification. One-bit AF44 DTA remains
blocked on its delegated pixel-packing specification. EGI masks,
segments/overlays, audio, and ancillary metadata are described but still need
resource-model decisions, implementation, and authentic controls. The detailed
research and fixture checklist is maintained under “Outstanding FLIC work”
in `docs/formats.md`.

`src/vexterlib/resources/fzx_font.nim` expands one- or two-byte MSB-first FZX
rows into monochrome coverage glyphs. FZX shift becomes vertical placement,
its universal per-character kern becomes a negative bearing and reduced
advance, and tracking contributes to advance. Because FZX contains byte
positions rather than a Unicode character map, printable positions 32–127 use
the explicit project default while every position remains preserved as a glyph
source index.

`src/vexterlib/resources/bmfont_font.nim` resolves static PNG atlas pages and
crops BMFont rectangles into generic glyphs, preserving offsets, advances,
baseline, mappings, and kerning. White-alpha and selected mask channels become
monochrome coverage while coloured glyphs retain RGB and alpha. Unicode
descriptors map scalar IDs directly; non-Unicode descriptors use only the
printable-ASCII default and retain all other IDs as source positions. Style,
padding, spacing, outline, charset, packed, and channel-role fields remain
inspection metadata.

`src/vexterlib/resources/amiga_diskfont_font.nim` extracts potentially
unaligned strike glyphs, preserves baseline, proportional spacing, and signed
left bearings, retains the unmapped default glyph, emits monochrome coverage,
and combines ColorFont planes into transparent indexed glyphs.

`src/vexterlib/resources/amiga_ilbm_image.nim` decodes uncompressed or
ByteRun1-compressed planar data: scanline-interleaved planes from ILBM `BODY`
chunks and whole sequential planes from ACBM `ABIT` chunks. It produces
indexed images for one through eight ordinary planes and six-plane EHB, and
true-colour images for HAM/HAM8. Legacy CMAPs whose component low nibbles are
uniformly zero are expanded by nibble replication. All defined BMHD masking
modes populate the raster alpha channel: explicit mask planes, transparent
palette indices, and boundary-connected lasso transparency. ByteRun1 mask rows
are decoded independently from their associated colour-plane rows. A legacy
writer error that includes one zero IFF alignment byte in an odd-sized
ByteRun1 BODY's declared payload is accepted; other trailing BODY data remains
an error.

`src/vexterlib/resources/amiga_pbm_image.nim` decodes provisional IFF PBM
chunky rows, with word-aligned raw or row-bounded ByteRun1 storage, into an
indexed raster. Transparent-colour masking is supported. A temporary external
compatibility corpus confirms eight-bit BMHD depth and ByteRun1 decoding for
even-width, unmasked images, but committed fixtures remain pending and the raw,
odd-width, and transparency assumptions are still synthetic-only.

`src/vexterlib/resources/amiga_anim_image.nim` reconstructs retained planar
buffers with ANIM delta methods 1 through 5, 7, and 8, including interleave references
and method-5 XOR used by Deluxe Paint animation brushes. It then renders each
frame through the same indexed/EHB/HAM ILBM path as still images. Method 1
supports plane-masked rectangular BODY XOR, while method 4 supports all six
documented option bits. Methods 6 and 74 are identified but report explicit
unsupported-method errors.

ANHD relative times use 50 Hz for explicit PAL CAMG monitor IDs and 60 Hz for
explicit NTSC or unspecified monitor IDs.

Method 3's negative-run cursor behavior is verified across every shared frame
of two VideoScape originals and their independently resaved Deluxe Paint
method-5 controls; the controls' extra bottom-row padding is not delta-addressed.
Method 7 consumes complete encoded short or long units and clips a padded final
unit when the ILBM row width is not longword-aligned.

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

`src/vexterlib/archetypes/font.nim` defines `VextBitmapFont`. Glyph identity is
separate from Unicode mappings, allowing aliases and custom characters without
duplicating imagery. It retains mono coverage, indexed and true-colour glyphs,
two-axis advances and kerning, bearings, baseline and line metrics,
substitutions, ligatures, and a fallback. Sources with no explicit mapping may
deliberately request the conventional 32–127 mapping; it is not imposed on
formats which provide their own mapping.

`src/vexterlib/resources/font_preview.nim` performs longest-match ligature and
substitution shaping, metric-aware placement, kerning, and width wrapping into
a true-colour alpha raster. It also lays every stored glyph, including unmapped
ones, into a selectable grid with baseline/ascent/descent guides. The GUI offers
an editable wrapped sample and a glyph-grid mode with source index, Unicode
mapping, bitmap dimensions, bearings, advances, and feature counts. Both views
composite transparency over a checker pattern.

`src/vexterlib/exporters/bmfont.nim` projects the representable font subset to
an AngelCode BMFont text descriptor and deterministic, padded PNG pages up to
1024 pixels. Mono coverage becomes white RGB with alpha; coloured glyphs retain
RGBA. The archetype continues to retain vertical kerning/advance,
substitutions, ligatures, and richer line metrics which BMFont cannot express.
Outlined packed-channel imports become true-colour glyphs using the AngelCode
sample shader's half-range outline/interior rule; ordinary masks remain
recolourable monochrome coverage.

`src/vexterlib/exporters/metadata_json.nim` emits the versioned
`vexter.resource-metadata.v1` schema for groups and every leaf archetype. It
retains ordered typed metadata and structural values, including font features
which BMFont cannot serialize, without embedding bulk media buffers.

`src/vexterlib/exporters/html_report.nim` builds a standalone UTF-8 report for
any resource. It embeds PNG/APNG previews, font sample and grid renderings, WAV
audio, escaped text or group summaries alongside the metadata JSON. All CSS and
media use data URLs, so the artifact has no runtime or network dependency.

`src/vexterlib/exporters/` consumes those contracts and
has no ZX Spectrum-specific knowledge. `src/vexterlib/artifacts.nim` defines
the in-memory output contract; callers, not exporters, write files.
Opaque resource nodes explicitly distinguish retained raw bytes from
identification-only leaves. Retained bytes export unchanged as
`application/octet-stream` BIN artifacts; the explicit availability flag also
allows genuine empty files without making metadata-only nodes exportable.
`src/vexterlib/metadata.nim` defines typed key/value metadata currently used
for signed AMOS hotspot coordinates.

`src/vexterlib/archetypes/audio.nim` defines signed PCM samples,
bit-depth-aware channel-major buffers, playback-rate-bearing sounds, and
sampled instruments with one-shot/repeat regions, pitch-cycle, volume, and
panning information. `src/vexterlib/exporters/wav.nim` serializes sounds as
uncompressed 8-, 16-, 24-, or 32-bit integer PCM with interleaved channels.
Audio resource nodes distinguish a plain `VextSound` from a
`VextSampledInstrument`; `audioSound` supplies the playable sound uniformly
without manufacturing instrument properties for ordinary audio files.

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
image.openraster
openraster.image
openraster.thumbnail
openraster.stack
openraster.layer
archive.lha
archive.lha-directory
archive.lha-file
amiga.hunk-executable
amiga.hunk-code
amiga.hunk-data
amiga.hunk-bss
amiga.hunk-overlay
amiga.lha-sfx
pcx
pcx.image
windows.bmp
windows.dib
windows.bitmap
png
png.image
qoi
qoi.image
netpbm
netpbm.image
gif
gif.image
wav
wav.sound
doom.wad
doom.palette
doom.flat
doom.patch
doom.texture-directory
doom.wall-texture
doom.sound
doom.lump
amiga.iff
amiga.acbm
amiga.pbm
amiga.pbm-image
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

IFF 8SVX forms expose a sampled instrument at `/instrument`. Its BODY is
decoded to signed eight-bit PCM, split from the format's channel-major stereo
layout, and paired with the VHDR playback rate, one-shot/repeat regions,
samples-per-high-cycle, and 16.16 volume. CHAN left-only and right-only forms
also retain their implied pan. Raw and Fibonacci-delta compression are
supported; multi-octave bodies are rejected explicitly until their octave
layout is implemented. WAV is its natural export format; WAV carries the PCM
and playback rate but not the instrument's loop, volume, or pan metadata.

IFF 16SV forms expose the same sampled-instrument path and metadata shape,
with a 16-bit buffer decoded from big-endian signed PCM words. The supplied
reference documentation defines 16SV as the same structure as 8SVX except for
the BODY sample width. Uncompressed mono and structurally valid CHAN
left/right/stereo layouts are supported. Compression and multi-octave data are
rejected because the supplied reference implementation does not implement
them. WAV is the natural export and writes the decoded samples as little-endian
16-bit PCM.

WAV files expose a plain `VextSound` at `/audio`. Import validates exact RIFF
lengths, chunk framing and odd-byte padding, a single `fmt ` and `data` chunk,
PCM format consistency, complete sample frames, and integer PCM widths of 8,
16, 24, or 32 bits. Chunks may appear in either order; unknown chunks are
retained and projected as numbered type/size metadata. Channels are converted
from interleaved WAV storage into Vext's channel-major signed samples, including
the unsigned-to-signed conversion required for eight-bit PCM. Floating point,
compressed codecs, RF64, and WAVE_FORMAT_EXTENSIBLE remain unsupported. WAV
re-export uses the ordinary generic sound exporter.

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

DMS archives expose their reconstructed AmigaDOS volume at `/disk` and use the
ADF traversal above. Information headers, track headers, and packed data are
CRC-checked; unpacked tracks are checksum-checked. NOCOMP, SIMPLE/RLE, HEAVY1,
and HEAVY2 are implemented, including persistent dictionaries, Huffman trees,
distances, and optional post-decompression RLE across track boundaries. QUICK,
MEDIUM, DEEP, encryption, and compression identifiers 7 through 9 remain
inspectable as packed `/tracks` resources but are not reconstructed. The
public-domain xDMS checkout is the attributed reference for CRC, RLE, HEAVY,
and track-state behavior; its provenance and upstream acknowledgements are in
`THIRD_PARTY.md`.

Some authentic OFS game disks place their own directory header block in the
first hash slot. ADF traversal recognizes and skips this self-entry without
following its parent-level collision link, while references to other visited
directory blocks remain cycle errors.

XPK wrappers using the SHRI compressor expose their recursively inspected
payload at `/content`. Master and chunk-header XOR checksums, alternating-byte
payload checksums, short and long chunk headers, four-byte chunk alignment,
raw chunks, and stateful SHRI continuation chunks are validated. Passwords and
compressors other than SHRI are unsupported. The BSD-licensed Ancient Format
Decompressor checkout is the attributed behavioral reference; provenance is
recorded in `THIRD_PARTY.md`.

Standalone PP11 and PP20 PowerPacker streams expose their recursively
inspected payload at `/content`. The legal efficiency tables, 24-bit expanded
size, initial bit shift, backwards bitstream, literal runs, and LZ matches are
validated. The BSD-licensed Ancient Format Decompressor checkout is the
attributed behavioral reference; provenance is recorded in `THIRD_PARTY.md`.

ZIP archives expose `/archive`. Entry paths are interpreted as logical archive
paths rather than host paths: slash and backslash separators are canonicalized,
absolute, empty, dot, parent, duplicate, and file/directory-conflicting paths
are rejected, and complete entry names are capped at 255 Unicode characters.
Legacy names use ZIP's CP437 mapping and names marked UTF-8 are validated.
Stored and DEFLATE entries are supported with lazy size and CRC-32 checks. Encrypted,
ZIP64, unsupported-compression, and classic multi-volume archives are rejected.
Recognized files open recursively on first GUI selection using the same
eight-layer bound and isolated warning behavior as ISO files. Bulk export applies conservative cross-platform
normalization to every resource-path segment and gives normalized collisions
deterministic `-2`, `-3`, and subsequent suffixes.

PCX images expose `/image`. One-, two-, and four-bit samples across up to four
planes use the 16-colour header palette; eight-bit single-plane images use the
mandatory trailing 256-colour palette. Eight-bit three-plane images produce a
true-colour raster. Scanline padding is excluded from output pixels and RLE
runs are bounded to individual scanlines. RGB plane order is the default;
`--pcx-channel-order bgr` selects files written in the alternate order.

TGA images expose `/image`. Raw and RLE colour-mapped, true-colour, and
grayscale types are supported. Colour-map indices may be eight or sixteen bits;
map entries and true-colour pixels support the documented 16/24/32-bit layouts.
Bottom-left and top-left origins are normalized to top-down rasters. Reserved,
two-way/four-way interleaved, Huffman/delta, and four-pass variants are rejected.

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
Every chunk's type and size is retained in inspection metadata. APNG frame
rectangles are decoded through the same PNG pipeline, composited with their
source/over blend and none/background/previous disposal operations, and exposed
as a full-frame true-colour animation. Unknown standard/private chunks remain
reported metadata and do not cause import failure.

JPEG files expose `/image` as a true-colour raster and naturally export as PNG.
Detection is structural; `.jpg`, `.jpeg`, and `.jpe` are supporting evidence
only. JFIF fields and EXIF presence, validity, orientation, and parser errors
are inspection metadata. A malformed EXIF block does not invalidate otherwise
valid JPEG image data.

GIF87a and GIF89a files expose `/image` as a `VextIndexedAnimation`, including
single-image files. LZW, interlacing, global/local colour tables, transparency,
delays, and none/background/previous disposal are decoded into full-canvas
frames. Retaining a one-frame animation deliberately makes GIF the natural
output for static GIF input. GIF export uses per-frame local colour tables and
binary transparency, so palette changes are supported. Partial alpha or a
composited frame exceeding 256 colours instead requires APNG.

FLI, FLC, CEL, FLH, FLT, and both documented FLX variants expose
`/animation`. Standard palette/copy/black/BYTE_RUN/DELTA_FLI/DELTA_FLC chunks
and DTA 15/16/24-bit copy, RLE, and delta chunks are decoded. CEL prefix origin
and transparent-index data are retained. EGI Huffman/BWT blocks and frame
shifts are decoded; one-bit DTA images remain pending their separately
referenced pixel-packing specification.

Generic `AmBk` containers continue to expose unknown bank types as opaque bank
data. A `Pac.Pic.` bank with its screen palette instead exposes an indexed
`amos.packed-picture` raster at `/picture`; the same bank nested in an `AmBs`
or AMOS program uses its numbered `/banks/N` resource path.

ANIM containers expose `/animation`. GIF-compatible indexed animations default
to GIF, while HAM animations produce
`VextTrueColourAnimation` and default to APNG. Indexed images and animations
can also be explicitly exported as APNG; frames are expanded through their own
palettes, so palette changes and per-pixel alpha are preserved. When an
indexed animation cannot be represented by GIF because of partial alpha or
palette capacity, APNG becomes its natural default. Delta-compressed first frames remain
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
GIF-compatible indexed animation, APNG for an indexed animation with partial
alpha or another GIF-incompatible property, and PNG for an indexed image. Explicit PNG export of an
animation uses its natural first frame; explicit APNG is available for every
indexed raster that can be sent to GIF.

## Tests and fixtures

The routine suites are:

- `tests/test_amiga_adf.nim`: synthetic FFS directory traversal, OFS and FFS
  file reconstruction, nested format decoding, and structural corruption;
- `tests/test_zip_archive.nim`: stored/DEFLATE expansion, hierarchy and nested
  decoding, per-member decoder-failure isolation, unsafe/duplicate/overlong
  path rejection, and portable export-name normalization;
- `tests/test_openraster.nim`: synthetic ZIP-profile refinement, required MIME
  placement and members, layer-stack metadata and raster exposure, derivation
  reporting, and forced generic-carrier inspection;
- `tests/test_lha_archive.nim`: level-0 framing, LH0 storage, authentic Aminet
  LH5 expansion, checksums, hierarchy and recursive decoding, path safety, and
  malformed or unsupported input;
- `tests/test_amiga_hunk.nim`: minimal load-file Hunk framing, retained code,
  generic executable detection, appended usage/main LHA recognition, SFX
  precedence, and normal archive resource routing;
- `tests/test_amiga_diskfont.nim`: synthetic plain/tagged indexes, safe
  companion resolution, TextFont and ColorTextFont descriptors, proportional
  metrics, default glyphs, planes and palettes, detection, inspection, and
  BMFont export;
- `tests/test_bmfont_import.nim`: text-descriptor round trips, coloured and
  monochrome glyph recovery, multi-page resolution, XML/binary identification,
  unsafe paths, counts, page references, and rectangle validation;
- `tests/test_xpk_shri.nim`: XPK framing, raw chunks, checksum failures,
  recursive inspection, and byte-identical SHRI reconstruction of Fishdemo;
- `tests/test_powerpacker.nim`: synthetic PP20 reconstruction, malformed
  headers, recursive inspection, and authentic Lemmings ANIM reconstruction;
- `tests/test_pcx.nim`: planar/header palettes, 256-colour trailing palettes,
  true-colour RGB/BGR order, row padding, RLE, and malformed input;
- `tests/test_tga.nim`: colour-map origins, identification fields, raw and RLE
  packets, row orientation, grayscale, 16/24/32-bit colour and alpha, and
  malformed or unsupported layouts;
- `tests/test_bmp.nim`: Windows and OS/2 DIBs, wrapped BMP offsets, indexed and
  true-colour rows, top-down orientation, bitfields, RLE4/RLE8, and failures;
- `tests/test_png.nim`: RGBA and indexed transparency, grayscale and 16-bit
  samples, filters, Adam7 reconstruction, APNG decomposition/composition and
  export round trips, private chunk tolerance, metadata retention, CRCs,
  malformed required chunks, and every existing independently encoded PNG
  control;
- `tests/test_jpeg.nim`: self-contained baseline Huffman decoding, structural
  detection, PNG routing, both EXIF TIFF byte orders, all eight orientation
  mappings, photographic sub-IFD values, medium-image component-plane scaling,
  malformed EXIF isolation, malformed JPEG framing, and explicit progressive
  decoding rejection; separately supplied IJG and camera JPEGs are also used
  as uncommitted compatibility controls;
- `tests/test_qoi.nim`: every QOI opcode, colour-index hashing, runs,
  modulo-256 channel differences, alpha, metadata, detection, PNG routing,
  declared pixel coverage, exact termination, and malformed input;
- `tests/test_koala_painter.nim`: fixed-layout validation, extension and size
  confidence, noncanonical load addresses, tolerated trailing data,
  multicolour selector ordering, doubled pixels, and the Colodore VIC-II
  palette mapping;
- `tests/test_netpbm.nim`: P1–P7 parsing, comments, packed PBM rows, plain
  samples, 16-bit raw samples, exact binary delimiters, concatenated images,
  PAM visual tuple types and alpha, extra planes, and malformed input;
- `tests/test_gif.nim`: GIF87a/GIF89a, LZW, interlacing, global/local palettes,
  transparency, changing-palette export, static GIF routing, corruption, and
  all existing independently encoded GIF controls;
- `tests/test_flic.nim`: FLI/FLC palettes, copy/black/full-frame and both delta
  RLE schemes, ring frames, timing, CEL metadata/transparency, DTA true colour,
  both FLX packed layouts, EGI Huffman/BWT expansion, frame shifting across
  indexed/16/24-bit buffers, extended-type identification, and malformed input;
- `tests/test_amiga_iff_ilbm.nim`: FORM/chunk validation, ILBM planar and
  ByteRun1 decoding, one-through-eight-plane indexed images, legacy palette
  expansion, EHB, focused HAM6/HAM8 cases, and authentic Deluxe Paint HAM6/HAM8
  controls;
- `tests/test_amiga_8svx.nim`: raw mono/stereo samples, sampled-instrument
  metadata, Fibonacci-delta expansion, detection, WAV routing, and malformed
  input;
- `tests/test_amiga_16sv.nim`: synthetic big-endian signed samples, stereo
  layout, and unsupported variants;
- `tests/test_wav.nim`: synthetic RIFF/WAVE import across all supported integer
  widths, channel interleaving, chunk ordering/padding/metadata, plain-sound
  routing, export, and structural validation. Authentic compatibility fixtures
  remain pending user-supplied samples;
- `tests/test_doom_wad.nim`: synthetic IWAD/PWAD directory ordering and bounds,
  duplicate names, PLAYPAL palettes, flat namespaces, patch posts,
  transparency, signed offsets, PNAMES resolution, TEXTURE1/TEXTURE2
  composition and clipping, retained recipes, DS sound decoding and WAV export,
  malformed resources, and PNG eligibility;
- `tests/test_amiga_acbm.nim`: ACBM detection, plane-contiguous raw and
  ByteRun1 ABIT decoding, and structural failure modes;
- `tests/test_amiga_pbm.nim`: provisional packed eight-bit rows, word
  alignment, raw and ByteRun1 storage, palettes, transparent indices, and
  explicit header/masking failures;
- `tests/test_amiga_anim.nim`: nested ANIM structure, methods 1–5/7/8, animation
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

`vx4.nimble` builds the Linux CLI before running these suites. Authentic and
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
- Keep `docs/outstanding.md` synchronized when a known implementation or
  recognized-format gap is added, resolved, or deliberately declared out of
  scope; do not use it as a roadmap for formats Vexter does not yet recognize.
- Preserve stable type identifiers and canonical resource paths unless a
  deliberate compatibility change is agreed.
- Prefer generic resource/archetype operations over format-specific branches
  in frontends and exporters.
- Resource nodes carry already-decoded archetype values, inline opaque bytes,
  or lazy shared-source payload recipes. ISO and ZIP use lazy payloads;
  alternate representations and true lazy directory enumeration are not yet
  implemented. The overall loading policy is intentionally unresolved: large
  nested collections can make eager probing, first-selection decoding, memory
  retention, and bulk operations behave poorly. `docs/outstanding.md` records
  the deferred design questions and a motivating pathological ZIP case.
- Single-resource compound export requires a directory destination at the CLI
  boundary. Bulk collision resolution renames compound artifact stems as a
  unit so descriptor references remain synchronized with companion files.
- Recursive decoding is shared by ADF, ZIP, LHA, PowerPacker, and XPK through the
  registered detection, parsed-container, and inspection path, with a fixed
  eight-layer bound.
- ISO 9660 tree construction uses indexed directory lookup. File nodes retain
  logical references into one shared source image and materialize bytes only
  for bounded nested inspection, GUI selection, or export. Filesystems above
  512 entries are presented structurally without eager nested decoding;
  selecting a lazy file probes it once and inserts successfully decoded
  descendants beneath the existing tree node. Smaller discs retain the
  512-file/128 MiB eager probing bounds.
