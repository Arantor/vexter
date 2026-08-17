# Amiga IFF ANIM fixtures

`TheTour.anim` is a 320×200, five-plane IFF ANIM containing 34 reconstructed
frames. Its 33 delta frames all use method 5. The final two frames duplicate
the first two, following the conventional continuous-loop layout.

`TheTour.gif` is a rendering control supplied with the ANIM. Its palette keeps
legacy four-bit Amiga components as `$x0`; after normalizing those components
to `$xx`, every expanded RGB pixel across all 34 frames matches Vexter's
decode. The GIF's uniform 100 ms frame timing is not authoritative: the ANIM's
ANHD relative times remain decoded as 1/60-second Amiga jiffies.

`TheTour.anim` is bundled with Deluxe Paint and is copyright Electronic Arts,
like the other supplied Deluxe Paint sample files. Its redistribution or
licensing status has not yet been supplied and should be confirmed before
distributing these files outside this development context.

SHA-256:

```text
1abaa4b7c0f44183134b77f9f1a2e3ba42144d7c57be7c13c591c8b0c66dc6ce  TheTour.anim
7badc395911c87682cae4ac30f1380cd6364fb0f8eed6977219965d69ae5ac6d  TheTour.gif
```
