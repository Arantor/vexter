# Third-party material

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
