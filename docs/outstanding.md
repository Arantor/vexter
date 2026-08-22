# Outstanding format work

This is the single concise index of known gaps in formats Vexter already
recognizes. It is not a roadmap: an item being listed does not imply priority,
and unsupported historical or proposed formats are not included. Detailed
behavior and evidence remain in [`formats.md`](formats.md).

- **Amiga Hunk executables and LHA self-extractors**
  - Broader Hunk record and executable-variant coverage needs a supplied Hunk
    specification and authentic controls.
  - Relocations, symbols, debug records, overlays, memory flags, resident
    names, and execution semantics are only framed or retained, not interpreted.
  - Other self-extractor layouts and executable stubs are not recognized.

- **LHA/LZH archives**
  - Header levels 2 and 3 are unsupported.
  - Compression methods other than `-lh0-` and `-lh5-` are unsupported,
    including `-lh1-` through `-lh4-`, `-lh6-`, `-lh7-`, and LArc/extension
    methods.
  - Level-1 extended headers are framed; broader filename, directory,
    platform-metadata, timestamp, and encoding interpretation needs controls.
  - Password protection, encryption, multi-volume variants, and other
    self-extractor arrangements are unsupported.

- **Amiga ADF filesystems**
  - Hard and soft links are identified but not followed or exported.
  - Authentic filesystem fixtures are not committed; current routine coverage
    is synthetic plus separately supplied compatibility disks reached via DMS.

- **Amiga DMS disk archives**
  - QUICK, MEDIUM, and DEEP decompression are not implemented.
  - Encryption and compression identifiers 7 through 9 are not implemented.

- **XPK containers**
  - Compressors other than SHRI are unsupported.
  - Password-protected streams are unsupported.

- **ZIP archives**
  - ZIP64, encrypted entries, classic multi-volume archives, and compression
    methods other than stored and DEFLATE are unsupported.

- **Amiga IFF 8SVX audio**
  - Multi-octave BODY layout is unsupported.
  - WAV export does not preserve instrument loop, volume, pan, or pitch-cycle
    metadata.
  - An authentic committed compatibility fixture is still desirable.

- **Amiga IFF 16SV audio**
  - Compression and multi-octave BODY layouts are unsupported because the
    supplied references do not define them.
  - Stereo behavior has synthetic coverage; broader authentic controls remain
    desirable.

- **WAV audio**
  - IEEE float, compressed codecs, RF64, and `WAVE_FORMAT_EXTENSIBLE` are
    unsupported.
  - Authentic compatibility fixtures remain outstanding.

- **Amiga IFF PBM images**
  - Support remains provisional pending committed authentic fixtures.
  - Raw, odd-width, and transparent images currently have synthetic coverage
    only.
  - Mask-plane and lasso layouts are unsupported because their packed-pixel
    representation has not been established.

- **Amiga IFF ANIM animations**
  - Delta methods 6 and 74 are identifiable but unsupported.
  - Delta-compressed first frames are unsupported pending authentic examples.
  - Animation-brush method-5 behavior still needs an authentic control.
  - Automatic versus user-toggleable colour cycling during playback remains a
    presentation decision.

- **AMOS packed pictures**
  - Partial pictures without a screen header cannot render without an external
    palette.
  - Six-plane packed-picture modes are unsupported.

- **Generic AMOS banks, bank sets, and programs**
  - Unknown bank types remain opaque rather than decoded.
  - Tokenised listings are diagnostic text rather than a complete AST; unknown
    commands remain explicit hexadecimal forms.

- **ZX Spectrum SNA snapshots**
  - BASIC extraction from 128K snapshots awaits confirmed paging semantics.

- **ZX Spectrum TAP containers**
  - Only qualifying screen CODE records and tokenised Program records are
    decoded; other records remain unrepresented.
  - Full Spectrum filename-character handling is deferred.

- **PCX images**
  - An independently produced authentic compatibility fixture remains
    desirable.

- **TGA images**
  - Reserved/interleaved layouts and Huffman/delta image types 32 and 33 are
    unsupported.
  - An independently rendered authentic compatibility fixture remains
    desirable.

- **BMP and DIB images**
  - JPEG/PNG-embedded payloads and CMYK compression modes are unsupported.
  - Top-down RLE is unsupported.
  - Authentic compatibility fixtures remain desirable.

- **FLI/FLC-family animations**
  - One-bit AF44 DTA packing awaits its delegated pixel-packing specification.
  - Embedded Small/Pawn scripts await format documentation; execution would be
    a separate product and security decision.
  - EGI masks, segments, overlays, path maps, audio, labels, regions, postage
    stamps, and ancillary metadata need resource-model decisions and authentic
    controls.
  - Compatibility tolerance for documented malformed files requires authentic
    evidence.
  - Broader authentic coverage remains outstanding, especially true-colour,
    EGI, CEL, FLX/FLH/FLT, masks, segments, and audio.

- **Netpbm images**
  - Unknown or nonvisual PAM tuple types are structurally retained but cannot
    be rendered.
  - Automated compatibility coverage is currently synthetic.

- **Amiga Workbench icons**
  - Chained classic icon images are unsupported.
  - Broader authentic controls for classic, NewIcons, and GlowIcons variants
    remain desirable.
