# ZX Spectrum screen fixtures

## `colours`

`colours.scr` and its PNG and GIF controls were freshly produced for the
Vexter project using a ZX Spectrum program. This is the primary exhaustive
colour-attribute fixture.

The top-left 128 x 128 pixels exercise colours 0 through 7 twice in each axis:

- attribute rows cover ink colours without and with FLASH;
- attribute columns cover paper colours without and with BRIGHT;
- the natural frame exposes the ink values; and
- the swapped FLASH frame exposes the paper values in flashing rows.

The remainder of the 256 x 192 screen is unfilled and displays normal white
paper. `colours.png` is the natural state and `colours.gif` contains both FLASH
states. Their encoded structure and compression are not normative; fully
composited pixel colours and positions are.

SHA-256:

```text
2b9edfebd57b7ea7aa194f035dc4f895b48b8273028585138e5df1653019a251  colours.scr
00fce7baf6e79dc4e647c2e1ca8806fe3facb1ef68e72d1c0f8cfb012fb32db2  colours.png
1cdc82dc8870ec5908ac321ba4e45d65ef5ff6e11732544ba05fd4e4baae4292  colours.gif
```
