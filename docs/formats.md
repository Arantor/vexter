# Format support

This document records formats implemented in the current clean-room Vexter
repository and historical coverage that may inform future work. Format work is
undertaken only when explicitly planned; the historical list is not an active
implementation schedule.

## Current CLI subset

The currently implemented formats use this subset of the intended CLI:

```text
vexter inspect [--json] [--all-candidates] [--ignore-warnings]
               [--input-format FORMAT] [--pcx-channel-order rgb|bgr] INPUT

vexter export [--format png|gif|apng|gif-cycled|apng-cycled|bmfont|metadata-json|txt|wav|bin]
              [--resource PATH] [--allow-large-animation]
              [--input-format FORMAT] [-o OUTPUT] [--force]
              [--ignore-warnings] [--pcx-channel-order rgb|bgr] INPUT
```

## Metadata JSON export

Every resource, including groups and opaque identification-only resources, can
be exported with `--format metadata-json`. The stable
`vexter.resource-metadata.v1` document records the resource path, type and
kind, ordered typed metadata, direct child paths, and archetype-specific
structure. Font documents include glyph identity and metrics, mappings,
two-axis advances and kerning, fallback behavior, substitutions, and ligatures;
bitmap pixels remain in the natural visual export. Raster documents retain
dimensions, animation timing and colour-cycle declarations, while audio
documents retain buffer and sampled-instrument metrics.

Metadata JSON is supplementary and never replaces a resource's natural default
export. It is also available to `export-all`, where groups and leaves receive
separate JSON artifacts.

## Raw binary export

Opaque resources that retain source bytes can be exported with `--format bin`;
BIN is also their natural format when `--format` is omitted. The artifact uses
the `application/octet-stream` media type and a `.bin` suggested extension, and
its data is byte-identical to the resource bytes. Availability is explicit, so
zero-length files remain exportable while identification-only resources such
as unresolved filesystem links do not produce misleading empty artifacts.

## Bitmap-font export

Bitmap-font resources naturally export with `--format bmfont`. This produces a
UTF-8 BMFont text descriptor plus one or more PNG atlas pages; CLI export
therefore requires a directory destination. Atlas pages are deterministic, padded,
power-of-two in height, and at most 1024 pixels in either dimension. Mono glyph
coverage is written as white with alpha for downstream recolouring; indexed and
true-colour glyphs retain their colour and transparency.

Unicode mappings, bearings, horizontal advances, baseline and line height, and
horizontal kerning are projected into BMFont. Glyph identity remains separate
from character mappings in memory, allowing aliases without duplicate atlas
images. Vertical advances/kerning, ascent, descent, leading, substitutions, and
ligatures remain in the generic archetype even though BMFont cannot serialize
them. Export reports only losses present in the source font and remains
available after those advisory warnings; compatible fonts export without
warnings. The GUI shapes substitutions and longest-match ligatures, wraps its sample
to the preview width, and displays transparent text over a checker pattern. Its
font inspector switches between editable sample text and a complete glyph grid.
The grid retains unmapped/default/custom glyphs, highlights a selected glyph,
draws baseline/ascent/descent guides, and reports source index, mappings,
dimensions, bearings, advances, and kerning/substitution/ligature counts.

## BMFont import

Container type identifier: `bitmap-font.bmfont`

Resource type identifier: `bitmap-font.bmfont-font`

AngelCode BMFont text descriptors are parsed as multi-file containers. Vexter
validates the `info`, `common`, `page`, `chars`, `char`, `kernings`, and
`kerning` records; page IDs, Unicode scalar IDs, atlas bounds and numeric
fields must agree. Character and kerning counts are retained and discrepancies
produce structured warnings because real generators can emit stale counts.
Quoted page names go through the
same safe companion resolver as Amiga diskfont indexes, and every companion
must be a static PNG matching the common atlas dimensions. Multiple pages are
supported.

Character rectangles are cropped into independent glyphs. BMFont `xoffset`,
`yoffset`, `xadvance`, baseline, line height, Unicode mappings, and horizontal
kerning become generic font values. White RGB with alpha and explicitly
selected alpha/red/green/blue mask channels become recolourable monochrome
coverage; genuinely coloured rectangles remain true-colour glyphs with alpha.
For an outlined single-channel glyph, the AngelCode packed threshold separates
the dark antialiased outline from the white antialiased interior and produces a
true-colour glyph. This follows the behavior demonstrated by the supplied
AngelCode sample `font.fx` shader.
The resulting font is exposed at `/font` and naturally exports to BMFont again.
The `info` style, smoothing, antialiasing, stretch, padding, spacing, outline,
charset and Unicode fields are retained alongside the `common` packed flag and
four channel-role values. When `unicode=1`, valid character IDs become Unicode
mappings. Otherwise only printable ASCII positions 32–127 receive the project
default identity mapping; every other ID remains available as a glyph source
index without guessing the declared legacy charset.
BMFont baselines beyond the declared line height are accepted; the original
values remain metadata and the generic line box expands to contain the baseline.
Non-semantic generator-specific `letter=` annotations are ignored, including
unescaped quote and backslash glyph annotations.

Binary `BMF` version 3 descriptors decode the information, common, page,
character, and optional kerning blocks. Block lengths, version, page count,
Unicode scalar IDs, signed metrics, atlas bounds, and record sizes are checked
before the same page and glyph conversion used by the text form. XML
descriptors map their equivalent elements and attributes into that same
validated representation, including declared counts and optional kerning.

The temporarily supplied `bmfonts/` controls are from the AngelCode Bitmap
Font Generator sample at <https://www.angelcode.com/dev/bmfonts/>. They exercise
text and binary version 3 descriptors, Unicode glyphs, signed metrics, kerning,
and packed per-glyph RGBA channel selection. They are compatibility evidence
only and are not copied into the routine fixtures; synthetic tests cover the
binary and XML structures.

## FZX bitmap fonts

Container type identifier: `zx-spectrum.fzx-font`

Resource type identifier: `zx-spectrum.fzx-bitmap-font`

FZX has no magic signature. Vexter validates its positive baseline spacing,
last-character range, complete three-byte character table, relative 14-bit
definition offsets, packed two-bit kern values, terminal offset, monotonically
ordered bounded bitmap definitions, one- or two-byte row alignment, and the
specified 16-pixel width and 192-pixel height limits. A structurally valid font
with a `.fzx` extension is **probable**; without the extension it is
**possible**.

The font is exposed at `/font` as `VextBitmapFont`. Character definitions use
MSB-first monochrome coverage. The header height becomes line height and the
inferred baseline; shift becomes vertical glyph placement. A character's
universal kern becomes a negative horizontal bearing and reduces its advance,
while header tracking is added to the advance. Empty definitions such as SPACE
retain their declared width and advance without manufacturing bitmap rows.

FZX records byte positions 32 through `lastchar`, not a Unicode character map.
Vexter applies the agreed default identity mapping only to printable positions
32–127. Every definition, including positions 128–255 and custom/remapped fonts,
retains its original position as `glyph.sourceIndex`; unknown encodings are not
invented as Unicode mappings. Inspection reports height, tracking, range and
mapping counts, blank and kerned character counts, and maximum stored glyph
dimensions. BMFont is the natural export.

Implementation follows the developer-supplied unpacked `FZX_Standard.zip`
distribution acquired from Spectrum Computing on 22 August 2026. Its `FZX.txt`
is the FZX v1.0 specification and copyright/open-standard notice by Andrew S. Owen
(2013). All 41 packaged fonts were checked as temporary structural and decoding
controls during implementation; they are not redistributed with Vexter.
Synthetic tests retain the established offset, metric, kern, shift, blank-glyph,
and one-/two-byte row behavior. `THIRD_PARTY.md` records provenance and selected
hashes. The supplied assembly example was not used as implementation source.

## Amiga bitmap diskfonts and ColorFonts

Container type identifier: `amiga.bitmap-diskfont`

Resource type identifier: `amiga.bitmap-diskfont-font`

Vexter recognizes `FCH_ID` and tagged `TFCH_ID` `.font` indexes as multi-file
containers. Each index entry retains its relative filename, intended height,
style, flags, and raw tag pairs. Safe relative paths are offered to a
frontend-owned companion resolver. Companions that exist and validate against
the indexed height and ColorFont kind become `/font/<height>` children;
unavailable optional sizes are simply retained as index metadata. Absolute,
volume-qualified, empty-segment, and traversal paths are never resolved.
Case-insensitive path fallback gives the CLI Amiga-like filename behavior on
case-sensitive hosts. Compugraphic `0x0f03` indexes remain excluded.
Amiga backslash path separators are normalized for companion lookup while the
original index filename remains visible as metadata. Tagged `TA_DeviceDPI`
values are exposed as separate horizontal and vertical DPI metadata.

