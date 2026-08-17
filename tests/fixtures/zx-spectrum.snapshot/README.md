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
