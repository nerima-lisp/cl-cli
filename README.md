# cl-cli

[![CI](https://github.com/nerima-lisp/cl-cli/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cli/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cli/)

`cl-cli` builds strict command-line parsers for Common Lisp: flags and typed
options, arbitrarily deep subcommands, positional and rest arguments,
context-sensitive help, shell completion for six shells, and offline man
page/Markdown/JSON generation — all from one declarative app spec. It targets
SBCL and also runs its portable core on ECL. Unlike the usual alternatives it
takes no third-party dependency at all: the `cl-cli` system depends on `uiop`
alone, which ships with every modern ASDF.

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
man page. See [Quick Start](https://nerima-lisp.github.io/cl-cli/quick-start/).

## Install

```nix
# flake.nix
inputs.cl-cli = {
  url = "github:nerima-lisp/cl-cli/v1.0.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

Without Nix, clone the repository somewhere ASDF looks — `~/common-lisp/` or
`~/quicklisp/local-projects/` — and `(asdf:load-system "cl-cli")`. Full
instructions, including the ASDF `:depends-on` entry, are in
[Installation](https://nerima-lisp.github.io/cl-cli/installation/).

## Documentation

- [Installation](https://nerima-lisp.github.io/cl-cli/installation/) and
  [Quick Start](https://nerima-lisp.github.io/cl-cli/quick-start/)
- [Option Values and Kinds](https://nerima-lisp.github.io/cl-cli/option-values/) —
  option kinds, typed values, env-var and config defaults, arity
- [Commands and Dispatch](https://nerima-lisp.github.io/cl-cli/commands/) —
  nested subcommands, aliases, grouping, the `define-app` DSL
- [API Reference](https://nerima-lisp.github.io/cl-cli/api-reference/) — every
  exported symbol and condition
- [Migration Guide](https://nerima-lisp.github.io/cl-cli/migration-guide/) —
  mapping an existing in-house parser onto `cl-cli`
- [Scope and Non-Goals](https://nerima-lisp.github.io/cl-cli/scope/) — what
  `cl-cli` deliberately leaves to the application

## Development

```sh
nix develop          # SBCL, ECL, and the shells the suite verifies against
nix run .#test       # run the SBCL test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework.
The suite is split into a portable core (`cl-cli/test`) and a
shell-verification half (`cl-cli/test/shell-verification`) that pipes generated
completion scripts and man pages through the real `bash`, `zsh`, `fish`,
`nushell`, `pwsh`, `elvish`, and `mandoc`. See
[Development](https://nerima-lisp.github.io/cl-cli/development/).

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
Report suspected vulnerabilities privately via
[SECURITY](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md), not
in a public issue.

## License

MIT. See [LICENSE](LICENSE).