An individual bitmap size descriptor is also recognized as a loadable Amiga
Hunk containing `DFH_ID`. Vexter validates the serialized `DiskFontHeader` and
`TextFont`, strike dimensions, character-location table, optional signed
spacing and per-character kerning tables, and every referenced bitmap plane.
The descriptor is preferred over the generic Hunk candidate and exposes a
font at `/font`.

Printable byte positions 32–127 receive the project's default identity Unicode
mapping. Every other position is retained as a source index without inventing
an encoding. The additional Amiga default glyph is retained but left unmapped.
Baseline, proportional advances, signed left bearings, bold-smear, style and
flag fields, modulo, range, and revision are retained as values or metadata.
Monochrome strikes become recolourable white-alpha glyphs.

`FSF_COLORFONT` descriptors additionally decode the `ColorTextFont` extension,
one through eight bitplanes, `PlanePick` and `PlaneOnOff`, foreground/low/high
colour metadata, and designer-supplied xRGB palettes. Palette index zero is
transparent in extracted glyphs; other source colours remain indexed and
opaque. BMFont text plus PNG is the natural export for both font kinds.

Implementation follows the developer-supplied AmigaOS documentation excerpt
acquired on 22 August 2026. All 117 bitmap size descriptors in the temporarily
supplied Amiga `Fonts` folder decoded (102 monochrome and 15 ColorFonts). Agfa
Compugraphic `.otag` material was ignored. The collection is not redistributed;
synthetic tests cover the serialized structures and decoding rules.

## Amiga ADF filesystems

Container type identifier: `amiga.adf`

ADF files are sector-for-sector images of Amiga floppy disks. Vexter supports
the standard 901,120-byte DD and 1,802,240-byte HD geometries with 512-byte
sectors. Detection requires a `DOS` boot signature with a defined filesystem
flag and a structurally valid, checksummed root block at the physical midpoint;
the case-insensitive `.adf` suffix supplies additional evidence but is not
required.

OFS and FFS filesystems are supported, including their international and
directory-cache flag variants. Directories are enumerated through all 72 root
or directory hash buckets and their collision chains. Files are reconstructed
from reverse-ordered data pointers and chained extension blocks. FFS sectors
contain 512 raw data bytes; OFS data headers and checksums are validated and
removed from their 488-byte payloads. Block bounds, metadata checksums, and
directory/data/extension cycles are rejected.

The volume appears as `/disk`. Directories become nested
`amiga.adf-directory` groups. Unknown files become `amiga.adf-file` opaque
nodes whose exact bytes remain available through the library. When a file is
recognized as another supported format, it becomes a group and that format's
normal resource paths are rebased below it. For example, a Spectrum screen
named `display.scr` appears as `/disk/display.scr/screen`. Nested inspection is
limited to eight container layers. AmigaDOS hard and soft links are currently
identified as `amiga.adf-link` leaves but are not followed. If a recognized
contained file is structurally valid but its resource decoding fails, the
error includes that file's `/disk/...` path and preserves the original decoder
message. `--ignore-warnings` instead retains the child as an opaque file and
continues inspecting its siblings. Human inspection prints collected warnings;
JSON inspection returns their `path`, `format`, and `message` fields.
Opaque files with retained contents can be selected with `export --resource`;
they default to byte-identical `application/octet-stream` output with a `.bin`
extension. Links remain identification-only and are not exportable.

Tests build compact logical filesystems within standard-size synthetic DD
images. They cover FFS subdirectories, OFS header removal, exact file bytes,
nested Spectrum decoding, signature and checksum validation, and cycle
rejection. No third-party ADF fixture is currently stored in the repository.

## Amiga DMS disk archives

Container type identifier: `amiga.dms`

Vexter parses the `DMS!` information header and every framed `TR` track record.
It validates the information-header, track-header, and packed-data CRC-16/ARC
values and detects a complete valid stream as certain. Matching `.dms` and
`.fms` suffixes add evidence. Complete ordered disk tracks are concatenated and
opened through the ADF handler, exposing the same `/disk` hierarchy and
recursive contained-file inspection as a direct ADF image.

NOCOMP, SIMPLE/RLE, HEAVY1, and HEAVY2 are decoded. HEAVY decoding retains its
LZ dictionary, static Huffman trees, and repeated-distance state between tracks
when requested by the control flags, and applies the optional second-stage DMS
RLE stream. Every reconstructed track is checked against its declared 16-bit
byte sum. QUICK, MEDIUM, DEEP, encryption, and compression identifiers 7
through 9 remain inspectable as opaque `/tracks` resources but cannot yet be
reconstructed.

The authentic `Frustration.dms`, `HolyGrail.dms`, and `GoldenFleece.dms`
reference files establish that the four bytes after `DMS!` may be zero rather
than the document's listed text values. All three contain 80 HEAVY2 tracks
representing a 901,120-byte DD OFS disk. Vexter's reconstructed images are
byte-identical to xDMS output and then pass the ADF parser. Their output hashes
are recorded in `THIRD_PARTY.md`.

The supplied public-domain xDMS source tree is the reference for CRC/checksum,
RLE, HEAVY, and stateful-track behavior, and for future compression support. The
exact upstream repository and supplied revision, including xDMS's own LHA,
LZHUF, and `testdms` acknowledgements, are recorded in
[`THIRD_PARTY.md`](../THIRD_PARTY.md). No xDMS code is compiled or linked into
Vexter.

The authentic disks also establish a filesystem compatibility detail: a user
directory may place its own header block in its first hash slot. Vexter skips
that self-entry and does not mistake the directory header's parent-level
collision pointer for a child-chain pointer. Other repeated directory blocks
continue to be rejected as cycles.

## XPK SHRI compressed containers

Container type identifier: `archive.xpk`

Vexter recognizes checksummed `XPKF` containers using the `SHRI` compressor.
It validates the master header, short or long chunk headers, four-byte payload
alignment, alternating-byte payload checksums, total packed and unpacked
sizes, and the terminal chunk. Raw chunks and SHRI versions one and two are
supported; version two retains its arithmetic model and LZ history across
chunk boundaries. Password-protected streams and other XPK compressors are
reported as unsupported.

The expanded payload appears at `/content` and is inspected recursively using
the ordinary registered format handlers and eight-container depth bound. The
directly supplied `Fishdemo.anim` is a 49,216-byte XPK/SHRI stream containing
five compressed chunks. It reconstructs byte-for-byte to the supplied
150,464-byte `Fishdemo-unpacked.anim`, which is a 320×256, six-plane method-5
ANIM containing 102 frames. Their SHA-256 values are respectively
`cf2893316af009d7885cef0ae3418da579f10c56b1bd2d50a76d539883f50915`
and `7d906e3ba64417d42452b4c3092148fa6f59a46fdcb01777aad24e120bc96554`.

The XPK framing and SHRI arithmetic/LZ behavior are ported from the supplied
BSD 2-Clause Ancient Format Decompressor checkout. Its revision and required
attribution are recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md).

## PowerPacker compressed containers

Container type identifier: `archive.powerpacker`

Vexter recognizes standalone `PP11` and `PP20` PowerPacker streams. It
validates the five known efficiency tables, four-byte file alignment, the
24-bit expanded size and initial bit shift, then reconstructs the backwards
literal/LZ bitstream with output-bound and back-reference checks.

The expanded payload appears at `/content` and is inspected recursively using
the ordinary registered format handlers and eight-container depth bound. The
supplied `Lemmings Inspiration.anim` has SHA-256
`335c7276d069ee8777dce42933a5d5f76b86c587cad66c4f714ae0d3ef4a8339` and
expands from 23,192 to 36,598 bytes. Its payload is a 320x256, five-plane ANIM
with ten stored forms. Its `DPAN` chunk exposes eight logical frames at 10
frames per second; the final two forms are interleave history for looping.
Its declared colour ranges are available through the optional cycled-animation
exports; invalid and redundant declarations are filtered as described below.

The decoding behavior is ported from `PPDecompressor.cpp` in the supplied BSD
2-Clause Ancient Format Decompressor checkout. Its revision, source hashes,
and required attribution are recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md).

## Amiga Hunk executables and LHA self-extractors

Type identifiers: `amiga.hunk-executable` and `amiga.lha-sfx`.

The current Hunk parser is intentionally an identification-level reader. It
validates `HUNK_HEADER`, the allocation table, CODE, DATA, BSS, relocation,
symbol, debug, and END framing and retains loadable bytes as opaque resources.
It also retains the length-delimited overlay arrangement present in the
supplied `lha.run`; detailed executable semantics and broader Hunk variants
remain future work.

`lha.run`, SHA-256
`76bae515264fcc3e1c69058ff03a4bcb096152a732cf19fdb03cceee18932497`,
contains a two-hunk 680x0 executable, one appended level-0 LH5 usage record,
and a level-1 LH5 archive. It is identified as `amiga.lha-sfx`. The executable
is exposed below `/executable`, the usage member below `/sfx/usage`, and the
main archive below `/archive`; main members use ordinary bounded recursive
inspection. Hunk identifiers and skip framing are informed by `tbsym.c` from
the supplied public-domain-source IFFSpecs bundle, as recorded in
`THIRD_PARTY.md`.

