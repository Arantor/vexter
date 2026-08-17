# AMOS sprite-bank fixtures

`DRAGON.Abk` is an `AmSp` sprite bank containing ten 32 x 17, four-plane
sprites. `DRAGON.gif` is an independently generated ten-frame control. Every
frame matches an unshifted decode of the bank exactly in expanded RGB.

The bank demonstrates the trailing variant of the shared 32-entry `$0RGB`
palette. Its planar payload is plane-major, beginning with plane zero;
plane zero supplies the least-significant palette-index bit. Words are
big-endian and their most-significant bit maps to output column zero.

The origin and third-party attribution of `DRAGON.Abk` are recorded in the
repository's [`THIRD_PARTY.md`](../../../THIRD_PARTY.md).

SHA-256 hashes:

```text
bb46e9560f1c385fa42f8f4627fd6dd9a827abc85fb1c92d5327927f5a0c9ba5  DRAGON.Abk
61b04a0c9c0733ad273b0809879e2cb88166706b474d5a8f5ef9a8ae2ec004a5  DRAGON.gif
```
