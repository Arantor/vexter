# Third-party material

## ProTracker MOD documentation and compatibility corpus

The developer supplied `mod-form-3rd.txt` and
`Protracker Module Format - 4th edition.html` on 29 August 2026. The former was
obtained from `textfiles.com/programming/FORMATS/mod-form.txt`; the latter from
`aes.id.au/modformat.html`. Together they document the 15- and 31-instrument
headers, signatures and channel counts, order and pattern layouts, sample
encoding, periods, effects, timing, stereo placement, and repeat behavior used
by Vexter. No internet research or third-party implementation code was used.

Source URLs:
* http://www.textfiles.com/programming/FORMATS/mod-form.txt
* https://www.aes.id.au/modformat.html

The developer also supplied the files under `mod/` as temporary compatibility
material. They are not copied into the committed fixture corpus; routine tests
construct compact synthetic modules from the documented layouts. Seventeen
files exercise classic `M.K.` modules. `Worms - The Director's Cut.MOD` begins
with `MMD1` and is retained as a negative, OctaMED-family control rather than
being interpreted as a classic MOD.

The supplied documentation SHA-256 values are:

```text
051b9cc04a12a1e850ca86c35de7050e558bc887620d54300658bf8024204733  mod-form-3rd.txt
315486e2ffb43db7a73b20501e6d1f7fb49842d66bcf283fd7e4be4e489db269  Protracker Module Format - 4th edition.html
```

## Adobe Swatch Exchange article and sample

The developer supplied Richard Moss's 16 October 2015 Cyotek article,
`Reading Adobe Swatch Exchange (ase) files using C# - Articles and information on C# and .NET development topics • Cyotek.html`,
on 29 August 2026. It was obtained from
`cyotek.com/blog/reading-adobe-swatch-exchange-ase-files-using-csharp`.
The prose and layout tables—not the supplied C# implementation—define the
big-endian `ASEF` header, counted length-delimited blocks, names, colour-space
tags, float component counts, colour classifications, and skippable custom
data used by Vexter. The article explicitly declines to define CMYK, Lab, or
grayscale conversion, so Vexter does not infer those conversions.

The developer also supplied `resurrect-64.ase`, sourced from Lospec as the
Adobe Swatch Exchange companion to the Resurrect 64 palette. It establishes
the documented version 1.0 RGB representation and the colour-block identifier
needed to interpret the article's otherwise unnumbered block categories. Both
files remain temporary research and compatibility material and are not copied
into the committed fixture corpus; routine tests use compact synthetic data.

Their supplied-file SHA-256 values are:

```text
f8c64b38f96b0af70ac5828567d29300e1acb6a6c217e0d195fbb4effa18f9f3  Reading Adobe Swatch Exchange (ase) files using C# - Articles and information on C# and .NET development topics • Cyotek.html
f341d1ec5e605a347c6501bf9f3ef2b36852710331366e52e5acef142150b74d  resurrect-64.ase
```

## Aseprite file specification and EULA

The developer supplied `ase-file-specs.md` and `EULA.txt` on 29 August 2026.
The specification was obtained from Aseprite's public GitHub repository at
`github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md`; it defines the
little-endian `.ase`/`.aseprite` header, frame and chunk envelopes, palette
chunks, and the broader sprite structures used as the sole authority for
Vexter's implementation. The implementation was produced from this supplied
document without reverse engineering Aseprite software.

The developer supplied the EULA to record the terms associated with their
licensed Aseprite copy, purchased through Steam, and states that use of the
documentation forms part of the product under that licence. The specification
and Aseprite software are not redistributed as part of Vexter's committed
fixture corpus. The supplied EULA is reproduced below for notice and reference.
Routine tests construct compact synthetic files from the documented field
layouts.

Their supplied-file SHA-256 values are:

```text
31a6a80526c24209361fc35f9431bd8909603bb106bb6c3ed866f9af28976ae3  ase-file-specs.md
d80bd3c464d02d6fa3fce2347ca0ec7435a9a3265318b67bc4d2235bfd8fcbde  EULA.txt
```

### Aseprite End-User License Agreement

The following text is reproduced verbatim from the supplied `EULA.txt`:

```text
END-USER LICENSE AGREEMENT FOR ASEPRITE

IMPORTANT: PLEASE READ THE TERMS AND CONDITIONS OF THIS LICENSE AGREEMENT CAREFULLY BEFORE CONTINUING WITH THIS PROGRAM INSTALL.

This End-User License Agreement ("EULA") is a legal agreement between you (either an individual or a single entity) and Igara Studio S.A. (hereinafter referred to as "Licensor"), for the software product(s) identified above which may include associated software components, media, printed materials, and "online" or electronic documentation ("SOFTWARE PRODUCT"). By installing, copying, or otherwise using the SOFTWARE PRODUCT, you agree to be bound by the terms of this EULA. This license agreement represents the entire agreement concerning the program between You and the Licensor, and it supersedes any prior proposal, representation, or understanding between the parties. If you do not agree to the terms of this EULA, do not install or use the SOFTWARE PRODUCT.

The SOFTWARE PRODUCT is protected by copyright laws and international copyright treaties, as well as other intellectual property laws and treaties. The SOFTWARE PRODUCT is licensed, not sold.

1. GRANT OF LICENSE.
The SOFTWARE PRODUCT is licensed as follows:
(a) Installation and Use.
The Licensor grants you the right to install and use copies of the SOFTWARE PRODUCT on your computer running a validly licensed copy of the operating system for which the SOFTWARE PRODUCT was designed.
(b) Backup Copies.
You may also make copies of the SOFTWARE PRODUCT as may be necessary for backup and archival purposes.

2. DESCRIPTION OF OTHER RIGHTS AND LIMITATIONS.
(a) Maintenance of Copyright Notices.
You must not remove or alter any copyright notices on any and all copies of the SOFTWARE PRODUCT.
(b) Distribution.
You may not distribute copies of the SOFTWARE PRODUCT to third parties. Evaluation versions available for download from the Licensor's websites may be freely distributed.
(c) Prohibition on Reverse Engineering, Decompilation, and Disassembly.
You may not reverse engineer, decompile, or disassemble the SOFTWARE PRODUCT, except and only to the extent that such activity is expressly permitted by applicable law notwithstanding this limitation.
(d) Rental.
You may not rent, lease, or lend the SOFTWARE PRODUCT.
(e) Support Services.
The Licensor may provide you with support services related to the SOFTWARE PRODUCT ("Support Services"). Any supplemental software code provided to you as part of the Support Services shall be considered part of the SOFTWARE PRODUCT and subject to the terms and conditions of this EULA.
(f) Compliance with Applicable Laws.
You must comply with all applicable laws regarding use of the SOFTWARE PRODUCT.
(g) Source code.
You may only compile and modify the source code of the SOFTWARE PRODUCT for your own personal purpose or to propose a contribution to the SOFTWARE PRODUCT.

3. TERMINATION
Without prejudice to any other rights, the Licensor may terminate this EULA if you fail to comply with the terms and conditions of this EULA. In such event, you must destroy all copies of the SOFTWARE PRODUCT in your possession.

4. COPYRIGHT
All title, including but not limited to copyrights, in and to the SOFTWARE PRODUCT and any copies thereof are owned by the Licensor or its suppliers. All title and intellectual property rights in and to the content which may be accessed through use of the SOFTWARE PRODUCT is the property of the respective content owner and may be protected by applicable copyright or other intellectual property laws and treaties. This EULA grants you no rights to use such content. All rights not expressly granted are reserved by the Licensor.

5. NO WARRANTIES
The Licensor expressly disclaims any warranty for the SOFTWARE PRODUCT. The SOFTWARE PRODUCT is provided 'As Is' without any express or implied warranty of any kind, including but not limited to any warranties of merchantability, noninfringement, or fitness of a particular purpose. The Licensor does not warrant or assume responsibility for the accuracy or completeness of any information, text, graphics, links or other items contained within the SOFTWARE PRODUCT. The Licensor makes no warranties respecting any harm that may be caused by the transmission of a computer virus, worm, time bomb, logic bomb, or other such computer program. The Licensor further expressly disclaims any warranty or representation to Authorized Users or to any third party.

6. LIMITATION OF LIABILITY
In no event shall the Licensor be liable for any damages (including, without limitation, lost profits, business interruption, or lost information) rising out of 'Authorized Users' use of or inability to use the SOFTWARE PRODUCT, even if the Licensor has been advised of the possibility of such damages. In no event will the Licensor be liable for loss of data or for indirect, special, incidental, consequential (including lost profit), or other damages based in contract, tort or otherwise. The Licensor shall have no liability with respect to the content of the SOFTWARE PRODUCT or any part thereof, including but not limited to errors or omissions contained therein, libel, infringements of rights of publicity, privacy, trademark rights, business interruption, personal injury, loss of privacy, moral rights or the disclosure of confidential information.
```