## LHA/LZH archives

Level-0 and level-1 LHA archives expose a host-independent hierarchy below `/archive`.
Both `.lha` and `.lzh` extensions are recognized. Header byte sums, member
bounds, uncompressed sizes, and CRC-16 values are validated. Amiga backslash
paths are canonicalized to resource-path separators, while absolute, empty,
dot, parent, duplicate, and conflicting paths are rejected.

Stored `-lh0-` and static-Huffman/LZ `-lh5-` members are reconstructed and
recognized contents are inspected recursively through the shared eight-layer
bound. Other compression methods and header levels 2 and 3 remain explicit
unsupported-format errors pending supplied documentation and controls.
Checksummed level-0 framing is detected independently of member decoding, so
an archive using an unsupported method is still identified as LHA and reports
that method rather than appearing to be an unrecognized file.

The level-0 layout follows the supplied CC0 Kaitai specification. The LH5
decoder is a native Nim port of the supplied MIT-licensed jslha revision,
validated against authentic Aminet archives and independent 7-Zip output. The
routine suite embeds one authentic small LH5 member with its decoded control.

## ZIP archives

Container type identifier: `archive.zip`

Vexter supports ordinary single-volume ZIP archives containing stored or raw
DEFLATE-compressed members. It validates the end record, central directory,
local header and data bounds, declared expanded sizes, and each file's CRC-32.
ZIP64, encryption, unsupported compression methods, and classic multi-volume
archives are reported as unsupported rather than partially interpreted.

The archive appears as `/archive`; directories become
`archive.zip-directory` groups and unrecognized files become
`archive.zip-file` opaque nodes retaining their expanded bytes. Recognized
members open recursively like ADF files. Recursion remains bounded to eight
container layers.

Archive names are logical names, independent of the machine opening them.
Names marked as UTF-8 are validated and legacy names are decoded as CP437.
Both slash forms are treated as separators. Absolute paths, empty components,
`.` and `..`, duplicates, file/directory conflicts, and names longer than 255
Unicode characters are rejected. This prevents recursive/ambiguous path loops
without attempting to materialize archive names on the host filesystem.

`normalizedZipExportName` and bulk-export naming replace host-sensitive control
and punctuation characters, trim trailing dots/spaces, and protect Windows
device names. `export-all` preserves the normalized resource hierarchy and
adds deterministic suffixes when distinct logical names normalize identically.

## Amiga IFF 8SVX audio

Container type identifier: `amiga.8svx`

Sampled-instrument type identifier: `amiga.8svx-instrument`

An 8SVX is an IFF `FORM 8SVX` containing a 20-byte `VHDR` voice header and a
`BODY`. Vexter exposes it as a generic sampled instrument at `/instrument`.
The archetype separates signed PCM samples, bit-depth and channel-aware audio
buffers, playback-rate-bearing sounds, and instrument metadata. This keeps the
8SVX loop and playback properties available without baking them into the PCM
buffer or requiring tracker-specific structures.

Uncompressed signed eight-bit PCM and Fibonacci-delta compression are
decoded. Mono, left-only, right-only, and channel-major stereo BODY layouts
are supported through `CHAN`; left/right-only data carries an implied -1/+1
pan. VHDR supplies the playback rate, one-shot and repeat lengths,
samples-per-high-cycle, and 16.16 volume. Optional `NAME` and `ANNO` text is
retained as metadata. Sample regions may omit a trailing portion of BODY but
may not exceed the decoded samples.

Valid 8SVX structure is detected as **certain**, with `.8svx` or `.8sv`
providing supporting evidence. Multi-octave BODY layout is explicitly
unsupported. WAV is the natural export and writes channel-interleaved,
uncompressed eight-bit PCM at the VHDR playback rate. WAV does not currently
embed the instrument loop, volume, or pan metadata. Synthetic tests cover raw
mono and stereo, delta decoding, metadata projection, WAV routing, and
malformed or unsupported structures; no authentic fixture is currently
stored.

## Amiga IFF 16SV audio

Container type identifier: `amiga.16sv`

Sampled-instrument type identifier: `amiga.16sv-instrument`

The supplied Roland Mainz 16sv.datatype V1.2 documentation defines `FORM
16SV` as the same structure as `FORM 8SVX`, except that BODY contains 16-bit
samples. Its included DataTypes V45 reference source reads native Amiga
16-bit words and its writer emits words directly, establishing big-endian
signed PCM. The included `Bluebird.16sv` fixture independently confirms the
relationship: VHDR declares 23,982 one-shot samples and BODY contains exactly
47,964 bytes.

Vexter decodes uncompressed samples without reducing them to the reference
datatype's eight-bit playback interface. The resulting generic buffer has a
16-bit depth and retains the VHDR playback rate, loop regions, pitch-cycle,
and volume. Because 16SV otherwise retains 8SVX structure, absent, left-only,
right-only, and stereo CHAN layouts use the same channel-major interpretation.
Compression and multiple octaves are explicitly rejected: the supplied
reference implementation lists both compression and stereo as unfinished,
and provides no 16-bit compressed-stream definition. The natural WAV export
contains interleaved little-endian 16-bit PCM.

The supplied documentation, source, and reference-sample provenance and hashes
are recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md). Automated tests use
synthetic data for stereo layout and malformed or unsupported input and do not
depend on the separately supplied reference package.

## WAV audio

Container type identifier: `wav`

Sound type identifier: `wav.sound`

WAV import validates an exact RIFF/WAVE stream, including declared RIFF size,
chunk boundaries, odd-byte padding, one `fmt ` chunk, one `data` chunk, and
consistent sample-frame alignment and byte rate. The chunks may occur in
either order. Unknown chunks remain visible as numbered type/size metadata.
Valid integer PCM is detected as **certain**, with `.wav` or `.wave` adding
supporting evidence.

Eight-bit unsigned PCM and little-endian signed 16-, 24-, and 32-bit PCM are
decoded into a plain `VextSound` at `/audio`, with interleaved input separated
into channel-major signed sample buffers. IEEE float, compressed codecs, RF64,
and WAVE_FORMAT_EXTENSIBLE are explicitly deferred. Synthetic tests cover the
implemented widths, multiple channels, unusual chunk order, odd padding,
unknown chunks, and malformed structures. Authentic compatibility fixtures
remain pending user-supplied WAV files.

WAV export accepts generic `VextSound` values rather than 8SVX structures. It
writes a canonical RIFF/WAVE file with a 16-byte PCM format chunk and one data
chunk. Channels are interleaved frame by frame. Eight-bit signed internal
samples are biased into WAV's unsigned representation; 16-, 24-, and 32-bit
samples use little-endian two's-complement PCM. Sample range, channel shape,
sample rate, RIFF size, and byte rate are validated before an artifact with
the `audio/wav` media type is returned.

## Amiga IFF, ILBM, ACBM, and PBM

Container type identifier: `amiga.iff`

Image/container type identifier: `amiga.ilbm`

Contiguous bitmap type identifier: `amiga.acbm`

Packed bitmap type identifier: `amiga.pbm`

Raster type identifier: `amiga.ilbm-image`

Packed bitmap raster type identifier: `amiga.pbm-image`

IFF files begin with `FORM`, a big-endian length covering the four-byte form
type and all following chunks, and the form type itself. Each chunk has a
four-byte identifier, big-endian payload length, payload, and one external pad
byte when the payload length is odd. Generic, structurally valid forms expose
an inspectable `/chunks` group with numbered opaque chunk resources and chunk
identifier/length metadata.

An ILBM is `FORM ILBM`. Vexter requires a 20-byte `BMHD` before its single
`BODY`; optional `CMAP` and four-byte `CAMG` properties must also precede the
body. Unknown chunks are skipped through the generic IFF framing. The image is
exposed as an indexed raster at `/image`.

ILBM rows are padded to 16-pixel word boundaries. For every scanline, plane
rows occur in order from plane zero (the least-significant palette-index bit)
upward, with the most-significant pixel bit first within each byte. Compression
zero is read directly. Compression one uses ByteRun1 independently for every
plane-row; runs may not cross row boundaries. Some legacy writers incorrectly
include the external IFF alignment byte in an odd-sized compressed BODY's
declared payload. Vexter accepts exactly one trailing zero byte in that case;
other trailing BODY data remains invalid.

An Amiga Contiguous Bitmap is `FORM ACBM` and uses an `ABIT` chunk in place of
ILBM's `BODY`. It otherwise shares `BMHD`, `CMAP`, `CAMG`, palette, indexed,
EHB, and HAM interpretation with ILBM. `ABIT` stores all rows of plane zero,
then all rows of plane one, continuing upward through the declared bitplanes.
Uncompressed and row-bounded ByteRun1 data are supported. ACBM images expose
the same raster resource at `/image` and use the normal PNG/GIF export paths.

