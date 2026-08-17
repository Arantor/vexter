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

### Fixtures

Fixtures are stored under `tests/fixtures/zx-spectrum.snapshot/`.
`colours.sna` contains the program that produced `colours.scr`, while
`colours-listing.sna` captures its non-flashing BASIC listing. Each snapshot's
screen-memory region matches its companion raw screen byte-for-byte. Provenance
and hashes are recorded alongside the files.

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
