# Outstanding work

This is the single concise index of known gaps in Vexter's implemented
behavior and in formats it already recognizes. It is not a roadmap: an item
being listed does not imply priority, and unsupported historical or proposed
formats are not included. Detailed format behavior and evidence remain in
[`formats.md`](formats.md).

- **Container loading and resource materialization**
  - The current mixture of eager tree construction, bounded recursive probing,
    and payload extraction on first selection does not yet form a satisfactory
    loading model across archives and filesystems.
  - Pathological but valid inputs can make either eager work or later
    selection disproportionately expensive. A concrete motivating case is a
    1.4 GB ZIP containing roughly 1,300 large images.
  - The unresolved design needs to cover lazy directory enumeration, nested
    format detection, decoded-resource lifetime and memory pressure,
    cancellation, progress, caching or eviction, bulk operations, and
    predictable CLI and GUI behavior. No replacement design has been chosen;
    this is deliberately deferred rather than treated as an implementation
    task.

- **GUI regression coverage for incremental inspection**
  - Define a regression matrix for transitions where a session initially
    exposes a generic descriptor and materialization later changes what the
    GUI knows about the resource. Cover decoded media and text, nested
    containers or groups, suspected-format decode failures, lazily enumerated
    children, single and multiple decoded roots, working-limit decisions,
    repeated selection or expansion, and replacing or closing a session while
    work is pending.
  - Extract the platform-neutral presentation decisions from the Win32 client
    so automated tests can verify the resulting label, warning state,
    metadata, expandability, preview kind, and available/default export
    formats without driving native controls.
  - Keep small deterministic synthetic fixtures in the repository for state
    transitions and boundary cases. Large archive and filesystem scenarios
    must not require multi-gigabyte fixtures in Git; investigate sparse or
    generated inputs, fixture recipes, and separately acquired CI artifacts
    when a CI environment is designed.
  - A private compatibility corpus may eventually be exercised by an optional
    local or protected-CI harness, but it is not a prerequisite for the
    checked-in suite and its acquisition, provenance, and automation are a
    separate piece of work.
  - Retain a short native-Windows pre-release smoke test for message-loop,
    worker-thread, common-control, visual, scrolling, progress, error-dialog,
    and export integration that cannot be established by the platform-neutral
    suite. Document its representative inputs and expected observations once
    suitable resources are available.

- **GUI raster-preview resampling**
  - Raster previews currently use nearest-neighbour-style scaling. This is the
    desired default when enlarging legacy pixel art, but large images scaled
    down to fit the preview can lose thin features or appear broken; WAD map
    previews are a concrete example.
  - Add direction-aware resampling choices. Investigate bicubic resampling as
    the initial higher-quality default for downscaling, retain nearest-neighbour
    enlargement as the default for legacy pixel material, and allow other
    upscaling or downscaling methods to be selected where useful.
  - Keep resampling a GUI presentation decision: changing preview quality must
    not alter decoded rasters or exported source-resolution content. Define
    expected behaviour for animation, alpha, indexed images, very large
    previews, and repeated repainting before choosing an implementation.

- **DOS ANSI art**
  - ANSiMation currently yields only its final static terminal state; no source
    timing convention has yet been supplied.
  - Additional local controls show that 16colo.rs canvas-tail cropping varies
    between artworks. The first two provenance-recorded controls match their
    reference dimensions, while `FLC0995.ANS` differs by one logical trailing
    row and `SL-INC2.ANS` by two rows before the confirmed aspect correction is
    applied; `SK-BLUE.ANS` differs by four rows under the same provisional
    policy. Cropping strictly to the last written row matches `SK-BLUE.ANS` but
    breaks the other controls, so a broader rule needs documentary evidence
    before becoming a compatibility contract.
  - Modern 256-colour/true-colour SGR, interactive device operations, keyboard
    redefinition, and unsupported private modes are intentionally absent.
  - Plain CP437 art is deliberately not classified as ANSI. The supplied
    `2E_gs.nfo` control can support a future distinct character-art handler,
    including non-80-column width inference, but that type is not yet
    implemented.
  - Non-SAUCE canvas width can also vary. `FILE_ID.DIZ` requires a tight
    37-column canvas while conventional ANSI art assumes 80 columns. Add an
    `auto|N` width interpretation option with carefully bounded extent
    inference; do not infer width from `.DIZ` or other filenames.

- **Classic DOOM WAD resources**
  - Add sprite-family grouping, mirrored rotations, and an explicit animation
    timing policy before offering coalesced GIF/APNG export.
  - PC-speaker `DP*` synthesis, MUS event streams, `GENMIDI`, and `DMXGUS` need
    separate transformation, format, and representation decisions.
  - Design an explicit base-IWAD companion mechanism for partial PWADs rather
    than searching for or silently assuming game data.

- **OpenRaster**
  - The canonical `mergedimage.png` is exposed directly; Vexter does not yet
    recomposite the layer stack or compare its rendering with that image.
  - Blend operators, isolated groups, opacity, visibility, and offsets are
    retained as metadata but are not applied by a native compositor.
  - Non-PNG layer source encodings are retained as opaque reusable data rather
    than decoded.
  - Application-specific extensions and archival-intent features are not yet
    interpreted.