Provisional IFF PBM support recognizes `FORM PBM ` as a packed eight-bit
indexed image. Unlike ILBM, its pixels form one chunky byte stream rather than
interleaved bitplanes. It uses the ordinary 20-byte BMHD, optional CMAP, and
BODY chunks and exposes `/image` as `amiga.pbm-image`.

The packed-pixel and single-plane facts were supplied directly by the
developer. A temporary external compatibility corpus confirms BMHD depth eight
and independently bounded ByteRun1 decoding across 42 even-width, unmasked
images. The draft importer additionally assumes each stored row is padded to an
even byte count and compression zero is raw storage. No-mask and
transparent-colour masking are supported; mask-plane and lasso modes are
rejected because a separate mask layout has not been established. CMAP
components are currently retained as full eight-bit values. Raw, odd-width,
and transparent images currently have synthetic coverage only and remain
subject to fixture confirmation.

Ordinary indexed images with one through eight planes are supported. A `CAMG`
EHB flag selects six-plane Extra Half-Brite: palette indices 32 through 63 are
generated from colours 0 through 31 by shifting each expanded RGB component
right once. If every component in a CMAP has a zero low nibble, Vexter treats
it as legacy Amiga four-bit storage and expands `$x0` to `$xx`; otherwise the
eight-bit component values are retained unchanged.

HAM and HAM8 decode to `VextTrueColourImage`. At the beginning of each
scanline the held colour is black. A mode-zero code selects a base CMAP entry;
the other modes replace blue, red, or green respectively while retaining the
other two held components. HAM uses four data bits and HAM8 uses six, expanded
to eight-bit components across the full 0–255 range. The uncommon five- and
seven-plane variants with a single mode bit follow the same decoder.

True-colour images export to RGB PNG. GIF remains limited to indexed rasters;
Vexter reports that quantization is not implemented instead of silently
reducing colours. All four BMHD masking values are supported. Mode zero is
opaque. Mode one reads an additional one-bit mask plane after the colour planes
of each scanline (or after the contiguous colour planes in ACBM), with set bits
opaque. Mode two makes pixels matching `transparentColour` transparent. Mode
three performs lasso masking: matching pixels connected to the bitmap boundary
are transparent, while enclosed matching islands remain opaque. Mask rows use
the same independent raw or ByteRun1 framing as colour-plane rows. The result
is stored as per-pixel alpha on indexed or HAM true-colour rasters and is
preserved by PNG/APNG export.

The `WP` ILBM inside `Frustration.dms` is the authentic transparent-colour
control. It declares masking mode two and palette index zero; it now inspects
without warnings and exports as a 32×768 RGBA PNG. Synthetic fixtures cover
explicit raw and ByteRun1 mask planes, transparent colour, lasso connectivity,
and rejection of undefined masking values.

The authentic Deluxe Paint 4.5 AGA samples `TutGallery.Ham` and
`EAWorld.Ham8` both decode byte-for-byte to the RGB pixels in their supplied
PNG controls. Both files declare eight source planes, despite the shorter
`.Ham` suffix on the former. The 320×200 `AquariumBackground.Ham` declares six
planes and provides authentic HAM6 coverage. Its ImageMagick PNG retains
four-bit component levels as `$x0`; after the same documented normalization to
`$xx` used for legacy palettes, all expanded RGB pixels match exactly.

The King Tutenkhamen fixture is 320×200, five-plane, and ByteRun1-compressed.
Its ImageMagick PNG is used as a layout control after normalizing the PNG's
retained `$x0` palette components to the required `$xx` values. Attribution
and redistribution cautions are recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md).

## Amiga IFF ANIM

Type identifier: `amiga.anim`

The operation 1–5 structures are documented by the locally supplied Aminet
`IFFSpecs.lzh` archive, SHA-256
`de8d37539503f3ee8599ec2e6121866d9e8186918ecaed96543626b56e0c2f85`.
Its `DOCUMENTS/Code.doc` declares the example source public domain, and its
ANIM specification is the 4 May 1988 SPARTA/Aegis revision.

An animation is `FORM ANIM` containing nested `FORM ILBM` records. The first
record is a complete ILBM and establishes dimensions, bitplane depth, palette,
and CAMG display mode. Later records contain a 40-byte `ANHD` animation header
and either a `DLTA` delta or, for operation zero, a replacement `BODY`.
Vexter exposes the result at `/animation`.

Planar frames are retained before rendering because deltas modify individual
planes. An ANHD interleave of zero means the delta refers to two frames back;
other values give the explicit reference distance. The second frame falls
back to the initial frame. A version-3 `DPAN` chunk supplies the logical frame
count and frames-per-second playback rate; stored interleave history frames
beyond that logical count are decoded but not presented. Without `DPAN`,
relative times are Amiga vertical-blank jiffies: explicit PAL CAMG monitor
modes use 50 Hz and explicit NTSC modes use 60 Hz. Files without a monitor ID
retain the ANIM specification's 60 Hz default.

ILBM `CRNG` and `CCRT` palette ranges are retained for indexed ILBM and ANIM
resources. Active CRNG rates use the format's 16,384/60 rate scale; CCRT uses
its seconds/microseconds interval and signed direction. Vexter retains up to
six effective ranges. Empty or one-colour ranges, ranges outside the decoded
palette, inactive or zero-rate ranges, and ranges whose colours are all equal
are ignored.

Colour cycling is an optional export transformation. `png` writes the natural
first image, while ordinary `gif` and `apng` preserve an existing animation
without applying its ranges. `gif-cycled` and `apng-cycled` combine the source
animation period with every range period, repeat through their least common
multiple, and emit a frame at each source-frame or palette-step boundary.
Expansion stops before exceeding 1,000 frames by default. The CLI requires
`--allow-large-animation` to acknowledge a larger result; the GUI presents a
confirmation before retrying such an export.

In the GUI, an indexed static image with effective colour ranges is playable
without pre-expanding the complete loop: its palette advances on demand at
each range boundary. Existing animations retain their ordinary playback
behavior for now; whether their colour cycling should be automatic or
toggleable remains deliberately undecided.

Implemented delta operations are:

- method 1, a plane-masked rectangular ILBM BODY XOR applied at its ANHD
  coordinates;
- methods 2 and 3, longword and word horizontal skip/single/run changes,
  including the historical negative-run cursor convention used by VideoScape;
- method 4, generalized short/long assignment or XOR deltas with separate or
  shared instruction lists, optional RLE, horizontal or vertical traversal,
  and short or long instruction fields;
- method 5, byte-vertical skip/literal/repeat encoding;
- method 7, byte opcodes with separate short/long data lists, clipping the
  padded tail of a final longword when the ILBM row is only word-aligned; and
- method 8, embedded short/long vertical operations, including a final short
  column when a row is not longword-aligned.

Method 1 decodes its BODY with the initial ILBM compression mode and XORs only
the rectangle and planes selected by ANHD. Methods 2 and 3 use eight plane
pointers followed by signed 16-bit controls.
Non-negative controls skip that many units and replace one unit. For negative
controls other than minus one, the run starts `abs(control) - 1` units beyond
the previous destination; a following count introduces that many contiguous
replacement units and leaves the cursor on the last one. Minus one terminates
the plane. Method 5 also honors the XOR convention and interleave-one layout
documented for Deluxe Paint animation brushes. This provides implementation support for
brushes, pending authentic sample verification. Stereo method 6 and reserved
method 74 remain structurally identifiable but explicitly
unsupported; their behavior is not inferred beyond the supplied specification.
Delta-compressed first frames are likewise deferred.

Indexed ANIMs produce `VextIndexedAnimation`. GIF-compatible animations default
to GIF, including frames with distinct palettes or binary transparency. HAM
frames pass through the ILBM HAM renderer and
produce `VextTrueColourAnimation`, defaulting to APNG. The APNG encoder writes
full-size RGB or RGBA frames, an infinite loop count, and per-frame millisecond
delays using standard `acTL`, `fcTL`, `IDAT`, and `fdAT` chunks. Indexed images
and animations can also request APNG explicitly; each frame is expanded
through its own palette, preserving palette changes and per-pixel alpha. An
indexed animation that GIF cannot represent naturally defaults to APNG, while
GIF remains preferred whenever both formats are viable. GIF export of
true-colour animation remains unavailable without quantization.

Synthetic tests cover methods 1 through 5, 7, and 8, brush-style XOR, interleave
behavior, and APNG structure. The authentic `TheTour.anim` method-5 fixture
contains 34 reconstructed frames; after normalizing its GIF control's legacy
`$x0` palette components to `$xx`, every expanded RGB pixel matches. Its last
two frames reproduce frames zero and one for conventional continuous looping.
An authentic animation-brush fixture is still needed for verification.

