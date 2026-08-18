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

vexter export [--format png|gif|apng|txt] [--resource PATH]
              [--input-format FORMAT] [-o OUTPUT] [--force]
              [--ignore-warnings] [--pcx-channel-order rgb|bgr] INPUT
```

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

Tests build compact logical filesystems within standard-size synthetic DD
images. They cover FFS subdirectories, OFS header removal, exact file bytes,
nested Spectrum decoding, signature and checksum validation, and cycle
rejection. No third-party ADF fixture is currently stored in the repository.

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

`normalizedZipExportName` replaces host-sensitive control and punctuation
characters, trims trailing dots/spaces, and protects Windows device names for
future bulk-export use. `export-all` and deterministic suffixing of normalized
name collisions are not implemented yet.

## Amiga IFF, ILBM, and ACBM

Container type identifier: `amiga.iff`

Image/container type identifier: `amiga.ilbm`

Contiguous bitmap type identifier: `amiga.acbm`

Raster type identifier: `amiga.ilbm-image`

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
plane-row; runs may not cross row boundaries.

An Amiga Contiguous Bitmap is `FORM ACBM` and uses an `ABIT` chunk in place of
ILBM's `BODY`. It otherwise shares `BMHD`, `CMAP`, `CAMG`, palette, indexed,
EHB, and HAM interpretation with ILBM. `ABIT` stores all rows of plane zero,
then all rows of plane one, continuing upward through the declared bitplanes.
Uncompressed and row-bounded ByteRun1 data are supported. ACBM images expose
the same raster resource at `/image` and use the normal PNG/GIF export paths.

Ordinary indexed images with one through five planes are supported. A `CAMG`
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
reducing colours. Mask planes and transparent-colour images still require
decoder work and are rejected rather than losing transparency; the shared
raster archetypes themselves now carry alpha.

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

An animation is `FORM ANIM` containing nested `FORM ILBM` records. The first
record is a complete ILBM and establishes dimensions, bitplane depth, palette,
and CAMG display mode. Later records contain a 40-byte `ANHD` animation header
and either a `DLTA` delta or, for operation zero, a replacement `BODY`.
Vexter exposes the result at `/animation`.

Planar frames are retained before rendering because deltas modify individual
planes. An ANHD interleave of zero means the delta refers to two frames back;
other values give the explicit reference distance. The second frame falls
back to the initial frame. Relative times are Amiga jiffies at 1/60 second.

Implemented delta operations are:

- method 5, byte-vertical skip/literal/repeat encoding;
- method 7, byte opcodes with separate short/long data lists; and
- method 8, embedded short/long vertical operations, including a final short
  column when a row is not longword-aligned.

Method 5 also honors the XOR convention and interleave-one layout documented
for Deluxe Paint animation brushes. This provides implementation support for
brushes, pending authentic sample verification. Methods 1–4, stereo method 6,
and reserved method 74 remain structurally identifiable but explicitly
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

Synthetic tests cover methods 5, 7, and 8, brush-style XOR, interleave
behavior, and APNG structure. The authentic `TheTour.anim` method-5 fixture
contains 34 reconstructed frames; after normalizing its GIF control's legacy
`$x0` palette components to `$xx`, every expanded RGB pixel matches. Its last
two frames reproduce frames zero and one for conventional continuous looping.
An authentic animation-brush fixture is still needed for verification.

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
`bank.flags`, `bank.type`, and `data.length` metadata. The payload is not yet
decoded or exportable.

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
