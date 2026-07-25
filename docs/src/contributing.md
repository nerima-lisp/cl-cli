# Contributing

## Scope

Contributions should keep `cl-cli` dependency-light, predictable, and
suitable for consumer CLIs that need strict parsing behavior.

Prefer changes that:

- preserve or improve existing parsing semantics
- extend help/completion output from the same spec metadata
- keep public API additions small and composable
- include focused tests for every behavior change

Avoid changes that:

- introduce new runtime dependencies without a strong reason
- add parser ambiguity for convenience-only shorthand
- duplicate validation logic across parser, help, and completion layers

## Development setup

With Nix:

```bash
nix develop
```

Without Nix, install SBCL and load the system through ASDF or Quicklisp — see
[Installation](installation.md).

## Validation

Run the full verification path before opening a change:

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

All three must be green. The test suite is split into a portable core
(`cl-cli/tests`) and a shell-verification half
(`cl-cli/tests/shell-verification`) that shells out to the real completion
consumers; `tests/run-tests.lisp` prints which one it loaded, so a run that
silently covers less than you expected is visible rather than mistakable
for a pass. Under ECL the shell-verification half is excluded, because its
`cl-process-kit` dependency pulls in `cl-log-kit`, which hard-codes
`sb-thread:*` --
[nerima-lisp/cl-log-kit#1](https://github.com/nerima-lisp/cl-log-kit/issues/1),
open upstream. See [Compatibility](compatibility.md) for the supported
implementation matrix.

If a test cannot run on a given implementation, gate it on the capability
that is actually missing and let it report as a skip with a reason. Do not
widen a threshold or delete an assertion so that a red run turns green.

When adding or changing parser behavior:

- add or update a focused test in the matching `tests/cases-*.lisp` file, and
  register any new file in `cl-cli.asd`.
  [tests/run-tests.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/tests/run-tests.lisp)
  is the loader, not a place to put tests. A test that shells out to a real
  tool belongs in `tests/cases-shell-verification.lisp`, under the
  `cl-cli/tests/shell-verification` system; everything else goes in the
  portable `cl-cli/tests`.
- cover both the success path and the expected failure mode when relevant
- prefer an assertion that would fail if the behavior were wrong over one that
  merely records what the code prints today. A completion renderer emitting
  `e:'app'` shipped broken because a test asserted that exact string; the
  question to ask is "what property does this encode", not "does this match"
- update [README.md](https://github.com/nerima-lisp/cl-cli/blob/main/README.md)
  and this documentation site if the user-visible surface changed

## Change guidelines

- Keep public exports intentional. Add new exports only when they are
  reusable outside one local consumer.
- Preserve constructor fail-fast behavior for invalid specs.
- Reuse shared normalization helpers instead of re-implementing string or
  list validation in multiple places.
- Keep comments rare and only use them where the code is otherwise hard to
  parse.

## Pull requests

A good change includes:

- a clear problem statement
- the smallest coherent implementation
- verification notes with the commands you ran
- documentation updates when the CLI surface changed

If a change is intentionally incomplete, state the remaining work explicitly.

See [Support](support.md) for how to ask questions before opening a change,
and [Release Process](releasing.md) for how changes eventually ship.