The directly supplied `StarWars1.anim` and `StarWars2.anim` VideoScape
method-3 files were independently loaded and resaved by the supplier in Deluxe
Paint as `StarWars1-op5.anim` and `StarWars2-op5.anim`. Every shared visible
frame of each original reconstructs identically to its method-5 control. The
controls store 352×256 frames while the originals store 352×220 frames; the
additional 36 rows are padding and are not addressed by either method-3
stream. Their respective SHA-256 values are
`e92a4713ea2c5b193c28632ac19c952b24c8bef287c079126a69f55b508e7598`,
`f80fe41d33d36de34dca7bcf8becefff555d0c7f68c85c0813c2e9529f9a9d1f`,
`2539fa8cf006f88bdcdf20827f033cef4dfd898993300fd83742dc24926cfc0f`,
and `22c1b01c20b1c978a4c1a668c6b3d561b5d58952f15cdb30202a9988b1612afa`.

The directly supplied `babewalk.anim7` sample establishes padded final
longwords in method 7. It is a 200×150 HAM8 animation whose 26-byte ILBM rows
are encoded as seven 32-bit delta columns; only the leading two bytes of the
seventh column belong to the bitmap. It contains 26 decoded frames and has
SHA-256 `9d29baa58a27c8e13b97f1330459043736f56ea476a1e850730e772074c25e20`.

The directly supplied method-5 animations `3Globes.anim` and `batcomp.anim`
establish the included-BODY-pad compatibility case. Their initial compressed
ILBM payloads respectively consume 140,141 of 140,142 bytes and 21,467 of
21,468 bytes, with a single trailing zero in each. They decode as 60 frames at
640×480 and 22 frames at 640×400. Their SHA-256 values are
`5d7d2a89f288278b03bc62fc009d17ccbb6fd2e1cb399d4b2b8633a1866c0c5c`
and `8878371f4b845b246924bf5c20e3e8e5033bec3396b0320a4889af5801fac0cb`.

## ZX Spectrum raw screen

Type identifier: `zx-spectrum.screen`

A raw ZX Spectrum screen is a 1:1 dump of Spectrum display memory:

- 6,144 bytes of non-linearly arranged bitmap data;
- 768 bytes of colour attributes;
- exactly 6,912 bytes in total;
- a 256 x 192 display; and
- commonly, but not necessarily, a case-insensitive `.scr` extension.

It has no magic signature. An exact size match, strengthened by a `.scr`
extension, identifies the format as **probable**, not certain. The container
exposes one resource:

```text
/screen
```

Raster archetypes are defined together in `archetypes/raster.nim`, leaving room
for indexed images, indexed animations, and forthcoming true-colour raster
types. The screen decoder produces a `VextIndexedImage` when no FLASH attribute
is present. When FLASH is present it instead produces a
`VextIndexedAnimation`: its first frame is the natural display state and its
second swaps ink and paper in flashing cells. Both animation frames currently
have a duration of 320 milliseconds.

Default output is selected through the archetype content:

```text
non-FLASH screen -> indexed image       -> PNG
FLASH screen     -> indexed animation   -> GIF
```

An explicit `--format png` applied to an animation exports its natural first
frame. This is a tested regression requirement. The PNG and animated GIF
encoders have no external dependencies. Their first versions favor simple,
deterministic correctness over file size: PNG uses stored DEFLATE blocks and
GIF uses valid low-compression LZW output.

### Fixtures

Fixtures are stored under `tests/fixtures/zx-spectrum.screen/`. The
project-produced `colours` set exhaustively exercises ink, paper, BRIGHT, and
FLASH values. `colours-listing.scr` contains no FLASH attributes and proves the
static indexed-image pathway. Fixture-specific provenance, coverage, and hashes
are recorded alongside the files.

Control images may be optimized and their encoded structure is not normative.
Tests compare expanded pixel colours and positions, with animated controls
compared as fully composited frames. Palette ordering, compression, chunk
layout, frame cropping, and other encoding choices are ignored.

## Generic AMOS banks

Type identifier: `amos.bank`

Standalone generic banks use the four-byte `AmBk` identifier and commonly use
an `.Abk` extension. After the identifier, all values are big-endian:

- a two-byte bank number;
- two bytes of flags;
- a four-byte stored length;
- an eight-byte, space-padded, unterminated ASCII bank-type label; and
- the bank payload.

Bits 30 and 31 of the stored length describe memory behavior, while bits 28
and 29 are undefined. Vexter ignores all four high bits. Bits 0 through 27
contain the payload length plus eight, so Vexter masks the value with
`$0fffffff` and subtracts eight. The resulting length must exactly match the
remaining bytes.

Known labels currently include `Music`, `Tracker`, `Amal`, `Data`, `Datas`,
`Work`, `Asm`, `Code`, `Pac.Pic.`, `Resource`, and `Samples`. Labels outside
this list remain reportable because they are descriptive rather than a format
dispatch mechanism.

A structurally valid generic bank is detected as **certain** and exposes one
opaque `amos.bank-data` resource at `/bank`. Inspection reports `bank.number`,
`bank.flags`, `bank.type`, and `data.length` metadata. The undecoded bank
payload is retained and defaults to raw `.bin` export.

## AMOS bank sets

Type identifier: `amos.bank-set`

An AMOS bank set starts with the four-byte `AmBs` identifier and a two-byte
big-endian member count. Exactly that many complete `AmBk`, `AmSp`, or `AmIc`
banks follow immediately, without padding or an offset table. Standalone bank
sets conventionally use an `.Abs` extension, matched case-insensitively.

Every member is structurally validated with the same parser used for its
standalone form. Prefix-aware parsing reports each member's exact consumed
length, allowing the next magic identifier to be read directly. Unknown bank
identifiers, truncated members, count mismatches, and trailing data invalidate
the standalone set. The same prefix API delimits the bank-set appendix in an
AMOS program container.

A valid set is detected as **certain**. It exposes a `/banks` group with
zero-based member paths. Generic banks appear as opaque `/banks/N` resources.
Sprite and icon resources appear at `/banks/N/sprite/I` and
`/banks/N/icon/I`, retaining the same raster types and hotspot metadata as
standalone banks. Supported raster members can be exported individually even
when other members remain opaque.

## AMOS programs

Type identifier: `amos.program`

Tokenised AMOS programs conventionally use an `.AMOS` extension. They begin
with a 16-byte ASCII header whose prefix is either `AMOS Pro` or `AMOS Basic`.
Professional headers commonly, but not invariably, append a version such as
`AMOS Pro101` within those 16 bytes. The full header is retained as metadata
after trailing spaces and nulls are removed.

The header is followed by a four-byte big-endian byte length and exactly that
many bytes of tokenised listing data. Each listing line records its word
length and indentation, contains its tokens, and ends with a two-byte null
token. An `AmBs` bank-set appendix follows at the resulting boundary. The
appendix is mandatory even when its member count is zero.

A program with a recognized header, a valid listing boundary, and a complete
bank appendix is detected as **certain**. `/listing` is an exportable text
resource with `amos.header` and encoded `data.length` metadata and defaults to
`.txt`. Attached banks use the same `/banks/N` hierarchy as a standalone set,
so supported sprite and icon resources can be inspected and exported directly
from the program while other banks remain opaque.

The listing decoder reconstructs source text rather than an AST. Simple tokens
use the imported AMOS symbol mapping, retaining distinct token identifiers
even where overloaded forms render identically. Complex tokens cover variable
and procedure names, labels and references, strings, binary/hex/integer/single
values, comments, flow-control records, and recognized extension commands.
Unknown ordinary tokens render the unparsed remainder of their line as
bracketed lowercase hexadecimal. Unknown extension tokens render as
`[ext N hex]`. Encrypted procedure bodies are restored before line decoding.
For each encrypted line, bytes after its four-byte cleartext prefix are XORed
with the evolving AMOS key, secondary key, and procedure-derived key. Compiled
procedures are not treated as encrypted. Invalid boundaries and line framing
remain explicit errors.

The `Fold.Acc` editor accessory supplied during development uses the same
outer program and bank-appendix structure as an ordinary AMOS program. Its
distinctive content is a 656-byte encrypted procedure body. Decryption reveals
the procedure-locking implementation; any unknown commands remain represented
by the normal bracketed hexadecimal diagnostics. Vexter therefore currently
treats it as `amos.program`; a separate accessory type would require structural
evidence beyond its `.Acc` filename.
The decrypted source additionally confirms `$011c` as `Border$`, `$0cd8` as
`Default Palette`, `$220a` as `Bset`, `$2296` as `Areg`, and `$22a2` as
`Dreg`. With these mappings the accessory has no diagnostic unknown-token
forms left.

### Fixtures

