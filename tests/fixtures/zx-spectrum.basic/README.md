# ZX Spectrum BASIC fixture

`colours-listing.txt` is the expected UTF-8 reconstruction of the program in
`../zx-spectrum.snapshot/colours-listing.sna`. It was supplied by the project
author and includes the `$8F` block graphic as Unicode `█`.

The author-supplied PureBasic token table and experimental snapshot decoder
were used as implementation references, then removed from the fixture tree;
the maintained behavior now lives in the Nim decoder and tests.