## GIMP palette specification and sample

The developer supplied `gpl.md` and `resurrect-64.gpl` on 29 August 2026.
`gpl.md` is a Markdown copy of the GIMP team's GPL version 2 specification
from `developer.gimp.org/core/standards/gpl/`. It defines the magic line,
version-1/version-2 header distinction, UTF-8 text, optional display columns,
comments, and decimal RGB colour records used by the implementation.

The Resurrect 64 sample was sourced by the developer from Lospec's palette
catalogue and is retained as temporary compatibility material rather than
copied into the committed fixture corpus. Routine tests otherwise use compact
synthetic data.

Their supplied-file SHA-256 values are:

```text
653bcba6c1a4ed2c2572eed979b01e07f9bc049f2ce1d8c33320867b795a392b  gpl.md
793af3d1aa2305aed01faeeacaadbd57d6ebeb8995fe899e12f86f7b1bb39e71  resurrect-64.gpl
```

On 29 August 2026 the developer also supplied the Aseprite modification used
by Vexter: a `Channels: RGBA` header immediately after the magic or optional
name line changes body records from RGB to RGBA. This behavior is documented
as supplied compatibility knowledge rather than attributed to the GIMP GPL
specification.

The developer subsequently supplied `alpha-palette.gpl` as a compatibility
sample of that RGBA modification. It remains temporary working material and is
not part of the committed fixture corpus. Its SHA-256 is:

```text
0a88978f337429b10159ba48387b4724346677134694675b79c8aadd585df289  alpha-palette.gpl
```

## Lospec Paint.NET palette samples

The developer supplied `general.txt` and `resurrect-64.txt` on 28 August 2026.
Both identify themselves as Paint.NET palette files downloaded from
`Lospec.com/palette-list`. `general.txt` names the 69-colour General palette
and carries its author-supplied description; `resurrect-64.txt` names the
64-colour Resurrect 64 palette and has an empty description. They establish
case-insensitive ARGB entries, optional descriptive metadata, and real files
whose declared colour counts match their content.

The files give only the generic Lospec catalogue URL rather than stable
palette-specific provenance and state no redistribution licence. They remain
temporary compatibility material in the working directory and are not copied
into the committed fixture corpus. Routine tests use compact synthetic data.
Their supplied-file SHA-256 values are:

```text
55e30c8bfcafe6e14638dad418fbceeb6d6b16f8f52c24b42a7c66e819317b68  general.txt
cd805eadaaf5ff7f8991bfe57a401e731760958a4ea65dd5c46370b33ec1b606  resurrect-64.txt
```

## Creative Voice file Wikipedia capture