`tests/fixtures/amos.program/Xerxes' Revenge.AMOS` is an AMOS Basic demo with
a 6,264-byte tokenised listing and four attached banks. It establishes the
listing boundary and nested extraction of 28 sprites alongside two `Datas`
banks and one `Pac.Pic.` bank. Provenance, coverage, and its hash are recorded
beside the fixture and in [`THIRD_PARTY.md`](../THIRD_PARTY.md).

## AMOS sprite and icon banks

Type identifiers: `amos.sprite-bank` and `amos.icon-bank`

Standalone AMOS sprite and icon banks conventionally use an `.Abk` extension;
matching is case-insensitive. Their four-byte identifiers are `AmSp` and
`AmIc`, respectively. A valid identifier plus a completely valid bank
structure identifies the exact bank type as **certain**. The extension adds
supporting evidence but is not required.

All numeric fields are big-endian. The identifier is followed by a two-byte
image count and then the image records. Each record contains:

- a two-byte width measured in 16-pixel words;
- a two-byte pixel height;
- a two-byte colour depth from one through five bitplanes;
- signed two-byte X and Y hotspot coordinates; and
- `widthWords * 2 * height * depth` bytes of planar image data.

The bank's shared 64-byte palette contains 32 big-endian `$0RGB` entries,
expanded from four to eight bits per channel by nibble replication. Vexter
accepts it directly after the count, as described for the format, or after all
image records, as established by the supplied DRAGON fixture.

Planar data is plane-major, beginning with plane zero. Plane zero is the
least-significant palette-index bit. Words are big-endian and pixels are read
most-significant bit first, beginning at output column zero.

Sprite banks expose a `/sprite` group with `amos.sprite` raster children at
`/sprite/0`, `/sprite/1`, and so on. Icon banks analogously expose `/icon` and
`amos.icon` children. Each child is a `VextIndexedImage` and carries signed
integer `hotspot.x` and `hotspot.y` metadata. PNG is consequently its default
export format.

### Fixtures

`tests/fixtures/amos.sprite-bank/DRAGON.Abk` contains ten sprite frames. An
independently generated GIF stored beside it is the authoritative rendering
control: every expanded RGB pixel matches the conventional unshifted decode.
Fixture hashes and details are recorded in that directory's README. Origin
and attribution are recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md).

## ZX Spectrum snapshot

Type identifier: `zx-spectrum.snapshot`

A 48K `.sna` snapshot is exactly 49,179 bytes long. Its first 27 bytes contain
processor registers and execution state, followed by a direct 48K RAM image.
The first 6,912 bytes of that RAM image are the current Spectrum screen.

128K `.sna` snapshots are exactly 131,103 or 147,487 bytes long, depending on
which RAM banks are currently paged in. They use the same 27-byte header and
place the current 6,912-byte screen at the same offset as the 48K layout.

An exact size match, strengthened by a case-insensitive `.sna` extension,
identifies the format as **probable**. The snapshot container exposes the
embedded display as a `zx-spectrum.screen` resource through the canonical path:

```text
/screen
```

Extraction delegates to the raw-screen decoder and consequently follows the
same indexed-image or indexed-animation and PNG/GIF pathways.

For 48K snapshots, Vexter also reads the little-endian `PROG` system variable
at address `$5C53`. Since an SNA omits ROM, an address is translated to a file
offset by subtracting `$4000` and adding the 27-byte header. A structurally
valid listing is exposed as `zx-spectrum.basic` at `/listing`. BASIC extraction
from 128K snapshots is intentionally deferred until active-bank semantics are
confirmed.

### Fixtures

Fixtures are stored under `tests/fixtures/zx-spectrum.snapshot/`.
`colours.sna` contains the program that produced `colours.scr`, while
`colours-listing.sna` captures its non-flashing BASIC listing. Each snapshot's
screen-memory region matches its companion raw screen byte-for-byte. Provenance
and hashes are recorded alongside the files.

## ZX Spectrum tokenised BASIC

Type identifier: `zx-spectrum.basic`

Each line begins with a two-byte big-endian line number and a two-byte
little-endian byte length, and ends with `$0D`. A following line-number field
of 32768 or greater marks the variables boundary. Bytes 32 through 127 retain
their ASCII values; bytes `$A5` through `$FF` expand through the Spectrum BASIC
keyword table. The `$0E` marker and five-byte calculator representation that
follow a textual number are omitted.

Block graphics `$80` through `$8F` map to Unicode quadrant/block characters;
in particular `$8F` becomes `█`. Since UDG shapes are runtime-defined, bytes
`$90` through `$A4` render reversibly as `⟦UDG A⟧` through `⟦UDG U⟧` rather
than pretending to know their appearance. Display controls embedded in strings
render as annotations such as `⟦INK 2⟧`, `⟦INVERSE 1⟧`, and `⟦AT 10 5⟧`.
When annotations occur, explanatory `REM VEXTER:` lines precede the listing.
Other unrecognised bytes remain visible as `⟦ZX:$HH⟧`.

TAP Program header/data pairs expose the same text resource. One listing uses
`/listing`; multiple listings use `/listing/1`, `/listing/2`, and so on.

## ZX Spectrum TAP container

Type identifier: `zx-spectrum.tap`

A TAP file is a sequence of blocks, each prefixed by a two-byte little-endian
length. The block bytes comprise a flag, content, and an XOR checksum covering
the flag and content. Vexter validates every block length and checksum and
requires each 19-byte header block to be followed immediately by the data block
it describes.

Vexter exposes CODE records whose declared length is 6,912 bytes, start address
is 16,384, and parameter 2 is 32,768 through the existing screen pathway. One
qualifying record is exposed as `/screen`; multiple records are exposed as
`/screen/1`, `/screen/2`, and so on. Program records containing structurally
valid tokenised BASIC are exposed through the listing paths described above.

Header filenames are ten-byte, space-padded fields. ASCII bytes are retained
and non-ASCII bytes are currently ignored; full Spectrum filename-character
handling remains deferred.

Structurally valid block framing and checksums identify the format as
**probable**, strengthened by a case-insensitive `.tap` extension.

## PCX images

Container type identifier: `pcx`

Raster type identifier: `pcx.image`

PCX detection validates the 128-byte ZSoft header, supported version and
encoding values, inclusive image bounds, plane count, and padded bytes per
scanline. These structural markers identify the format as **probable**; a
case-insensitive `.pcx` extension adds supporting evidence. The image is
exposed at `/image`.

Raw and PCX run-length-encoded scanlines are supported. Runs are bounded to a
single complete scanline across its planes, and each padded row must decode to
exactly the declared size. Padding bytes are not exposed as pixels.

One-, two-, and four-bit samples with a combined depth no greater than four
bits produce indexed images using the header's 16-colour palette. Plane zero
provides the least-significant component of the palette index. Eight-bit
single-plane images require the palette marker and complete 768-byte palette
immediately after the image data and produce a 256-colour indexed image.

Eight-bit three-plane images produce a `VextTrueColourImage`. RGB is the
default plane order. `--pcx-channel-order bgr` selects the alternate ordering
for affected files; the option is passed through recursive ZIP and ADF
inspection as well as direct PCX inspection. PNG export uses the existing
true-colour pathway.

Synthetic tests cover planar pixel assembly, header and trailing palettes,
scanline padding, RLE expansion and row bounds, RGB/BGR interpretation, and
missing or malformed image data. An independently produced authentic fixture
is still desirable for compatibility coverage.

## TGA images

Container type identifier: `tga`

Raster type identifier: `tga.image`

TGA detection validates the 18-byte header, dimensions, image and colour-map
layouts, identification and colour-map boundaries, and complete raw or RLE
pixel coverage. Because TGA has no mandatory signature, valid structure
identifies it as **probable**; case-insensitive `.tga`, `.vda`, `.icb`, and
`.vst` extensions add supporting evidence. The image is exposed at `/image`.

Raw types 1, 2, and 3 and their RLE equivalents 9, 10, and 11 are supported.
RLE raw and repeated packets may cross scanline boundaries and must produce
exactly the declared pixel count. Colour-mapped images accept eight- or
sixteen-bit stored indices and 16/24/32-bit BGR(A) map entries; non-zero palette
origins are normalized to the generic zero-based indexed representation.
Grayscale images currently use eight-bit intensity. True-colour images accept
the documented 16-bit A1R5G5B5, 24-bit BGR, and 32-bit BGRA layouts.

Bottom-left and top-left storage origins are normalized into top-down raster
order. Sixteen-bit five-bit components are shifted left by three as directed by
the supplied specification. Declared binary or eight-bit attributes populate
per-pixel alpha. Reserved descriptor bits, two-way or four-way interleaving,
and Huffman/delta image types 32 and 33 are rejected explicitly.

Implementation follows the developer-supplied copy of the format description
from Paul Bourke's TGA format page, retrieved 2026-08-21. Its linked unlicensed
C example was not supplied or consulted. Current tests are synthetic; an
independently rendered authentic compatibility fixture remains desirable.

