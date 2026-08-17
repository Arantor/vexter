# Amiga ILBM fixtures

`KingTut.LoRes` is a 320×200, five-bitplane, ByteRun1-compressed ILBM image.
`KingTut.png` is an ImageMagick conversion used as a pixel-layout control.
The PNG retains legacy CMAP components as multiples of 16; Vexter follows the
IFF guidance and replicates each four-bit component into the low nibble, so
tests normalize the control from `$x0` to `$xx` before comparing expanded RGB.

The artwork is the King Tutenkhamen Deluxe Paint cover image drawn by Avril
Harrison for Electronic Arts in 1985. See the repository `THIRD_PARTY.md` for
provenance and redistribution cautions.

`TutGallery.Ham` and `EAWorld.Ham8` are 640×400 HAM sample images shipped with
Deluxe Paint 4.5 AGA, copyright Electronic Arts 1992. Their corresponding PNG
files are independent true-colour rendering controls. Both supplied ILBMs
declare eight source planes and therefore exercise HAM8 decoding; the `.Ham`
suffix on `TutGallery.Ham` is not an authoritative plane-count indicator.
`AquariumBackground.Ham` is a 320×200 Deluxe Paint sample that declares six
planes and exercises authentic HAM6 decoding. `AquariumBackground.png` was
created with ImageMagick. Like the King Tut conversion, it retains four-bit
HAM component levels as `$x0`; normalizing them to `$xx` makes every RGB pixel
match Vexter's specification-compliant output.

SHA-256:

```text
01538bd5e2075881264327505d3705f853aa32884833811818633e1fb214f6cd  AquariumBackground.Ham
3243a9885b7cfaab9cdca4dcfa4cd8a804d7c995dd00bd778d30d411835119ca  AquariumBackground.png
0bf2a23c328aca077d4320dbaf5a6511f7864018ac8d674348356ede91c250ba  EAWorld.Ham8
01644e16c214f55a40598d9fb1562e8405656a8abce7772e8b421c50a721720e  EAWorld.png
0e3d3739075ced0e3dbd564ec455e3174844cd66abdeb240c54e88041c173473  TutGallery.Ham
b4cf32923cc4a72aba4a5f239eced251b1b85ef4a0ab2eedc364c834fbcef96d  TutGallery.png
```
