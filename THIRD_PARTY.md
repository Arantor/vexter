# Third-party material

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
