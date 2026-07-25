# Release Process

Use this checklist before publishing a tagged release.

## Preconditions

- [CHANGELOG.md](https://github.com/nerima-lisp/cl-cli/blob/main/CHANGELOG.md)
  reflects all user-visible changes
- [README.md](https://github.com/nerima-lisp/cl-cli/blob/main/README.md)
  examples match the current public API
- [Security](security.md) points to a real private reporting path
- package metadata in
  [cl-cli.asd](https://github.com/nerima-lisp/cl-cli/blob/main/cl-cli.asd)
  still matches the canonical repository URLs

## Verification

Run the full validation path:

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

If a release changes parser semantics, help output, or completion rendering,
add or update focused tests before tagging.

## Publish

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, [Contributing](contributing.md), [Support](support.md),
   and [Security](security.md) are consistent.
3. Tag the release from the verified commit.
4. Publish release notes that summarize breaking changes, new APIs, and
   migration work for downstream CLIs.

## Post-release

- Verify that package consumers can still load `cl-cli` through ASDF or
  Quicklisp-compatible workflows.
- Triage any follow-up regressions into focused parser, help, completion, or
  runtime argv categories.
