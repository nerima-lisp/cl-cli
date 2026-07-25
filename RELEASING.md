# Releasing

Use this checklist before publishing a tagged release.

## Preconditions

- `CHANGELOG.md` reflects all user-visible changes
- `README.md` examples match the current public API
- `SECURITY.md` points to a real private reporting path
- package metadata in `cl-cli.asd` still matches the canonical repository URLs

## Verification

Run the full validation path:

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

SBCL and ECL are both release-blocking and must be green, as must the docs
build that `nix flake check` also runs. Confirm the runner's own line about
which half of the suite it loaded: a release verified only by the portable
core has not exercised the generated completion scripts.

CI runs `nix flake check` on every push and pull request to `main`, on both
`x86_64-linux` and `aarch64-darwin`. `nix flake check` only evaluates outputs
for the system it runs on, so a local run verifies your machine's system and
nothing else.

If a release changes parser semantics, help output, or completion rendering,
add or update focused tests before tagging.

## Publish

1. Bump `:version` in `cl-cli.asd`. It appears twice — once in the `cl-cli`
   system and once in `cl-cli/tests` — and both must match. `flake.nix` reads
   the first `:version` line as the docs package version.
2. Update `CHANGELOG.md`: cut `[Unreleased]` into a dated section for the new
   version, add that version's link reference at the bottom of the file, and
   repoint the `[Unreleased]` compare link at the new tag.
3. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` are
   consistent, and mirror any change into the matching page under `docs/src/`.
4. Tag the release from the verified commit, using a `vX.Y.Z` tag name.
5. Publish release notes that summarize breaking changes, new APIs, and migration work for downstream CLIs.

## Post-release

- Verify that package consumers can still load `cl-cli` through ASDF or Quicklisp-compatible workflows.
- Triage any follow-up regressions into focused parser, help, completion, or runtime argv categories.