- **JPEG**
  - Progressive, lossless, arithmetic-coded, hierarchical, and multi-scan
    sequential JPEG processes are recognized only as unsupported or rejected;
    the native decoder currently handles one baseline or extended-sequential
    Huffman scan.
  - Four-component CMYK/YCCK images and uncommon component interpretations are
    unsupported. Three components are currently interpreted as YCbCr.
  - Chroma upsampling is nearest-neighbour, and ICC profiles, EXIF fields other
    than the standard bounded TIFF directories and values currently exposed,
    XMP, vendor MakerNote semantics, embedded thumbnails, and other application
    metadata are not interpreted.

- **Palette interchange**
  - Ordered palettes can currently be exported as PNG swatches and exact
    metadata JSON. GIMP GPL, Aseprite's alpha-bearing GPL modification,
    Paint.NET text palettes, and Adobe Swatch Exchange RGB palettes are
    supported as input. GIMP GPL exports standard RGB or Aseprite RGBA
    automatically; Paint.NET and Adobe ASE are not export formats. Adobe ASE
    CMYK, Lab, and grayscale conversion needs supplied authoritative rules.
  - Brilliance `DRNG` and `BRNG` chunks in palette-only IFF files are not yet
    interpreted. Their accompanying `CMAP` colours remain available, but the
    additional range definitions require documentation and focused controls.

- **ProTracker-compatible MOD**
  - The bounded stereo replay does not yet emulate the Amiga low-pass filter,
    tremolo, glissando, selectable modulation waveforms, or invert-loop, and
    it uses a complete in-memory PCM mix rather than streaming. The GUI has no
    live playback cursor.
  - The bounded control-flow analysis covers documented ProTracker jumps,
    breaks, pattern loops, and restart behavior but is not a substitute for
    full tick-by-tick effect replay.
  - `MMD1`/OctaMED modules are a separate unsupported family; the supplied
    Worms module requires authoritative format documentation before work can
    begin.

- **Aseprite sprites**
  - File, frame, and chunk structure plus old and current palette chunks are
    recognized. Layer/cel compositing, linked and compressed cels, blend modes,
    tilemaps and tilesets, animation tags, slices, profiles, masks, external
    files, and structured user data remain to be decoded from the supplied
    specification.
- **Amiga Hunk executables and LHA self-extractors**
  - Broader Hunk record and executable-variant coverage needs a supplied Hunk
    specification and authentic controls.
  - Relocations, symbols, debug records, overlays, memory flags, resident
    names, and execution semantics are only framed or retained, not interpreted.
  - Other self-extractor layouts and executable stubs are not recognized.

- **Amiga bitmap diskfonts and ColorFonts**
  - Positions outside printable ASCII remain source indices until an explicit
    Amiga or font-specific character mapping is supplied.

- **BMFont**
  - Declared non-Unicode charsets are retained but positions beyond printable
    ASCII need charset-specific mapping tables and representative controls.
  - Common channel-role combinations beyond explicit single-channel masks and
    the documented packed-outline threshold need representative controls.

- **PNG, APNG, and GIF export optimization**
  - Current outputs prioritize deterministic correctness and use simple
    lossless encoding rather than size-optimized filtering, compression,
    palette construction, or animation-frame differencing.
  - Embedded HTML-report media consequently remains larger than necessary,
    even when browsers scale its presentation.

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

- **Creative Voice audio**
  - Codec-zero unsigned eight-bit PCM supports version-one mono and type-8
    mono/stereo streams. Creative codec IDs 1–3 support mono type-1/type-2 and
    type-8 streams, including finite stateful repeats. Type-9 supports mono or
    stereo codec-zero eight-bit PCM and codec-four signed sixteen-bit PCM.
  - Type-8 stereo ADPCM remains unsupported because per-channel predictor
    initialization, state, and packed-code assignment are not documented.
  - Type-9 codecs 1–3 remain unsupported because the supplied page does not
    explicitly establish that their older reference-byte framing carries into
    new-format blocks. A-law (6) and mu-law (7) lack supplied conversion rules.
    Creative codec `0x0200` lacks initialization, nibble-order, reset, and
    multichannel details.
  - More than two type-9 channels, midstream sample-rate/width/channel changes,
    and infinite-repeat material need explicit product behavior or broader
    archetype support rather than further container-field research.
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

- **Commodore 64 KoalaPainter images**
  - Authentic supplied samples are temporary compatibility controls rather
    than committed fixtures; routine automated coverage is synthetic.

- **Amiga Workbench icons**
  - Chained classic icon images are unsupported.
  - Broader authentic controls for classic, NewIcons, and GlowIcons variants
    remain desirable.
- **ISO 9660**
  - Add Joliet and SUSP/Rock Ridge naming and metadata, multi-extent files,
    path-table cross-checking, and broader descriptor semantics.
  - Consider Mode 2 and other CD-sector layouts plus EDC/ECC verification;
    audio tracks and other Rainbow Book filesystems remain outside this base.
  - Demand decoding currently occurs synchronously on first GUI selection.
    This is one instance of the unresolved cross-container loading design
    above; its eventual behavior should not be specified independently here.
