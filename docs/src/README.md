# cl-cli

`cl-cli` is a small, dependency-light Common Lisp CLI toolkit for building
strict flag and option parsers, subcommand-based tools, root/default command
entry points, positional and rest-argument parsers, help/version handling, and
reusable app, command, option, and positional specs.

The project is intentionally conservative about dependencies so it works well
in minimal Common Lisp and Nix environments.

!!! tip "New to cl-cli?"

    Load it, describe an app spec, and dispatch it in a few lines:

    ```lisp
    (ql:quickload :cl-cli)

    (defparameter *app*
      (cl-cli:make-app
       :name "demo"
       :commands (list (cl-cli:make-command
                         :name "compile"
                         :positionals (list (cl-cli:make-positional :key :input :required-p t))
                         :handler (lambda (invocation)
                                     (format t "compiling ~A~%"
                                             (cl-cli:positional-value invocation :input))
                                     0)))))

    (cl-cli:run-app *app* :argv '("demo" "compile" "input.lisp"))
    ```

    Continue with [Installation](installation.md) → [Quick Start](quick-start.md)
    → [Option Values and Kinds](option-values.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    Every install path — Nix, ASDF, and Quicklisp — and your first parsed and
    dispatched app spec.

    [:octicons-arrow-right-24: Installation](installation.md) ·
    [Quick Start](quick-start.md)

-   :material-tune:{ .lg .middle } &nbsp; **Modeling a CLI**

    ---

    Option kinds and typed values, cross-option relationships and grouping,
    subcommand dispatch, and custom validation with exit codes.

    [:octicons-arrow-right-24: Option Values](option-values.md) ·
    [Option Relations](option-relations.md) ·
    [Commands](commands.md) ·
    [Validation](validation.md)

-   :material-console-line:{ .lg .middle } &nbsp; **Runtime Behavior**

    ---

    Terminal-aware colored help, response files, abbreviated options,
    negative-number arguments, and launcher-aware argv normalization.

    [:octicons-arrow-right-24: CLI Behavior](cli-behavior.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Completion and Docs**

    ---

    Generate bash/zsh/fish/PowerShell/nushell/elvish completion scripts —
    static and runtime-dynamic — plus man pages, Markdown, and JSON straight
    from an app spec.

    [:octicons-arrow-right-24: Shell Completion](shell-completion.md) ·
    [Documentation Generation](documentation-generation.md)

</div>

## Status

Pre-1.0. The capability list below is the current public surface, validated by
the test suite documented in [Contributing](contributing.md):

- strict, exact-match option and flag parsing, with optional GNU-style
  abbreviated-prefix matching
- `:flag`, `:boolean`, `:value`, `:optional-value`, `:count`, and `:key-value`
  option kinds
- typed values (`:integer`, `:number`, `:float`, `:boolean`, `:string`) with
  `:min` / `:max` range checks, or a fully custom `:parser`
- repeatable (`:multiple-p`), delimited (`:value-delimiter`), and
  fixed/variadic-arity (`:value-count`) option values
- environment-variable defaults, a layered `:config` plist, and
  `option-value-source` provenance tracking
- cross-option relationships — `:requires`, `:requires-any-of`,
  `:conflicts-with`, `:required-if`, `:required-unless` — plus
  `exclusive-group`, `required-exclusive-group`, and `inclusive-group` helpers
- arbitrarily deep nested subcommands, command/option grouping, aliases, and
  `:default-command` / `:require-command` dispatch policy
- context-sensitive, terminal-aware help (`:color :auto`, `:width :auto`) with
  usage synopses, examples, and deprecation annotations
- shell completion generation for bash, zsh, fish, PowerShell, nushell, and
  elvish, including a runtime `__complete` callback for dynamic candidates
- offline documentation generation — man page, GitHub-flavored Markdown, and
  JSON schema — from the same spec metadata that drives `--help`
- response-file (`@args.txt`) expansion and launcher-aware argv normalization
  for SBCL- and Nix-wrapped executables
- configurable usage/error exit codes following BSD `sysexits.h` by default

See [Scope and Non-Goals](scope.md) for what `cl-cli` deliberately leaves to
the application, and [Migration Guide](migration-guide.md) for mapping an
existing in-house parser onto `cl-cli`.

## Test

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

## Contributing

Development workflow, change expectations, and verification requirements are
documented in [Contributing](contributing.md).