## BMP and DIB images

Container type identifiers: `windows.bmp` and `windows.dib`

Raster type identifier: `windows.bitmap`

BMP files use the `BM` file wrapper around a DIB; standalone DIB input begins
directly with its bitmap header. Vexter recognizes the 12-byte OS/2 core
header and Windows 40-, 52-, 56-, 108-, and 124-byte headers. Wrapped BMP
detection is **certain** after its signature, declared size, reserved fields,
DIB structure, palette, and pixel offset validate. A structurally valid
standalone DIB is **probable**, with `.dib` providing supporting evidence.
Both expose a raster at `/image`.

Uncompressed one-, four-, and eight-bit indexed images use their BGR palette
and packed most-significant-first indices. Sixteen-, 24-, and 32-bit images
produce true-colour rasters; ordinary 16-bit pixels use 5:5:5 interpretation,
while declared 16/32-bit colour masks are normalized across their full range.
Non-overlapping, contiguous red, green, and blue masks are required.

Rows are padded to four-byte boundaries. Conventional bottom-up images are
inverted into natural top-to-bottom raster order, while negative-height
Windows DIBs remain top-down. RLE4 and RLE8 encoded, absolute, end-of-line,
delta, and end-of-bitmap commands are supported with image-bound checks;
top-down RLE is rejected.

JPEG/PNG-embedded BMP payloads and CMYK compression modes are explicitly
unsupported. Contiguous, non-overlapping alpha masks are normalized into the
generic per-pixel eight-bit alpha channel. This includes
`BI_ALPHABITFIELDS` and alpha masks embedded in extended Windows headers. A
32-bit BI_RGB image without an explicit alpha mask treats its unused high byte
as opaque, preserving the usual legacy interpretation.

Both indexed and true-colour raster archetypes can carry per-pixel alpha.
Omitting the alpha buffer means fully opaque; `alphaAt`, `rgbaAt`, and
`hasAlpha` expose it uniformly. PNG and APNG export select RGBA output whenever
any non-opaque alpha is present. GIF export supports binary alpha when a
transparent palette index is available; partial alpha remains APNG-only.

Synthetic tests cover Windows and OS/2 headers, wrapped and standalone input,
palette conversion, row orientation and padding, 24-bit colour, 16-bit
bitfields, RLE4/RLE8, invalid offsets, incompatible compression, and
truncation. Authentic compatibility fixtures remain desirable.

## FLI/FLC-family animations

Container type identifier: `flic`

Raster type identifier: `flic.animation`

The importer recognizes the documented FLI (`0xAF11`), FLC/FLX (`0xAF12`),
DTA/EGI (`0xAF44`), compressed EGI (`0xAF30`), and frame-shift EGI (`0xAF31`)
file identifiers. Case-insensitive `.fli`, `.flc`, `.cel`, `.flh`, `.flt`, and
`.flx` extensions add supporting evidence. Valid headers and fully bounded
chunk/frame structures identify the family as **certain**.

Eight-bit FLI/FLC files decode changing COLOR_64/COLOR_256 palettes, BLACK,
FLI_COPY, BYTE_RUN, DELTA_FLI, DELTA_FLC, key images, and key palettes into a
`VextIndexedAnimation`. FLI speeds are converted from 1/70-second ticks; FLC
speeds and Pro Motion per-frame overrides are milliseconds. The declared frame
count excludes and therefore omits a trailing ring frame.

CEL prefix chunks retain registration coordinates and their transparent palette
index becomes per-pixel alpha. FLH/FLT files using the DTA identifier decode
documented 15-, 16-, and 24-bit DTA_BRUN, DTA_COPY, and DTA_LC chunks into
true-colour animations. Both documented 15-bit FLX families use the ordinary
FLC chunks; the Autodesk creator identifier selects pixel-based DELTA_FLC
skips, while other FLX sources use Tempra's byte-based skips.

The supplied page documents the structure and identifiers of EGI segment,
Huffman, script, mask, region, audio, frame-shift, path-map, label, and user
chunks. Unknown or non-rendering chunks remain safely skippable as required by
the format. The separately supplied EGI compression page defines Huffman and
BWT-Huffman blocks and frame shifting; these are decoded for AF30 and AF31
files, including 16- and 24-bit pixel buffers. Huffman compression applies only
to the documented DELTA_FLC, BYTE_RUN, and KEY_IMAGE payloads; DELTA_FLC's line
count remains outside the compressed blocks. One-bit DTA packing and embedded
Small/Pawn bytecode remain delegated to unavailable documents. Files requiring
those missing interpretations report an explicit unsupported-decoding error
rather than guessed behavior.

### Outstanding FLIC work

The remaining work falls into three categories.

Source material is still required before these interpretations can be added
without inference:

- **One-bit AF44 DTA:** obtain the pixel-packing rules: bit order, row padding,
  colour interpretation, whether DTA run lengths count pixels or packed bytes,
  and skip/run units in DTA deltas. Raw/copy, run-length, and delta examples
  with reference images are desirable.
- **Embedded scripts:** obtain the referenced Small/Pawn bytecode version and
  documentation only if bytecode inspection is wanted. Executing scripts is a
  separate product and security decision and is not implied by importing the
  animation.

The following documented features need resource-model or presentation decisions
and authentic examples before implementation:

- EGI bitmap, multilevel, and region masks need an alpha-mapping policy,
  persistence/compositing rules, and examples of full and delta masks. In
  particular, the document supplies a level count but no universal mapping
  from multilevel mask values to opacity. Mask-targeted SHIFT chunks are
  consequently rejected; image-targeted SHIFT chunks are implemented.
- Segment tables, nested segments, launch/continue transitions, overlay prefix
  frames, and path maps need a resource model: whether import exposes every
  branch or renders a selected path, how per-segment ring frames behave, and
  how overlays are selected and composited.
- `WAVE` chunks need single- and multi-block examples and a decision on whether
  discontinuous segment audio becomes one reconstructed `/audio` resource or
  remains attached to animation segments.
- Labels, extended labels, regions, user strings, postage stamps, path maps,
  scripts, and frame-local CEL data need decisions about which values become
  public metadata or child resources. Opaque script preservation does not
  require understanding or executing the bytecode.
- Compatibility handling needs evidence for the documented real-world defects,
  notably bad `oframe` offsets, odd chunk sizes, surplus frame padding, garbage
  reserved fields, and the alternate `0xF5FA` frame identifier. Tolerance will
  not be added solely from the defect list because accepting malformed lengths
  can weaken boundary validation.

Finally, authentic compatibility coverage is outstanding. The temporary corpus
exercises only a classic FLI using COLOR_64, BYTE_RUN, and DELTA_FLI. Synthetic
tests cover the implemented structures and codecs, including Huffman,
BWT-Huffman, image frame shifting, and 15/16/24-bit buffers, but do not establish
compatibility with an EGI encoder. Redistributable, provenance-recorded controls
are wanted for:

- plain Huffman, BWT-Huffman, horizontal/vertical frame shifting, and combined
  shifted/delta EGI animations at eight, 16, and 24 bits per pixel;
- FLC COLOR_256/DELTA_FLC, CEL transparency and registration, both FLX
  variants, and 15/16/24-bit FLH/FLT with each DTA codec; and
- BLACK/COPY/key chunks and the other documented EGI extensions.

Useful fixture records include the source and licence, checksum,
dimensions/depth, declared and ring frame counts, timing, exercised chunks,
and independently produced reference frames or animation. The best research
order is representative EGI controls, one-bit DTA clarification, and then
samples for the already documented extensions.

Implementation follows the developer-supplied copies of CompuPhase's “The FLIC
file format” and “EGI compression schemes”, retrieved 2026-08-21 and
2026-08-22 respectively and recorded in
[`THIRD_PARTY.md`](../THIRD_PARTY.md). Synthetic tests cover every implemented
codec. One temporary external FLI compatibility file (320×200, 41 frames)
inspects and exports to GIF successfully but is not retained as a fixture or
treated as format authority.

## GIF images and animations

Container type identifier: `gif`

Raster type identifier: `gif.image`

GIF87a and GIF89a import validates the logical screen, global and local colour
tables, image rectangles, extension/data sub-block framing, LZW minimum code
size, and final trailer. The exact signature and valid block stream identify
the format as **certain**; `.gif` adds supporting evidence. Extension labels
and expanded data lengths are retained as numbered metadata alongside version,
frame count, background index, and pixel aspect ratio.

Image data is expanded with the GIF clear/end-code LZW dictionary and restored
from four-pass interlaced order when selected. Each image rectangle uses its
local table or the logical screen's global table. GIF89a graphic controls
supply binary transparency, hundredth-second delays, and none, background, or
previous disposal. Frames are composited into full logical-screen images and
exposed at `/image` as a `VextIndexedAnimation`.