The developer supplied `Creative Voice file - Wikipedia.html` on 28 August
2026 from [Wikipedia](https://en.wikipedia.org/wiki/Creative_Voice_file). The
saved revision describes the 26-byte Creative Voice header, version checkword,
block framing, version-one PCM rate formula, continuation, silence, metadata,
and repeat block semantics used by the initial decoder. It does not define the
codec table or extended-block fields. Its SHA-256 is:

```text
9e5a2936f1816765c809994413262967ea64b676e4a5b8618b2a06f8c0bf1809  Creative Voice file - Wikipedia.html
```

The HTML capture is temporary research material and is not copied into routine
test fixtures. Tests construct compact synthetic Creative Voice streams.

## Creative Voice format notes

The developer supplied `vocform2.pro notes.txt` on 28 August 2026, sourced from
`http://www.textfiles.com/programming/FORMATS/vocform2.pro`. It records the
classic block layouts and names Creative's compression method numbers. The
developer also supplied `extended notes.txt`, sourced from the Internet
Archive's 20 March 2018 capture of SoX's `AudioFormats-11.html#ss11.5`. It
defines type-8 extended attributes and describes later type-9 blocks. These
temporary research files are not formal fixtures. Their SHA-256 values are:

```text
4a2e2a4be511895274789c5cb0bb1457438f2cc5018a6f506b8b095923249425  vocform2.pro notes.txt
76297a6033e93becc44f175ba3221f30f65d5b37946df9b35a6a6bfb2df73d05  extended notes.txt
```

The type-8 mono time-constant formula and pack method zero inform the maintained
extended PCM decoder. The compressed method names alone do not define their
ADPCM algorithms.

The developer subsequently supplied four temporary MultimediaWiki captures on
28 August 2026. `Creative 8 bits ADPCM - MultimediaWiki.html` defines Creative
codec IDs 1–3, including their predictor, adaptive step, and packed-code
layouts. `Creative Voice - MultimediaWiki.html` defines the VOC blocks,
channel-aware type-8 rate formula, type-9 fields, and broader codec ID table.
The linked `Creative ADPCM - MultimediaWiki.html` and `PCM -
MultimediaWiki.html` pages document codec `0x0200` and PCM conventions for
possible later type-9 support. Their SHA-256 values are:

```text
390b6218e09b4a86ddb34229aaf1b341b6c1ce3751c510b7b15e91ba1e70ef0f  Creative 8 bits ADPCM - MultimediaWiki.html
decdc086a1e1b2108ae518a6a217d957b6afdee8304305211e312a58e4e81ad0  Creative ADPCM - MultimediaWiki.html
a5bc62d2de32365f1ab0a91fe6197eb0bbc467c76b45c5758849540f785385c7  Creative Voice - MultimediaWiki.html
53672ae8c6ebe0d127fd23b07e8f9981bb418cdf6b1fe726eb02fda95d57be2d  PCM - MultimediaWiki.html
```

The codec IDs 1–3 decoder follows the supplied empirical algorithm as the
project's current format authority. The type-8 channel formula and type-9
layout support stereo codec-zero PCM and type-9 codec-zero/code-four PCM.
Stereo ADPCM and the other linked type-9 codecs remain unimplemented because
their stream-level rules are not fully established by the supplied captures.

## Unofficial DOOM Specs v1.666

The developer supplied `The Unofficial Doom Specs v1.666.html` on 27 August
2026 from [gamers.org](https://www.gamers.org/dhs/helpdocs/dmsp1666.html).
Matthew S. Fell's 15 December 1994 document is the format authority for the
classic IWAD/PWAD header and directory, PLAYPAL palettes, flat namespaces, and
column/post picture encoding, texture composition, and sampled sound-card
effects, classic map records, and automap line semantics used by the current
DOOM support. Its SHA-256 is:

```text
3a74e6ef7abd706d76cf47562eae11d17b8bf78bced033ee85dd5801bc424b9d  The Unofficial Doom Specs v1.666.html
```

The supplied HTML retains the document's copyright notice and restricted
redistribution terms. It is temporary research material and is not copied into
the repository. Routine tests construct small synthetic WADs and contain no
id Software game data.

## KoalaPainter specification, samples, and Colodore palette

The developer supplied a temporary unpacked copy of Massimiliano Scarano's
Koala DataType 39.4 for AmigaOS on 2026-08-25. It was obtained from the Aminet
package [`util/dtype/Koala_DataType_V39_4`](https://aminet.net/package/util/dtype/Koala_DataType_V39_4).
The package's AmigaGuide documents the 10,001-byte KoalaPainter payload layout;
its source establishes the leading two-byte `$6000` C64 load address, complete
10,003-byte file representation, bitmap traversal, selector meanings, and
hardware colour indices. Its 45 images are temporary authentic compatibility
subjects and are not copied into the repository fixture set. The guide states
that the datatype is E-mailware with no restrictions on distribution or use.

The developer separately supplied `colodore.txt`, a Paint.NET palette
downloaded from [Lospec's Colodore palette page](https://lospec.com/palette-list/colodore).
It identifies the palette as Colodore by Pepto and refers to Pepto's
[VIC-II colour work](https://www.pepto.de/projects/colorvic/). These exact ARGB
values are Vexter's KoalaPainter rendering palette. Since the Paint.NET file
groups the colours visually rather than by VIC-II register number, the values
are reordered into the hardware indices identified by the datatype's named
palette and decoder. The supplied palette file does not state separate licence
terms and is retained as temporary research material rather than copied into
the implementation or fixture tree.

Relevant supplied-file SHA-256 values are:

```text
7dcd6c9a6227ed110525edf62bf1918690877fe5fe28626e3a765fea9c137007  Koala_DataType.guide
8b14102cbd90c4b615f25c5d5f1b7c4c9b37e4c11f2108b9d0b932d64cdcb24c  Source/dispatch.c
83a9b56a7375675393096ff5ef7fde590495259343d311c1c3aa61f5fc4ee5f1  aminet_readme.txt
70a14461271c9e66b56d8fa5d3c3a240f897641b947ec6ac9d84e60a1fad0897  colodore.txt
48c4059bf6e6b178dfa46d6a87e684898af79ab2af794997c9ab85ee943ff441  Images/kla/amiga12.kla
b7e9e23c18a08ef177b6ded86dfeb9b3c44f79e2c25ef2160c335ee49ab7957d  Images/koa/garfield.koa
309943995ed6147c49a718daccca5b729e4d0fb9792593f9fc2ffb607a92e4e0  Images/no_extension/BUBBLE
40d96317a68fdf5301412846693cfaf0cdd1c4e3480502ec35633279e2b402ce  Images/prg/r-type.prg
```

## ISO 9660 reference

The developer supplied a local copy of Wikipedia's
[ISO 9660 article](https://en.wikipedia.org/wiki/ISO_9660) on 2026-08-24. It
is the initial reference for ISO 9660 volume descriptors, both-byte integer
fields, path tables, directory records, filename levels, and the relationships
to SUSP, Rock Ridge, Joliet, and raw CD-ROM data sectors. The downloaded page
identifies revision `1367156854` and links its text under CC BY-SA 4.0.

The accompanying `iso9660/` disc images are temporary compatibility inputs and
are deliberately neither catalogued nor committed. The reference-page hash is:

```text
a8573c6bc3939821513b0c7059bdf852b69502e432d7dd411d379299129ab1df  ISO 9660 - Wikipedia.html
```

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

## SAUCE 00.5 specification

The developer supplied `sauce/`, a checkout of Olivier "Tasmaniac" Reubens'
SAUCE (Standard Architecture for Universal Comment Extensions)
specification, sourced from
[the radman1 GitHub repository](https://github.com/radman1/sauce). The supplied
revision is `f72abdf242fb9cb791f4bd25dffedc2aab0cae7c` (2015-03-13).

The checkout's `README.md` and `sauce-00-5.htm` both contain revision 00.5 of
the specification. On 2026-08-23, the developer confirmed that this is the
same revision published by ACiD at
[its accompanying SAUCE specification page](https://www.acid.org/info/sauce/sauce.htm)
and that revision 00.5 is current at that time. These two sources are the
format authority for future SAUCE metadata handling, including record and
comment framing, field encodings, data/file classifications, type-dependent
information, and flags. Their ANSI and ANSiMation classifications may inform
format detection, but ANSI terminal-control semantics will require separately
supplied documentation and controls.

The checkout does not include an explicit licence file. Vexter treats it as
supplied specification material and does not copy substantial specification
text into the implementation or project documentation. Relevant hashes are:

```text
a2124dfa0076075692846fed238d92c017a1032265c89a4ffdd6d69e6e042ff4  README.md
322ad2fa4291d88334b702067b5f542ed8e458b85337f4e3fdb9b94050840cd4  sauce-00-5.htm
```

## OpenRaster 0.0.6 specification and temporary compatibility subject

The developer supplied the local, untracked `openraster/` research directory
with the Baseline Intent, File Layout, and Layer Stack pages of the OpenRaster
specification version 0.0.6 from
[openraster.org](https://www.openraster.org/), together with its RELAX NG
Compact schema. These local documents are the format authority for
OpenRaster's ZIP profile, required members, layer-stack vocabulary, and
baseline rendering model. They are implementation references only and are not
redistributed or committed to Vexter.

The accompanying `2018-11-28_coc.ora` is a temporary authentic compatibility
subject and is likewise excluded from version control. Its artwork is David
Revoy's *Pepper & Carrot* image for the project's Code of Conduct page circa
2018. The source was obtained from the ZIP linked by the
[archived Code of Conduct page](https://web.archive.org/web/20181130120539/https://www.peppercarrot.com/en/article455/our-code-of-conduct),
opened from the artist's original Krita document, and exported as OpenRaster.
The original work is licensed under the
[Creative Commons Attribution 4.0 International licence](https://creativecommons.org/licenses/by/4.0/).
Attribution is to David Revoy and *Pepper & Carrot*.

The resulting OpenRaster file has a 1912×1215 canvas, fourteen PNG layers,
nested and isolated stacks, hidden layers, offsets, opacity, and multiple
compositing operators. Its required `mergedimage.png` and 256×162 thumbnail
provide rendering controls. The document declares OpenRaster version 0.0.1
and uses stack offsets that are deprecated by version 0.0.6, making it useful
for testing version-compatible parsing. It may be used locally for format
research and compatibility testing, but must not be copied into Vexter's
fixture set.

Relevant SHA-256 hashes are:

```text
794873ee930364dbb1026df8535cf160f96b8b38dbe764acf0499f9ebd769cc9  Baseline Intent — Open Raster Specification version 0.0.6.html
2292af3394ac310acd786e4b58f306963739bb6ac7e54f0d8b5583245c73b2f1  File Layout Specification — Open Raster Specification version 0.0.6.html
e3991de55ec2933ee4466e10c9fef634dcacc3a271d200ba07f37689028a0595  Layer Stack Specification — Open Raster Specification version 0.0.6.html
6675b4e6d881d932c8072748159a79762218d495f30676551a113afe08a357c2  schema.rnc
fb59d839968f1ba91651f3888a997fe9563b18f9be277f8d4378702f477e9e3e  2018-11-28_coc.ora
```

## JPEG, JFIF, EXIF, and Independent JPEG Group references

The developer supplied the local, untracked `jpeg-10/` source distribution
from [the Independent JPEG Group](https://ijg.org/), originally distributed as
`jpegsr10.zip`. Its README identifies it as release 10 of 2026-01-25 and
copyright © 1991–2026 Thomas G. Lane and Guido Vollbeding. Vexter uses this
industrial implementation as an attributed behavioral and algorithmic
reference while porting JPEG decompression to native Nim; the C library is not
compiled, linked, or redistributed with Vexter.

As required by the supplied licence, Vexter documentation acknowledges that:

> this software is based in part on the work of the Independent JPEG Group

The distribution identifies the work of Tom Lane, Guido Vollbeding, Philip
Gladstone, Bill Allombert, Jim Boucher, Lee Crocker, Bob Friesenhahn, Ben
Jackson, John Korejwa, Julian Minguillon, Luis Ortiz, George Phillips, Davide
Rossi, Ge' Weijers, and other members of the Independent JPEG Group. The local
README contains the complete copyright, no-warranty, and use conditions and is
the licence authority for the port.

The developer also supplied `JPEG File Interchange Format - Wikipedia.html`,
sourced from [Wikipedia's JFIF article](https://en.wikipedia.org/wiki/JPEG_File_Interchange_Format),
as the local reference for JFIF marker layout, APP0 fields, density, thumbnails,
and Y/YCbCr interpretation. `Exif.php` and `ExifTag.php` are developer-authored
2014–2015 code supplied as prior practical research into JPEG APP1 discovery,
TIFF byte order, IFD entry framing, and EXIF orientation tag `0x0112`. They are
references only and are not incorporated as PHP or redistributed.

Relevant SHA-256 hashes are:

```text
9558ec9e705f74c3e4c0bc0063effd9e1434ac33b6551602c5f1b8fbdb00fa49  jpeg-10/README
0bdc0e108e92a0abd3e37262a230dd09ddb854b26c8a0bb61e723e90c2ff8d2b  JPEG File Interchange Format - Wikipedia.html
bebd171da0521564ce9301cc5a5b0295f53e4b6aa9f89d1116ce200d9adf8ba8  Exif.php
4c490f2f51a4379452091a9828c82b7b2f4a162c596ec2f53fd3b779ab62a2fd  ExifTag.php
```

## Temporary 16colo.rs ANSI and character-art compatibility controls

The developer supplied three artwork files and their PNG renderings from
[16colo.rs](https://16colo.rs/) on 2026-08-23:

- `BC-DEEP4.ART`, from the
  [art-r1 pack](https://16colo.rs/pack/art-r1/BC-DEEP4.ART), is an ANSI stream
  without SAUCE and ends with the DOS EOF byte;
- `HX-ICE.ICE`, from the
  [ice-9405 pack](https://16colo.rs/pack/ice-9405/HX-ICE.ICE), has a SAUCE 00.0
  record classifying it as an 80-column Character/ANSI file.
- `FLC0995.ANS`, subsequently supplied from the
  [flat0995 pack](https://16colo.rs/pack/flat0995/FLC0995.ANS), has a SAUCE
  00.0 record classifying it as an 80-column Character/ANSI file and exercises
  a substantially taller multi-artist logo collection.
- `SL-INC2.ANS`, subsequently supplied from the
  [ansis-s pack](https://16colo.rs/pack/ansis-s/SL-INC2.ANS), is a non-SAUCE
  ANSI stream whose final operation is cursor movement rather than a DOS EOF
  marker.
- `SK-BLUE.ANS`, subsequently supplied from the
  [anshelp pack](https://16colo.rs/pack/anshelp/SK-BLUE.ANS), is a non-SAUCE
  ANSI help document ending in CR/LF followed by a DOS EOF marker.
- `2E_gs.nfo`, subsequently supplied from the
  [bafh-pack6 pack](https://16colo.rs/pack/bafh-pack6/2E_gs.nfo), is plain
  72-column CP437 character art with CR/LF records, no ANSI escape sequences,
  and no SAUCE. It is both a negative ANSI-detection control and a future
  plain character-art rendering control.
- `us-arts.ans`, subsequently supplied from the
  [rmrs-56 pack](https://16colo.rs/pack/rmrs-56/us-arts.ans), is a non-SAUCE
  80-column ANSI stream whose 640-pixel-wide PNG establishes eight-pixel
  letter spacing. Its 2,784-pixel height is an exact multiple of the 16-pixel
  font height and establishes square-pixel presentation without legacy aspect
  correction. Together with the earlier non-SAUCE controls, it demonstrates
  that spacing and presentation aspect cannot always be inferred from the
  payload.
- `FILE_ID.DIZ`, subsequently supplied from the
  [ttnt-010 pack](https://16colo.rs/pack/ttnt-010/FILE_ID.DIZ), is a non-SAUCE
  ANSI stream despite its distribution-description extension. Its 296 by 688
  PNG establishes a tight 37-column canvas with 8x16 square-pixel rendering;
  applying its cursor-right commands gives the same 37-column written extent.

The accompanying PNGs are rendering controls from the same site. All are
720 pixels wide, demonstrating 80-column, nine-pixel-wide glyph rendering.
The developer established that 16colo.rs uses nine-pixel font rendering for
works made before 2000, including these controls, unless SAUCE indicates
otherwise, and explicitly applies legacy display-aspect correction. These
files may be used as temporary test subjects but must not be committed to
Vexter's fixture set.

```text
cadca202bbb57d6c86b5a2e8aac0c42880028ad7e630cdaca77cb6730f300287  BC-DEEP4.ART
9d8963790e017e7c7ae448c29774db589f28d3dce352bdb6dfc4c459ba6345e7  BC-DEEP4.ART.png
82be414bbcf3f4f8d1805dc4855ba8b90224b773a1c6072d511bc3a03f4b16d0  HX-ICE.ICE
24a025788c81e96c1e07257274930bd976d38e22eae23e19caa191f667eb2b13  HX-ICE.ICE.png
e45e95bf06d62513aeb7fcad4394228492e85d16e28dff6d94f8d45afd64e3dd  FLC0995.ANS
2d12c84b0c39b614cb1cbe1273114591defe9896d639b805237f7ab93dffa9a5  FLC0995.ANS.png
9140f154152640dfc0075aafc848965edb2632b6bf1f76f4a409730098f73832  SL-INC2.ANS
d40d07fcc18de5fbf7630356f59ba297233a75a6e3bd4cec06babd1e3946a006  SL-INC2.ANS.png
82feeae6db06508e021cd79971c9829830841e512938c9e97f3cca5aec6c03af  SK-BLUE.ANS
4e0e9154c85f6cb59d59afd8d54951b4e5ed34799bcf32a511044eae130a6f4f  SK-BLUE.ANS.png
58df1a0203262585a652e64842ae1a4a7e698765cc721fe5e5703d42c7b88527  2E_gs.nfo
2aba1dabe71b5a3a0a5d38ce8d2e7e6b1d3f7393544815bb873f60b2ec40ab81  2E_gs.nfo.png
a338d502cee2fe97492d2a7b2b31bd072ac58a442f919280b00c9d42caf04dbd  us-arts.ans
cd82c0e3f6dd13f8e6a41fd80ca76791eed989d8c1ea5774ee251df967a28bad  us-arts.ans.png
6a727604a561bcf59985d6aa2f16d665606368eda79de98ce5483bd2bd1d20ea  FILE_ID.DIZ
d330b41794ff8b67bab03b20fed887db8497dd3f6b8723443d21400fd3476103  FILE_ID.DIZ.png
```

## Ultimate Oldschool PC Font Pack

The developer supplied the complete `oldschool_pc_font_pack_v2.2_FULL/`
distribution from [int10h.org](https://int10h.org/) on 2026-08-23. Its README
identifies it as “The Ultimate Oldschool PC Font Pack” version 2.2, dated
2020-11-21, copyright 2016–2020 VileR. The pack is licensed under the Creative
Commons Attribution-ShareAlike 4.0 International licence; its complete licence
text is supplied as `LICENSE.TXT` in the package.

```

   The Ultimate Oldschool PC Font Pack is licensed under a Creative Commons
   Attribution-ShareAlike 4.0 International License.

   You should have received a copy of the license along with this work. If
   not, see < http://creativecommons.org/licenses/by-sa/4.0/ >.

                                                        (c) 2016-2020 VileR

```

The pack is the font authority for future PC text-mode and ANSI rendering. It
contains base CP437 and extended “Plus” variants in several formats and at
multiple authentic bitmap sizes. Byte-oriented ANSI input should use a base
CP437 face; extended variants may be useful for later Unicode-facing features
but do not redefine the source byte mapping. Any font or derived glyph data
redistributed with Vexter must retain attribution to VileR and int10h.org, the
CC BY-SA 4.0 licence and its required notices, and an indication of any
modifications.

For the two temporary 16colo.rs controls above, the base CP437 IBM VGA 9x16
strike is the initial reference face. Equivalent `.FON` and `.otb` copies are
available; implementation may mechanically extract the same bitmap glyphs
into a compact native asset. Relevant hashes are:

```text
9348ddfd44da5a127c59141981954746a860ec8e03e0412cf3af7134af0f97e2  LICENSE.TXT
02c3ff012a36c9c220678a515998ebea8b7cbe053d7e1c45003019f01d70b83e  README.TXT
5d90f6bc6f415288aa0d028bf3f2109e2ae22677aab4c928e722ad2e4be9626d  Bm437_IBM_VGA_9x16.FON
995baf3be9fe1a71cc2ce270a3cf7b9d97c707664c2ee86c8094392026d32755  Bm437_IBM_VGA_9x16.otb
90e4ae6c6f8bd41d88df53f5c3e0755e483229aac4f64bed883a6c51909ae8fe  embedded IBM VGA 9x16 CP437 glyph data
```

## ANSI escape-sequence reference

The developer supplied `ANSI.md` on 2026-08-23, sourced from
[fnky's ANSI escape-sequence reference](https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797).
It is the initial control-sequence authority for Vexter's ANSI art support,
covering general ASCII controls, cursor positioning and movement, erasure,
SGR attributes and colours, save/restore operations, and ANSI.SYS screen
modes. Vexter will implement only the bounded, non-interactive subset relevant
to inspection and rendering; device reports, keyboard redefinition, and other
host interaction must never be executed.

The supplied document has no explicit licence notice. It is retained as
developer-supplied research material rather than copied into implementation
documentation. Its hash is:

```text
c6d3202759082f5909c377d411d299826f7f6e62aa722b50b2f2731a7b919200  ANSI.md
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
