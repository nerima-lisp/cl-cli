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

SBCL is the release-blocking target and must be green. ECL is currently
expected to fail: `cl-log-kit` (a transitive test dependency via
`cl-process-kit`) hard-codes `sb-thread:*` with no portability guard, so
it cannot compile under any non-SBCL implementation --
[nerima-lisp/cl-log-kit#1](https://github.com/nerima-lisp/cl-log-kit/issues/1),
open upstream. `nix flake check`'s `ecl` output — and any local ECL run —
will fail until that's fixed; do not treat it as a release-blocking
regression to chase, and do not skip the SBCL check to compensate.

If a release changes parser semantics, help output, or completion rendering,
add or update focused tests before tagging.

## Publish

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` are consistent.
3. Tag the release from the verified commit.
4. Publish release notes that summarize breaking changes, new APIs, and migration work for downstream CLIs.

## Post-release

- Verify that package consumers can still load `cl-cli` through ASDF or Quicklisp-compatible workflows.
- Triage any follow-up regressions into focused parser, help, completion, or runtime argv categories.