A single-image GIF deliberately remains a one-frame indexed animation, so its
natural output is GIF rather than PNG. GIF export writes a local colour table
for every frame, allowing imported animations and other indexed animations to
change palettes. Fully transparent/opaque per-pixel alpha is mapped to a free
transparent palette index. Partial alpha or a frame that cannot fit into 256
colours is not quantized and instead remains suitable for APNG.

Synthetic tests cover GIF87a routing, GIF89a local tables/transparency,
interlacing, changing-palette round trips, and malformed LZW/trailers. The
existing independently encoded Spectrum, AMOS sprite, and 34-frame Amiga ANIM
GIF controls all complete the import pipeline.

## PNG images

Container type identifier: `png`

Raster type identifier: `png.image`

PNG import validates the eight-byte signature, chunk framing and ordering,
CRC-32 values, IHDR methods and legal colour-type/bit-depth combinations,
palette and transparency constraints, consecutive IDAT data, and the terminal
IEND. A valid structure is detected as **certain**, with `.png` adding
supporting evidence. The decoded image or animation is exposed at `/image`.

The complete IDAT stream is inflated and every scanline is reconstructed using
the None, Sub, Up, Average, or Paeth filter. Non-interlaced and all seven Adam7
passes are supported. Grayscale, indexed, grayscale-alpha, true-colour, and
true-colour-alpha images decode at every bit depth permitted for their colour
type. Sixteen-bit components are normalized over their full range to Vext's
current eight-bit channels. Indexed images retain their palette indices;
`tRNS`, explicit grayscale/true-colour alpha, and RGBA data populate the
generic per-pixel alpha channel.

All chunks are retained and reported through numbered `chunk.N.type` and
`chunk.N.length` metadata alongside bit depth, colour type, interlace method,
and total chunk count. APNG `acTL`, `fcTL`, and `fdAT` chunks are therefore
visible and drive animation decomposition. Each frame rectangle is inflated
through the normal PNG scanline pipeline and composited onto a transparent
full-size canvas using source/over blending and none, background, or previous
disposal. The resulting full-canvas frames and rational delays form a
`VextTrueColourAnimation`; no indexed/GIF reduction is attempted. Export
therefore naturally defaults back to APNG. Unknown standard, private, or
non-standard chunks remain metadata-only and do not make an otherwise valid
PNG fail.

The independently encoded PNG controls already stored for Spectrum, AMOS, and
Amiga image tests all complete the new import pipeline. Synthetic tests cover
RGBA round trips, packed indexed pixels and `tRNS`, 16-bit grayscale and all
filters, Adam7 coordinate reconstruction, APNG import/export round trips,
partial-frame blending/disposal, private chunk tolerance/metadata, CRC
rejection, and required chunks.

## QOI images

Container type identifier: `qoi`

Raster type identifier: `qoi.image`

QOI import validates the `qoif` signature, positive big-endian dimensions,
RGB/RGBA channel descriptor, defined colour-space descriptor, byte-aligned
chunk framing, exact declared pixel coverage, and the required eight-byte end
marker with no trailing data. A valid stream is detected as **certain**, with
`.qoi` adding supporting evidence. The decoded true-colour image is exposed at
`/image` and naturally exports as PNG.

RGB, RGBA, INDEX, DIFF, LUMA, and RUN chunks are decoded with eight-bit tags
taking precedence over two-bit tags. Decoding maintains the specified
zero-initialized 64-entry colour hash, starts with opaque black, and applies
channel differences modulo 256. The header's channel and colour-space fields
are retained as metadata but, as specified, do not alter chunk decoding.
Per-pixel alpha is retained when any decoded pixel is non-opaque.

Implementation follows the developer-supplied “The Quite OK Image Format”
Specification Version 1.0 dated 2022-01-05. All eight temporarily supplied QOI
test images from the QOI specification website decoded pixel-for-pixel,
including alpha, against their accompanying PNG controls. Those third-party
files are compatibility evidence only and are not repository fixtures;
automated tests instead construct synthetic streams covering every opcode and
structural failure mode. Provenance and hashes are recorded in
[`THIRD_PARTY.md`](../THIRD_PARTY.md).

## Netpbm images

Container type identifier: `netpbm`

Raster type identifier: `netpbm.image`

Netpbm import supports all seven documented variants: plain PBM/PGM/PPM
(`P1`–`P3`), raw PBM/PGM/PPM (`P4`–`P6`), and PAM (`P7`). It validates magic
numbers, positive dimensions, maxvals from 1 through 65535, ASCII comments and
whitespace, exact raster sizes, sample bounds, packed PBM row padding, and
one- or two-byte big-endian raw samples. Structurally valid input is detected
as **certain**, with `.pbm`, `.pgm`, `.ppm`, `.pam`, or `.pnm` adding evidence.

Plain variants contain exactly one image. Raw P4–P6 and PAM streams may contain
multiple images with no delimiter or padding between them. A single image is
exposed at `/image`; a stream becomes an `/image` group with numbered children
such as `/image/1`. PBM retains its specified zero-white, one-black indexed
interpretation. PGM and PPM samples are normalized from their declared maxval
to true-colour eight-bit components and naturally export as PNG.

PAM parsing accepts arbitrary tuple-type text structurally. Raster decoding is
available for the specification's visual `BLACKANDWHITE`, `GRAYSCALE`, `RGB`,
`BLACKANDWHITE_ALPHA`, `GRAYSCALE_ALPHA`, and `RGB_ALPHA` tuple types. Opacity
samples become Vext alpha. A depth greater than required for the defined tuple
type is accepted and higher planes are ignored, following the specification's
reader guidance. Unknown/nonvisual tuple types remain explicit unsupported-decoding
errors rather than being assigned invented semantics.

Implementation follows the four developer-supplied Netpbm project format
documents recorded in [`THIRD_PARTY.md`](../THIRD_PARTY.md). Automated tests
use synthetic inputs for every variant. These documents describe Portable
Bitmap PBM, not the unrelated Amiga packed-pixel `FORM PBM ` container; IFF PBM
support is documented separately above from its own supplied facts and
compatibility evidence.

## Windows icons and cursors

Container type identifiers: `windows.ico` and `windows.cur`

Vexter validates the six-byte ICO/CUR header, every 16-byte directory record,
and the bounds of every referenced payload. A structurally valid directory is
identified as **certain**; matching `.ico` and `.cur` extensions provide
supporting evidence. Each entry is exposed independently at `/icon/N` or
`/cursor/N`, so a multi-size file is not flattened into one assumed image.

Embedded PNG streams are parsed and decoded through the ordinary CRC-checked
PNG implementation. DIB entries support the same Windows and OS/2 header,
palette, bitfield, raw-pixel, and RLE variants as standalone DIB images. Their
stored height is explicitly split into equal-height XOR image and one-bit AND
mask layers. For uncompressed 32-bit DIB entries the fourth byte is treated as
alpha when it contains any non-zero value; all-zero legacy alpha falls back to
opaque pixels before applying the AND mask. The AND mask always has final say
for transparent pixels.

Inspection metadata retains the directory dimensions, colour count, planes and
nominal depth, data offset and length, detected entry encoding, and actual
decoded dimensions and depth. CUR directory words are instead reported as
`hotspot.x` and `hotspot.y`. Directory dimensions are deliberately not forced
onto embedded images; actual payload dimensions drive decoding and default
largest-image selection. Unsupported entry payloads remain identified opaque
BIN-exportable resources rather than causing an otherwise valid collection to
disappear.

## Amiga Workbench icons

Classic Workbench `.info` DiskObjects are detected and inspected. Their
unselected and selected planar imagery is exposed at `/icon/unselected` and
`/icon/selected`; the unselected image is the implicit classic export. Header
fields, default tool, and tool types are metadata. NewIcons `IM1=` and `IM2=`
records are decoded at `/newicon/unselected` and `/newicon/selected` using
their embedded palettes and colour-zero transparency. Appended OS 3.5
`FORM ICON` images are decoded at `/glowicon/unselected` and
`/glowicon/selected`, including palette reuse, explicit transparency, and
uncompressed or bit-oriented ByteRun image/palette data.

Implicit export prefers GlowIcons, then NewIcons, then the unselected classic
image. Every available representation and state remains explicitly
addressable at its canonical path.

Implementation research used the Amiga SDK includes temporarily supplied in
`sys-include/` and the official NewIcons 4.6 developer package supplied in
`NewIcons46/`, sourced from Aminet. Package `.info` files were used as
non-authoritative compatibility references and were not copied into fixtures.
The locally supplied `Amiga Icon Formats - www.evillabs.net.html` wiki capture
provided documentary details for the NewIcons and OS 3.5 codecs. The capture
itself is research material and is not part of the repository fixtures.

## Historical implementation coverage

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

This is retained only as historical context. Relationships to future formats
will be specified when those formats are deliberately added.
