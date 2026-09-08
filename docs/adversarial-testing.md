# Adversarial testing

Vexter treats every input file, container member, filename, and declared size
as untrusted. Adversarial testing primarily protects availability, memory
safety, bounded resource use, deterministic behavior, and confinement of
filesystem output. It supplements format-correctness tests; it does not replace
their documented reference material or permit external format research.

## Permanent public gate

`tests/test_adversarial.nim` is dependency-free and runs as part of `nimble
test`. Its explicit profile table must contain exactly one row for every format
handler. It drives every physical parser, every semantic carrier path, and
automatic detection with a common hostile corpus. A new handler is incomplete
until it has an adversarial profile and format-specific named-invariant tests.

Generic mutations are not presumed invalid: a changed input can still be a
valid file. They fail the gate only if they produce a defect, assertion,
abnormal termination, nondeterminism, resource-limit escape, or filesystem
escape. A structure-aware test that deliberately violates a documented named
invariant must be rejected, or isolated at the contained-member boundary when
that is the documented recovery behavior.

Confirmed failures are minimized. Generated or redistributable reproducers are
added to the ordinary format suite. Restricted source files remain in private
infrastructure, but should be replaced by a synthetic byte-level regression
whenever that preserves the fault.

## External fuzz interface

`tools/vexter_fuzz_target.nim` is a process target for external instrumentation:

```text
vexter_fuzz_target detect - FILE-NAME INPUT
vexter_fuzz_target parse TYPE-ID FILE-NAME INPUT
vexter_fuzz_target inspect TYPE-ID|- FILE-NAME INPUT
vexter_fuzz_target session TYPE-ID|- FILE-NAME INPUT
```

Expected catchable parse failures exit normally. Nim defects, assertions,
signals, sanitizer failures, and hangs remain visible to the runner. The target
has no fuzz-tool dependency and is not part of product builds.

The private fuzz repository should pin Vexter as a Git submodule, keep corpus
provenance and SHA-256 records, and build this target with AFL++/Clang ASan and
UBSan. Routine campaigns last one hour; weekly and pre-release campaigns run
overnight. Run at most two jobs concurrently. ORC is the normal Linux target;
repeat high-risk targets under ARC to cover ownership behavior shared with the
Windows GUI.

A sanitizer-only build requires no source changes:

```sh
nim c --cc:clang --passC:-fsanitize=address,undefined \
  --passL:-fsanitize=address,undefined --path:src \
  -o:build/linux/vexter-fuzz-target-sanitize tools/vexter_fuzz_target.nim
```

An AFL++ repository can substitute its compiler while retaining Nim's Clang
backend, then select a handler and operation per campaign shard:

```sh
nim c --cc:clang --clang.exe:afl-clang-fast \
  --clang.linkerexe:afl-clang-fast --path:src \
  -o:build/linux/vexter-fuzz-target tools/vexter_fuzz_target.nim
afl-fuzz -i corpus/archive.lha -o findings/archive.lha -- \
  build/linux/vexter-fuzz-target session archive.lha sample.lha @@
```

Private GitHub Actions should run short sanitizer smoke tests for proposed
changes, rotating one-hour nightly shards, overnight weekly shards, and a
native Windows deterministic CLI/extraction and GUI-open smoke job. Artifacts
must retain the Vexter commit, compiler and tool versions, exact invocation,
minimized input, input hash, sanitizer log, and stack signature.

## Audit checklist

Review every handler for checked size arithmetic before slicing or allocation,
decompression output bounds, recursion and resource accounting, and safe FFI
buffer ownership. Review extraction for traversal, separator variants,
case-folding and portable-name collisions, device names, symlinks, junctions,
overwrite behavior, and preflight/write races. Review GUI worker completion,
cancellation, repeated open/close, and shared result ownership separately; GUI
correctness is secondary, but it must not make core failures unsafe.

The permanent failure gate covers uncaught defects, sanitizer findings,
abnormal exits, timeouts, nondeterminism, path escape, documented limit escape,
and acceptance of a mutation known to violate a named invariant.
