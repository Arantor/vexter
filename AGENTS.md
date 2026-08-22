# Development guidance

Before changing this repository, read [`DEVELOPMENT.md`](DEVELOPMENT.md) for
the implemented architecture, module boundaries, test workflow, and current
limitations. Read [`PLAN.md`](PLAN.md) separately for intended future work; do
not treat planned features as implemented behavior.

The current development environment is subject to heat-related constraints:

- run no more than two background or build processes concurrently;
- give builds, tests, and other sustained CPU work a suitably low priority
  (for example, `nice -n 15` on Linux); and
- prefer sequential test execution unless concurrency is necessary.

Keep compiler warnings enabled for builds and test compilations; do not use
`--warnings:off`, because warnings are part of the verification result.

Format implementation must follow the source and research policy in
`PLAN.md`: do not search the internet for Vexter format research or
implementation material.
