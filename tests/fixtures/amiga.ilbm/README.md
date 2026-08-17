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
HAM6 remains covered by a focused synthetic test until a six-plane authentic
fixture is supplied.

SHA-256:

```text
0bf2a23c328aca077d4320dbaf5a6511f7864018ac8d674348356ede91c250ba  EAWorld.Ham8
01644e16c214f55a40598d9fb1562e8405656a8abce7772e8b421c50a721720e  EAWorld.png
0e3d3739075ced0e3dbd564ec455e3174844cd66abdeb240c54e88041c173473  TutGallery.Ham
b4cf32923cc4a72aba4a5f239eced251b1b85ef4a0ab2eedc364c834fbcef96d  TutGallery.png
```
