# ZX Spectrum snapshot fixtures

## `colours.sna`

This is a 48K SNA snapshot containing the Spectrum program that produced the
`zx-spectrum.screen/colours.scr` fixture. The first 27 bytes contain register
and execution state. The following 6,912 bytes are screen memory and match
`colours.scr` exactly.

SHA-256:

```text
d022905e5ce8d5e5f40df2d644e72a695c62b861b606ee5d251f469247d43a74  colours.sna
```

The extracted screen-memory SHA-256 is:

```text
2b9edfebd57b7ea7aa194f035dc4f895b48b8273028585138e5df1653019a251
```

This fixture proves 48K SNA detection, screen-resource extraction, and reuse of
the raw-screen decoding and export pathway.

## `colours-listing.sna`

This snapshot captures the same project program in the BASIC editor, where the
screen has no FLASH attributes. Its screen-memory region matches
`zx-spectrum.screen/colours-listing.scr` exactly. It proves that snapshot
screen extraction can produce a static `VextIndexedImage` and default to PNG.

SHA-256:

```text
16a30f0d8cf5780fe08f8e4b5ac056fce51edd33d38733a4045894e4415ce1d4  colours-listing.sna
```

The extracted screen-memory SHA-256 is:

```text
dc2641506aacd9505d6a85ac9dbaab039cce356a457ec7f0ecb37cb0954820ab
```
