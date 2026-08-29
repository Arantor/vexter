# Vexter

Vexter is a viewer and extractor for legacy file formats. It provides a Nim
library, a command-line client, and a dependency-free native Windows GUI for
inspecting, previewing, and exporting resources without modifying their source
files.

Vexter is authored by Peter Spicer in collaboration with OpenAI Codex,
including substantial AI-assisted implementation, testing, research against
supplied reference material, and documentation. This implementation began as a
study of the current state of AI use in the software industry and proved
sufficiently useful to continue as an ongoing project.

## Supported formats

- Amiga: Workbench icons, ADF and DMS disks, PowerPacker, XPK/SHRI, IFF
  ILBM/ACBM/PBM, ANIM, 8SVX/16SV audio, monochrome and colour bitmap diskfonts,
  AMOS programs and banks, Hunk
  executables, and LHA self-extractors
- Images and animations: BMP/DIB, PCX, TGA, PNG/APNG, GIF, QOI, Netpbm,
  Commodore 64 KoalaPainter, and FLI/FLC-family files
- Fonts: BMFont text, XML, and binary-v3 descriptors with PNG pages, FZX, and
  monochrome or colour Amiga bitmap diskfonts
- Palettes: Paint.NET and GIMP text palettes, Adobe Swatch Exchange and Aseprite sprite palettes, and palette-only IFF ILBM/ACBM files
- Archives and audio: ZIP, level-0/1 LHA/LZH with LH0/LH5 members, Creative
  Voice PCM audio, and integer PCM WAV
- ZX Spectrum: screen dumps, SNA snapshots, TAP files, and tokenised BASIC
- Game data: classic DOOM IWAD/PWAD directories, palettes, flats, sprites,
  patches, composited wall textures, sound effects, automap-style map previews,
  and other patch-format graphics

Decoded resources can be exported as PNG, GIF, APNG, BMFont text plus PNG
atlases, self-contained HTML reports, metadata JSON, WAV, text, or raw binary.
ILBM and ANIM colour cycling can optionally be expanded into bounded GIF or
APNG animations while static and original-animation exports remain available.
Containers such as ADF, ZIP, LHA, PowerPacker, and XPK are inspected recursively
when their contents use another supported format. See
[format documentation](docs/formats.md) for exact coverage and current
limitations, or the [outstanding-work index](docs/outstanding.md) for a concise
list of known implementation and recognized-format gaps. The broader
[candidate-format and capability catalogue](docs/candidate-formats.md) records
non-binding directions for Vexter's eventual digital-archaeology workbench.

## Building

Vexter requires Nim and Nimble.

```sh
nice -n 15 nimble test
nice -n 15 nimble cli
nice -n 15 nimble gui
```

The CLI task builds Linux and Windows executables. The GUI task cross-compiles
the native Windows application and requires MinGW-w64.

## Command line

```text
vexter inspect INPUT
vexter export [--format png|gif|apng|bmfont|html-report|metadata-json|txt|wav|bin] [-o OUTPUT] INPUT
vexter export-all [--format png|gif|apng|bmfont|html-report|metadata-json|txt|wav|bin] -o DIRECTORY INPUT
```

Run `vexter --help` for the complete option list.

## Licence

Vexter is distributed under the [BSD 3-Clause License](LICENSE). Supplied
specifications, reference implementations, and compatibility fixtures may
have separate terms documented in [THIRD_PARTY.md](THIRD_PARTY.md).
