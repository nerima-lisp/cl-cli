# cl-cli

[![CI](https://github.com/nerima-lisp/cl-cli/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cli/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cli/)

`cl-cli` builds strict command-line parsers for Common Lisp: flags and typed
options, arbitrarily deep subcommands, positional and rest arguments,
context-sensitive help, shell completion for six shells, and offline man
page/Markdown/JSON generation — all from one declarative app spec or from
reusable app, command, option, and positional specs. It targets SBCL and also
runs its portable core on ECL. It takes almost no third-party dependency: the
`cl-cli` system depends on `uiop` alone (ships with every modern ASDF) on
every implementation but SBCL, and additionally on
[`cl-host-kit`](https://github.com/nerima-lisp/cl-host-kit) on SBCL.

For independent argv workloads, the optional SBCL-only `cl-cli/concurrent`
system provides `cl-cli/concurrent:parse-argv-batch`, backed by
[`cl-concurrent-kit`](https://github.com/nerima-lisp/cl-concurrent-kit). It
preserves input order and bounds in-flight requests; the portable `cl-cli`
system remains unchanged.

Full documentation is published at <https://nerima-lisp.github.io/cl-cli/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(asdf:load-system "cl-cli")

(defparameter *app*
  (cl-cli:make-app
   :name "demo"
   :version "0.1.0"
   :global-options (list (cl-cli:make-option :name "verbose" :short #\v :kind :flag))
   :commands (list
              (cl-cli:make-command
               :name "compile"
               :options (list (cl-cli:make-option :name "output" :short #\o :kind :value))
               :positionals (list (cl-cli:make-positional :key :input :required-p t))
               :handler (lambda (invocation)
                           (format t "compile ~A -> ~A~%"
                                   (cl-cli:positional-value invocation :input)
                                   (cl-cli:option-value invocation :output)))))))

(cl-cli:run-app *app* :argv '("demo" "compile" "-o" "out.bin" "input.lisp"))
;; => compile input.lisp -> out.bin
```

The same spec drives `--help`, `cl-cli:render-completion`, and the generated
man page. See [Getting Started](https://nerima-lisp.github.io/cl-cli/getting-started/).
If you prefer named reusable building blocks, the DSL also exports
`define-app`, `define-command`, `define-option`, and `define-positional`.

## Install

As a library, from another flake:

```nix
# flake.nix
inputs.cl-cli = {
  url = "github:nerima-lisp/cl-cli/v1.3.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch. On a `lispDependencies` edge, read
`cl-cli.packages.<system>.cl-cli` -- `packages.default` is the demo binary
described under [Development](#development), not the ASDF system.

To try the demo CLI without adding cl-cli to anything:

```sh
nix build              # -> ./result/bin/cl-cli-demo
./result/bin/cl-cli-demo greet --upcase ada
```

Without Nix, clone the repository somewhere ASDF looks — `~/common-lisp/` or
`~/quicklisp/local-projects/` — and `(asdf:load-system "cl-cli")`. Full
instructions, including the ASDF `:depends-on` entry, are in
[Getting Started](https://nerima-lisp.github.io/cl-cli/getting-started/).
On SBCL, load the optional batch API explicitly with
`(asdf:load-system "cl-cli/concurrent")`.

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-cli/getting-started/) —
  installation and quick start
- [Option Values and Kinds](https://nerima-lisp.github.io/cl-cli/guide/option-values/) —
  option kinds, typed values, env-var and config defaults, arity
- [Commands and Dispatch](https://nerima-lisp.github.io/cl-cli/guide/commands/) —
  nested subcommands, aliases, grouping, and the `define-*` DSL family
- [API Reference](https://nerima-lisp.github.io/cl-cli/reference/api/) — every
  exported symbol and condition
- [Migration Guide](https://nerima-lisp.github.io/cl-cli/guide/migration-guide/) —
  mapping an existing in-house parser onto `cl-cli`
- [Scope and Non-Goals](https://nerima-lisp.github.io/cl-cli/guide/scope/) — what
  `cl-cli` deliberately leaves to the application

## Development

```sh
nix develop          # SBCL, ECL, and the shells the suite verifies against
nix build            # -> ./result/bin/cl-cli-demo
nix build .#cl-cli   # the library (the ASDF system, for lispDependencies)
nix run .#test       # run the SBCL test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
SYSTEM=$(nix eval --raw --expr 'builtins.currentSystem')
nix build ".#checks.${SYSTEM}.coverage" --no-link --print-out-paths
nix build ".#checks.${SYSTEM}.coverage-gate" --no-link
```

`cl-cli/demo` is a small, real CLI (`greet`, a `remote` subcommand group,
plus the standard help/version/completion/docs commands) built entirely from
`cl-cli`'s own primitives, so the library exercises itself as a binary, not
only as a test suite. It is what this flake delivers as `packages.default`, so
`nix build` produces it and `nix run . -- greet --upcase ada` runs it; `nix
build .#cl-cli-demo` and `nix run .#cl-cli-demo` name the same derivation
explicitly. Its source lives in [`demo/`](demo/); its end-to-end dispatch tests
are in `t/demo-test.lisp`.

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework.
`nix run .#test` is the reproducible test entry point. For a direct SBCL run,
use `sbcl --script run-tests.lisp`; it discovers adjacent source checkouts, and
its `CL_*_SOURCE_DIR` environment variables override those locations in an
isolated worktree.
The suite is split into a portable core (`cl-cli/test`) and a
shell-verification half (`cl-cli/test/shell-verification`) that pipes generated
completion scripts and man pages through the real `bash`, `zsh`, `fish`,
`nushell`, `pwsh`, `elvish`, and `mandoc`. See
[Development](https://nerima-lisp.github.io/cl-cli/development/).
The SBCL-only `cl-cli/concurrent` system is checked as part of the SBCL test
system; it is not loaded by the ECL check or the portable core.

The coverage check writes an `sb-cover` HTML report containing
`cover-index.html` to the returned Nix store path. The `coverage-gate` check
parses that same report and fails if aggregate expression or branch coverage
falls below 96%. This is a regression floor for the current report, not the
project target: the target remains 100% of reachable branches inside function
bodies, while `sb-cover`'s raw expression percentage also counts top-level
forms and macro-expansion helpers.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

Release notes are on the
[Releases page](https://github.com/nerima-lisp/cl-cli/releases).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
Report suspected vulnerabilities privately via
[SECURITY](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md), not
in a public issue.

## License

MIT. See [LICENSE](LICENSE).
