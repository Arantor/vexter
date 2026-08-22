# Third-party material

## IFFSpecs bundle Hunk reference

The developer-supplied `IFFSpecs.lzh` bundle from Aminet is documented with
its hash and public-domain source notice under the ANIM section of
`docs/formats.md`. Its unpacked `EXAMPLES/PGTB/tbsym.c`, authored by The
Software Distillery and made available to the Amiga development community,
defines the classic Hunk record identifiers and demonstrates the framing used
to skip load-file headers, CODE, DATA, BSS, relocation, symbol, debug, and END
records. Vexter uses that file only as the supplied structural reference for
its deliberately narrow executable recognizer. The source itself declines to
interpret overlays; Vexter retains the length-delimited overlay observed in
the supplied `lha.run` control without assigning execution semantics to it.

## jslha LHA/LH5 reference

`jslha/` is a developer-supplied checkout of Jani Poikela's jslha, sourced
from [its upstream GitHub repository](https://github.com/jpoikela/jslha). The
supplied revision is `40b09291bcd8ff722200fc3fd35fa84d06b5ac5d` (2018).

The project is MIT licensed; its complete licence and copyright notice are in
`jslha/LICENSE`. Vexter's native Nim LH5 decoder ports the table construction,
block decoding, history-copy, and method configuration behavior from
`lib/new_decoder.js`, `lib/tree.js`, and `lib/decoder.js`. Compatibility was
checked against authentic Aminet LHA archives and independent 7-Zip output.

The required MIT notice follows:

> MIT License
>
> Copyright (c) 2018 Jani Poikela
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Ancient Format Decompressor XPK/SHRI and PowerPacker reference

`ancient_format_decompressor/` is a developer-supplied checkout of Teemu
Suutari's Ancient Format Decompressor, sourced from
[the upstream GitHub repository](https://github.com/bsoja/ancient_format_decompressor).
The supplied revision is
`52b911ae52162f0ef19da0264275906590e0db9e` (2017-09-10).

Contrary to the initially stated MIT licence, the checkout's `LICENSE` file is
the BSD 2-Clause License and identifies Teemu Suutari as copyright holder from
2017. Vexter's Nim XPK framing, SHRI arithmetic/LZ, and standalone PowerPacker
implementations are ports of the behavior in `XPKMaster.cpp`,
`SHRIDecompressor.cpp`, and `PPDecompressor.cpp`; the C++ project is not
compiled or linked into Vexter. The required copyright and licence notice must
accompany redistributed source and binary forms.

```text
BSD 2-Clause License

Copyright (c) 2017, Teemu Suutari
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Relevant supplied-file SHA-256 values are:

```text
cf4eed95a3c433612fefad68939848f2bd19f549f5addc569815de846d8859cb  LICENSE
4a3e1f9a5d2d5865e96226fbee91d1debc4c8539171017eb433b9a2c58ff0937  XPKMaster.cpp
c5d51efdaaad9e62eaa502759a598e1a2e914a948b718a77ee8e8b712842d690  SHRIDecompressor.cpp
ae95d6f8ec499723625553e7b11b799c0f44c8bf11c476cfcf604d4c38e5bc94  PPDecompressor.cpp
508203f9f0309a740eee5217f8509783fdceebb34344874599212caea6ada912  PPDecompressor.hpp
```

## FLIC family format specification

The developer supplied `The FLIC file format.html`, sourced from
[CompuPhase's FLIC format page](https://www.compuphase.com/flic.htm) on
2026-08-21. The page is copyright Thiadmer Riemersma and identifies itself as
licensed under Creative Commons Attribution-ShareAlike 3.0. It documents FLI,
FLC, CEL, FLH, FLT, both FLX variants, DTA chunks, Pro Motion timing, and EGI
container/chunk extensions.

The page delegates Huffman/BWT coding, frame-shift application, one-bit DTA
pixel packing, and embedded Small/Pawn bytecode to separate documents. The
later-supplied EGI compression page below closes the first two gaps. One-bit
DTA packing and Small/Pawn bytecode remain unspecified, and Vexter does not
infer those missing rules. The FLIC page's SHA-256 hash is:

```text
80cdd87e88495edb1df7732550e3fe19d696b618e1134fd665e7d1d11d5a190a  The FLIC file format.html
```

The developer subsequently supplied `EGI compression schemes.html`, sourced
from [CompuPhase's EGI compression page](https://www.compuphase.com/compress.htm)
on 2026-08-22. It defines EGI Huffman and BWT-Huffman blocks, lazy
move-to-front reversal, and frame-shift application. Its SHA-256 hash is:

```text
6f97180e24e2828c9d2886ec8aa3594f0c9a3a2f69aca76d1a88a26dbc323ee5  EGI compression schemes.html
```

## FZX standard distribution

The developer temporarily supplied the unpacked standard FZX distribution,
sourced from
[Spectrum Computing](https://spectrumcomputing.co.uk/index.php?cat=96&id=28171)
and retrieved on 22 August 2026. The FZX format and supplied distribution are
copyright Andrew S. Owen.

The included `FZX.txt` identifies FZX v1.0 as a royalty-free open standard. It
permits use for designing and distributing fonts and in programs, including
commercial releases, provided the standard is followed without incompatible
irregular changes. Vexter uses that document as its format authority and the
41 packaged fonts as temporary compatibility controls. The distribution is not
retained in the repository. Its individual font text files carried their own
attribution and copyright notices; no font artwork is redistributed by Vexter.

Selected SHA-256 values from the supplied distribution were:

```text
8cd6d7ff6d0656465ac976b50d2b322a6d17bc649fe2cd1e57ea80be450e1345  FZX.txt
49d06f615d4cc3f7b70c27b8af6a467e0dcb1754880fe59221c9b5ae01fcd5b0  FZX.png
8dcb836d04b738ee654c47c7b9a6189030366730c03c3def9c8d33816bdc0842  fonts/Sinclair.fzx
be62cf1d63c8c31ff5db90a19857ceecfff484e1e7d431290e0221ce5fcfe2f2  fonts/GenevaMono/GenevaMonoCyrillic.fzx
```

## TGA format specification

The developer supplied `TGA format specification.html`, sourced from
[Paul Bourke's TGA format page](http://www.paulbourke.net/dataformats/tga/) on
2026-08-21. It is the format authority for Vexter's TGA header, colour-map,
pixel, origin, attribute, and RLE packet handling. The page links to a C example
whose licence is unspecified; that example was neither supplied nor used.

```text
96938c23b053f89c74fd73251d103024891a1aba1947b25a8097e5ad80962908  TGA format specification.html
```

## IFF PBM developer-supplied format details

The developer directly established that IFF PBM uses the `FORM PBM ` form
type, contains one non-interleaved plane, and stores pixels in eight-bit chunky
form. This is the authority for the initial importer. Word-aligned rows,
eight-bit BMHD depth, raw/ByteRun1 row framing, and applicable masking modes are
provisional implementation assumptions pending authentic test files or fuller
documentation; they are identified as such in format documentation and tests.

## Netpbm format specifications

The developer supplied HTML copies of the Netpbm project's PBM, PGM, PPM, and
PAM format documentation, sourced from
[the Netpbm documentation site](https://netpbm.sourceforge.net/doc/). The PBM,
PGM, and PPM copies are dated 2025-11-07; the PAM copy is dated 2013-11-27.
Together they define Netpbm variants P1 through P7 and are the authority for
Vexter's magic, comment, whitespace, sample, sequence, PAM-header, and visual
tuple-type behavior. They do not describe the unrelated Amiga IFF `FORM PBM `
format.

```text
b56089e0c386e2cc43e44a8124569185b7b1db863daed19da27c3045ca64e9d9  The PBM Format.html
b9c11d3613c1953e5e77e93ef4c0f4a010cd55138e1c4710a14e913f0f38f3de  PGM Format Specification.html
d029cd9c665322af35f94f77097aa0c6f02829ce8a9e5ffb1bcd3abbdd3a3805  PPM Format Specification.html
a5616fea88fdfc2a635f7188043574bcf50d7f360f08d9332084b57837dda8bb  PAM format specification.html
```

## QOI specification and temporary compatibility set

The developer supplied `qoi-specification.pdf`, “The Quite OK Image Format”,
Specification Version 1.0 dated 2022-01-05, from the QOI specification website.
It is the format authority for QOI header, chunk, hash, wraparound, and end
marker behavior. Its SHA-256 hash is:

```text
e9389266f56db4e1614810f2a0003e85e11a5dd3c5e46b7ccc09bcfee8b17a42  qoi-specification.pdf
```

The developer also temporarily supplied the QOI website test image set with
reference PNG copies. Vexter decoded all eight QOI images pixel-for-pixel,
including alpha, against those controls. The files are not retained as project
fixtures. Their supplied QOI hashes are:

```text
b05a622813eff15ce64f33ab76eee3f9d144f5cf24386e13ddf17c27f6310a01  dice.qoi
3cae50b533fbc796171a0763c29a576eaac475d04b6a95fe46b02d440f609e11  edgecase.qoi
e330cc81299a2641386f32bdf4b7070b8d5f8f2f76d899ced389b5a1469e65b0  kodim10.qoi
d225e987dc07262be2acee5dee164b5f48d3a49dd0e03f426b3111b52f265548  kodim23.qoi
e6519746939c2b6bc6776a65ce87b1dbd769069c2d2c11295453e9f35160ba57  qoi_logo.qoi
de309646439d2e49c51d9921eb1faff9af4cb33f0019a24ccb57dce1ef00dbab  testcard.qoi
b284ed810a892bca34e89a956b7f8bf21afae4826197a8f3eaef90e470e2149e  testcard_rgba.qoi
a289c12cd96cc3ff65fcafa1a6d55c5cace0095a45bc570ca1a4d8b79a20b4df  wikipedia_008.qoi
```

## DMS header specification

The developer supplied `DMS.txt`, titled “DMS HEADER STRUCTURE v1.01” and
sourced from [Laurent Clévy's Amiga documentation site](http://lclevy.free.fr/amiga/DMS.txt),
temporarily as the format source for DMS information and track-header framing.
It documents the fields, flags, compression-mode identifiers, and record sizes,
but does not document CRC calculation or compression bitstreams. At that stage
no authentic DMS archive fixture had been supplied. Its redistribution status
is unknown, so the temporary document is not part of the implementation.

```text
0a2b277f3a54a76d4de7301131e2c2b92a026a098f12301637d89a94502c43ec  DMS.txt
```

`Frustration.dms`, `HolyGrail.dms`, and `GoldenFleece.dms` were subsequently
supplied from a public-domain archive. The precise archive name and acquisition
URL have not been supplied. They are retained as authentic HEAVY2 reference
files and establish zero-valued post-identifier header bytes, 80-track
framing, detection, HEAVY2 reconstruction, and OFS traversal. Vexter output was
compared byte-for-byte with xDMS 1.3.5 output; the resulting ADF hashes are:

```text
bf0680b1fdfc128a67db55e420011c39c8f1282b5776ecc5910eef9d734b913c  Frustration.dms
47d3e86030aa536ad1af3cce823293b6478bbf911e52a8106e4c25786e1d957a  HolyGrail.dms
40305a448561194790fe1e1b66d0a2d36f8a34078b0a73745acbe58808d2122d  GoldenFleece.dms
3f02b65c2314b6a8abf3f2789b166ca1afccbe1cf428ef31f2661c1b4e7d7ac6  Frustration.adf
58382f5dc9ac17f572196556869064b194342868daa2186009f587936f19b0e5  HolyGrail.adf
53a971729fa34e42708a94ceb79a6ce76ab311e5f2aec060135b4b287891b505  GoldenFleece.adf
```

## xDMS reference implementation

`xdms/` is a user-supplied checkout of the original xDMS portable DMS archive
unpacker from [Heikki Orsila's xDMS repository](https://gitlab.com/heikkiorsila/xdms).
The supplied checkout identifies its origin as that repository and is at commit
`714ab57d3d73b3174c62396a14d17a27d35c9fc2` (2026-07-23). It is retained as
reference material for DMS CRC/checksum behavior, encryption, track-state
handling, and the RLE, QUICK, MEDIUM, DEEP, and HEAVY decompression modes.

The bundled `COPYING` and `README.md` declare xDMS to be public-domain
software. The README credits André Rodrigues de la Rocha as the original
author/maintainer and Heikki Orsila as the new maintainer. It also records that
the HEAVY routines are based on static-LZH routines from Masaru Oki's Unix LHA,
the DEEP routines are based on Haruyasu Yoshizaki's LZHUF, and initial header
and CRC information came from Bjorn Stenberg's `testdms`. Those upstream
acknowledgements must remain visible when corresponding behavior informs the
Vexter implementation.

Vexter does not compile or link xDMS, and the supplied C source is not copied
verbatim into the Nim implementation. Its CRC-16/ARC, byte-sum, RLE, static
Huffman/LZ HEAVY1/HEAVY2, and cross-track reset behavior informed the Nim DMS
decoder. Tests and format documentation identify xDMS as that source.

## IFF 16SV reference package

`16sv_datatype/` is Roland Mainz's 16sv.datatype V1.2 package. It includes
documentation, source, Amiga binaries, and the `Bluebird.16sv` compatibility
fixture. The supplied documentation describes it as the official
datatypes.library V45 reference implementation and permits noncommercial
redistribution only when the package remains complete; commercial
redistribution requires the author's permission. Vexter uses the documentation
and source as format evidence and `Bluebird.16sv` to validate 16-bit sample
counting, byte order, playback rate, and WAV output.

Relevant SHA-256 hashes:

```text
826ba6f483b3894eae7cfa24db8128a99645b13e5b628d504706c83d64df4e11  16sv.datatype.doc
c7c4a85061e6453542129f8ca44040eda962e0c3da41127d9fe9f89cdc3b72a9  dispatch.c
ccb4f0f1ae28e2f3b304c6b6e88eab38e91a75f0eceadd7a9b0bac74cfe91522  Bluebird.16sv
```

## Amiga bitmap diskfont documentation and compatibility collection

The developer supplied `Graphics Library and Text - AmigaOS Documentation
Wiki.html`, an excerpt saved from the [AmigaOS wiki](https://wiki.amigaos.net/wiki/Graphics_Library_and_Text)
on 22 August 2026. Its TextFont, ColorTextFont, FontContentsHeader, and
DiskFontHeader descriptions informed the bitmap diskfont implementation.

The developer also supplied a copy of their Amiga `Fonts` folder as temporary
compatibility evidence. Its 117 loadable bitmap size descriptors were used to
check monochrome and ColorFont parsing; Agfa Compugraphic outline material was
ignored. Neither the documentation excerpt nor the font collection is
redistributed as a Vexter test fixture.

```text
35df2062557d81ebe497f85fcc50ae988f1c911005dcb796b5300acdf18a6c6c  Graphics Library and Text - AmigaOS Documentation Wiki.html
```

## BMFont compatibility collection

The developer supplied `bmfonts/` from the AngelCode Bitmap Font Generator
sample distributed at <https://www.angelcode.com/dev/bmfonts/>. The collection
contains text and binary-version-3 descriptors, packed RGBA atlas pages, and
the sample `font.fx` channel/outline shader. It is used temporarily to validate
binary blocks, Unicode IDs, signed metrics, kerning, companion-page resolution,
and per-glyph channel selection. It is not copied into the routine fixtures.

Relevant SHA-256 hashes:

```text
f4f3f9c9cbb08e9ba066e319c2e58871bc428ed77d39022d55f89a976d1d6cf1  arial24.fnt
d73216ae1ca3560737e6fcd8336930d9248e926dee0bcba6a88861dd50b772fa  arial24_00.png
68e71784f5d0d1068cb56e59cb74531a9468e1ce887e67502aa72c0f160fb2f1  chinese.fnt
fba8034512000059ca15deba482d071465c65bf9b2f54f06a61cb612328967cb  chinese_00.png
4d3d288380a7710e4658222441154a9ba6b604d49f996bc79930e19914bfc626  comic10.fnt
a743acd6c89509626e6f2522e695b010492f05825df2eda015b6e3c5b97d0dfc  comic10_00.png
cba9a703474980f1b04f80097d9249546f15614c0355bb94113b5772e17efbf0  comic24.fnt
8f01891ae6b3b05985d69d868f7948d5f81bc152e024856ed929fd38495df76a  comic24_00.png
34eae5a5de5a91d1a1de5498612bcc2db7170af3702cd1a6c38abdb91033b565  font.fx
```

## AMOS sprite-bank fixture

`tests/fixtures/amos.sprite-bank/DRAGON.Abk` is part of the “Sprites 600” demo
included with AMOS The Compiler, originally by Mandarin Software. It is kept
as a compatibility fixture for parsing and rendering AMOS sprite banks.
Its redistribution or licensing status has not yet been supplied and should
be confirmed before distributing the fixture outside this development context.

The accompanying `DRAGON.gif` is an independently generated rendering control.

## Castle AMOS packed-picture fixture

`tests/fixtures/amos.pacpic/Castle_AMOS.Abk` is a `Pac.Pic.` picture bank from
“Castle AMOS”, one of the demo games bundled with AMOS. It is retained to
validate packed-picture header parsing, two-stage RLE decompression, planar
rendering, and palette conversion. Its redistribution or licensing status has
not yet been supplied and should be confirmed before distributing the fixture
outside this development context.

`Castle_AMOS.png` is the supplied rendering control.

## Deluxe Paint King Tutenkhamen ILBM fixture

`tests/fixtures/amiga.ilbm/KingTut.LoRes` contains the King Tutenkhamen cover
art drawn by Avril Harrison in 1985 for Electronic Arts and associated with
Deluxe Paint. It is retained as a compatibility fixture for IFF/ILBM parsing,
ByteRun1 decompression, planar rendering, and legacy four-bit palette scaling.
Its redistribution or licensing status has not yet been supplied and should
be confirmed before distributing the fixture outside this development context.

`KingTut.png` is an ImageMagick conversion retained as a rendering control.

`tests/fixtures/amiga.ilbm/AquariumBackground.Ham`, `TutGallery.Ham`, and
`EAWorld.Ham8` are sample images shipped with Deluxe Paint 4.5 AGA, copyright
Electronic Arts 1992. Their accompanying PNG files are independent rendering
controls created with ImageMagick. They are retained to validate HAM6 and HAM8
true-colour reconstruction. Their redistribution or licensing status has not
yet been supplied and should be confirmed before distribution outside this
development context.

## TheTour IFF ANIM fixture

`tests/fixtures/amiga.anim/TheTour.anim` and its GIF rendering control are
retained to validate method-5 delta reconstruction and conventional ANIM loop
frames. `TheTour.anim` is bundled with Deluxe Paint and is copyright Electronic
Arts, consistent with the other supplied Deluxe Paint samples. Its precise
redistribution or licensing status has not yet been supplied and should be
established before distribution outside this development context.

## AMOS program fixture

`tests/fixtures/amos.program/Xerxes' Revenge.AMOS` is an AMOS Basic demo
program created by Peter J. Hickman and shipped with AMOS. It is retained as a
compatibility fixture for tokenised program boundaries and attached banks.
Its redistribution or licensing status has not yet been supplied and should
be confirmed before distributing the fixture outside this development context.
