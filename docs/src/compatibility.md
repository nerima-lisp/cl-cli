# Compatibility

From `1.0.0` onward `cl-cli` follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). This page states
exactly which surface that promise is about, so you can tell in advance whether
something you depend on can change under you.

## What the version number covers

The compatibility promise is about the **external symbols of the `CL-CLI`
package** — the `:export` list in
[`src/package.lisp`](https://github.com/nerima-lisp/cl-cli/blob/main/src/package.lisp),
catalogued in the [API Reference](api-reference.md). Specifically:

- the names and lambda lists of exported functions and macros, including every
  keyword accepted by `make-app` / `make-command` / `make-option` /
  `make-positional` and every clause accepted by `define-app` /
  `define-command`
- the exported accessors, and the meaning of what they return
- the condition hierarchy: which conditions exist, what they subclass, and
  their exported slot readers
- the documented exit codes
- the *behavioral* contract of the generated artifacts — that
  `render-bash-completion` emits a valid bash completion script offering the
  app's visible commands and options, that `render-manpage` emits a
  `mandoc`-clean section-1 page, that `render-json` emits an object whose
  documented keys mean what they say

A **major** release is required to remove or rename any of the above, to reject
an argument that used to be accepted, or to change documented behavior
incompatibly. A **minor** release adds. A **patch** release fixes a defect
without changing the documented contract.

## What it does not cover

- **Unexported symbols.** Anything reachable only through the `cl-cli::`
  double-colon escape — including every `%`-prefixed internal helper — is
  implementation detail and moves without notice. If you find yourself needing
  one, that is worth [an issue](https://github.com/nerima-lisp/cl-cli/issues):
  the fix is to export a supported entry point, not for you to reach through.
- **Exact rendered text.** The line wrapping and section ordering of `--help`,
  the internal layout of a generated completion script, the roff or Markdown
  formatting details. These are improved in minor releases. Assert on the
  semantics of the output, not on a byte-for-byte snapshot of it — the test
  suite in `tests/` does exactly that, and is a reasonable model to copy.
  `render-json`'s *keys* are covered by the promise above; its whitespace is
  not. `render-json` additionally carries its own `schemaVersion` — see
  [Documentation Generation](documentation-generation.md) — so its shape is
  versioned independently of the library.
- **Performance.** The benchmark suite guards against gross regressions, but
  no specific timing is promised.
- **The test systems.** `cl-cli/tests` and `cl-cli/tests/shell-verification`,
  and the fixtures in them, are internal to the project.

## Supported implementations

`cl-cli` itself is portable Common Lisp. Its only runtime dependency is
[UIOP](https://asdf.common-lisp.dev/uiop.html), and it uses four symbols from
it (`getenv`, `command-line-arguments`, `read-file-string`, `split-string`).
The library contains exactly two implementation-conditional expressions, both
of which fall back to a documented conservative answer rather than failing.

| Implementation | Status | What CI runs |
| --- | --- | --- |
| SBCL | Primary target | The full suite, including the checks that pipe generated scripts through the real `bash`, `zsh`, `fish`, `nushell`, `pwsh`, `elvish`, and `mandoc` |
| ECL | Supported | The portable core suite |
| Others (CCL, ABCL, Clasp, Allegro, LispWorks, …) | Expected to work, untested | — |

Two behaviors degrade rather than fail where an implementation cannot support
them:

- **Terminal detection.** `:color :auto` probes the real file descriptor only
  on SBCL. Elsewhere `%stream-tty-p` answers "not a terminal", so `NO_COLOR`
  and `CLICOLOR_FORCE` become the only signals. Passing `:color t` or
  `:color nil` explicitly always works and is exact everywhere.
- **`current-process-argv`.** SBCL reads `sb-ext:*posix-argv*` directly;
  elsewhere it goes through `uiop:command-line-arguments`.

If you run `cl-cli` on an implementation not listed as tested and it works,
say so in an issue — the matrix above is limited by what is verified, not by
what is believed to work.

## Platforms

CI runs on `x86_64-linux` and `aarch64-darwin`; the Nix flake also defines
outputs for `aarch64-linux` and `x86_64-darwin`. There is no OS-specific code
in the library. The completion renderers emit scripts for shells, not for
operating systems, and the PowerShell renderer is as usable on Linux as on
Windows.

## Deprecation

When an exported symbol is going away, it is deprecated in a minor release —
documented here and in the [changelog](https://github.com/nerima-lisp/cl-cli/blob/main/CHANGELOG.md),
with the replacement named — and removed no earlier than the next major
release.

Note that this is about `cl-cli`'s own API. Deprecating an *option in your own
CLI* is a separate, supported feature: see `:deprecated` in
[Commands and Dispatch](commands.md).
