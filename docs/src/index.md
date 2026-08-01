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
    (asdf:load-system "cl-cli")

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

    Continue with [Getting Started](getting-started.md) →
    [Option Values and Kinds](guide/option-values.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    Every install path — Nix and ASDF — and your first parsed and
    dispatched app spec.

    [:octicons-arrow-right-24: Getting Started](getting-started.md)

-   :material-tune:{ .lg .middle } &nbsp; **Modeling a CLI**

    ---

    Option kinds and typed values, cross-option relationships and grouping,
    subcommand dispatch, and custom validation with exit codes.

    [:octicons-arrow-right-24: Option Values](guide/option-values.md) ·
    [Option Relations](guide/option-relations.md) ·
    [Commands](guide/commands.md) ·
    [Validation](guide/validation.md)

-   :material-console-line:{ .lg .middle } &nbsp; **Runtime Behavior**

    ---

    Terminal-aware colored help, response files, abbreviated options,
    negative-number arguments, and launcher-aware argv normalization.

    [:octicons-arrow-right-24: CLI Behavior](guide/cli-behavior.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Completion and Docs**

    ---

    Generate bash/zsh/fish/PowerShell/nushell/elvish completion scripts —
    static and runtime-dynamic — plus man pages, Markdown, and JSON straight
    from an app spec.

    [:octicons-arrow-right-24: Shell Completion](guide/shell-completion.md) ·
    [Documentation Generation](guide/documentation-generation.md)

</div>

## Status

Stable. From `1.0.0` the exported API is covered by Semantic Versioning — see
[Compatibility](reference/compatibility.md) for exactly what that promise includes, which
Lisp implementations are tested, and how a symbol is deprecated.

The capability list below is the current public surface, validated by the test
suite documented in [Development](project/development.md):

- strict, exact-match option and flag parsing, with optional GNU-style
  abbreviated-prefix matching
- a functional spec API (`make-app` / `make-command` / `make-option` /
  `make-positional`) plus the additive `define-app` / `define-command`
  clause-based DSL that expands into it
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

See [Scope and Non-Goals](guide/scope.md) for what `cl-cli` deliberately leaves to
the application, and [Migration Guide](guide/migration-guide.md) for mapping an
existing in-house parser onto `cl-cli`.

## Contributing

Build, test and formatting commands are in [Development](project/development.md).

Contribution process, the code of conduct, security reporting and support
channels are org-wide and live in
[nerima-lisp/.github](https://github.com/nerima-lisp/.github):
[CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md),
[CODE_OF_CONDUCT](https://github.com/nerima-lisp/.github/blob/main/CODE_OF_CONDUCT.md),
[SECURITY](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md) and
[SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
