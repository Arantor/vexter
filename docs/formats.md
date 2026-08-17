# Format support

This document records formats implemented in the current clean-room Vexter
repository and historical coverage that may inform future work. Format work is
undertaken only when explicitly planned; the historical list is not an active
implementation schedule.

## Current CLI subset

The currently implemented formats use this subset of the intended CLI:

```text
vexter inspect [--json] [--all-candidates] [--input-format FORMAT] INPUT

vexter export [--format png|gif] [--resource PATH]
              [--input-format FORMAT] [-o OUTPUT] [--force] INPUT
```

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
`[ext N hex]`. Encrypted procedure bodies are not decoded yet and emit an
explicit `[encrypted procedure]` diagnostic marker.

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
