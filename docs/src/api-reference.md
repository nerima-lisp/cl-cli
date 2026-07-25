# API Reference

All public symbols live in the `cl-cli` package. This page groups the full
export list by role; see the linked guide pages for usage examples of each
group.

## Spec constructors

`make-app`, `make-command`, `make-option`, `make-positional`,
`exclusive-group`, `required-exclusive-group`, `inclusive-group` — see
[Option Relations and Grouping](option-relations.md) for the group helpers.

`define-app` and `define-command` are macros wrapping those constructors in a
declarative, clause-based form: `:option`, `:positional`, and `:command`
clauses replace the nested `:global-options (list ...)` / `:positionals
(list ...)` / `:commands (list ...)` keywords, and `:commands-from` splices in
an already-built command list. Each binds its spec with `defparameter`. The
functional constructors are unchanged and remain usable on their own. See
[Commands and Dispatch](commands.md#declarative-dsl) for the full clause
vocabulary and a `:commands-from` splicing example.

## Built-in commands

`make-standard-commands` builds the aggregate `help` / `version` /
`completion` / `docs` / `__complete` set (each gated by its own `:include-*-p`
keyword). The individual constructors are also exported directly:
`make-help-command`, `make-version-command`, `make-completion-command`,
`make-docs-command`, and `make-complete-command` (the hidden dynamic-completion
callback; `render-complete-reply` is its underlying logic) — see [Shell
Completion](shell-completion.md) and [Documentation
Generation](documentation-generation.md).

## Parsing and dispatch

`parse-argv` returns an invocation object without running handlers;
`run-app` parses and dispatches, returning a process exit code — see
[Validation and Exit Codes](validation.md).

## Help

`print-app-help` and `print-command-help` render help text directly to a
stream, independent of the built-in `help` command — see [CLI
Behavior](cli-behavior.md#colored-width-aware-help) for the `:color` /
`:width` keywords they accept.

## Shell completion

`render-completion` (shell name as a string) plus the shell-specific
`render-bash-completion`, `render-zsh-completion`, `render-fish-completion`,
`render-powershell-completion`, `render-nushell-completion`, and
`render-elvish-completion`.

## Documentation

`render-manpage`, `render-markdown`, and `render-json` render offline
reference docs and machine-readable schema; `render-docs` dispatches to them
by format name (`"man"` / `"markdown"` / `"json"`).
`+json-schema-version+` is the version of `render-json`'s output shape, also
emitted as that document's first member.

## Runtime argv

`current-process-argv`, `application-argv`, `extract-application-argv`,
`default-runtime-markers`, and `strip-argv-separators` normalize
launcher-inserted tokens and `--` separators — see [CLI
Behavior](cli-behavior.md#launcher-aware-argv-normalization).

## Invocation accessors

`option-value` and `positional-value` read resolved values; `option-value-source`
reports where an option value came from (`:command-line` / `:env` /
`:config` / `:default`). `invocation-app`, `invocation-command`,
`invocation-action`, `invocation-argv0`, `invocation-raw-argv`,
`invocation-global-options`, `invocation-command-options`,
`invocation-positionals`, `invocation-command-path`,
`invocation-option-sources`, `invocation-stdout`, and `invocation-stderr`
expose the rest of the parsed invocation. `command-by-name` resolves a
command spec by name or alias.

## Spec accessors

Every `make-app` and `make-option` keyword has a matching reader; `make-command`
is the exception, in that its `:subcommands` and `:default-command` keywords
have no exported reader. (Positionals have no accessor family — read positional
data through `positional-value` on an invocation instead.)

**App** — `app-name`, `app-version`, `app-summary`, `app-description`,
`app-global-options`, `app-positionals`, `app-commands`,
`app-default-command`, `app-handler`, `app-examples`, `app-help-footer`,
`app-see-also`, `app-authors`, `app-manual-date`,
`app-allow-abbreviated-options`, `app-expand-response-files`,
`app-allow-negative-numbers`, `app-require-command`, `app-auto-help`.

**Command** — `command-name`, `command-aliases`, `command-group`,
`command-description`, `command-examples`, `command-options`,
`command-positionals`, `command-handler`, `command-hidden-p`,
`command-deprecated`, `command-help-footer`.

**Option** — `option-key`, `option-names`, `option-negated-names`,
`option-kind`, `option-description`, `option-value-name`,
`option-value-type`, `option-value-min`, `option-value-max`,
`option-value-delimiter`, `option-value-count`, `option-value-hint`,
`option-default`, `option-env-vars`, `option-choices`,
`option-completion-candidates`, `option-complete`, `option-parser`,
`option-required-p`, `option-required-if`, `option-required-unless`,
`option-requires`, `option-requires-any-of`, `option-conflicts-with`,
`option-multiple-p`, `option-consume-optional-value-p`,
`option-stop-parsing-p`, `option-hidden-p`, `option-deprecated`,
`option-help-group`.

## Conditions

Usage errors subclass `cli-usage-error`; specification errors signal
`cli-invalid-specification`. Every condition has a `cli-error-message`
reader; several carry additional structured readers for the specific values
involved.

| Condition | Extra readers | Signaled when |
| --- | --- | --- |
| `cli-unknown-option` | `cli-unknown-option-name` | an option token doesn't match any declared option |
| `cli-unknown-command` | `cli-unknown-command-name` | a command token doesn't match any declared command (or `:require-command t` with none given) |
| `cli-missing-option-value` | `cli-missing-option-value-name` | an option that takes a value appears without one (including too few tokens for `:value-count`), or a required option — or one made required by `:required-if`/`:required-unless` — is absent |
| `cli-missing-dependent-option` | `cli-missing-dependent-option-name`, `cli-missing-dependent-option-dependency` | an `inclusive-group` member is set without its partners |
| `cli-missing-any-of-options` | `cli-missing-any-of-options-name`, `cli-missing-any-of-options-alternatives` | none of a `:requires-any-of` set is present |
| `cli-conflicting-options` | `cli-conflicting-options-left-option`, `cli-conflicting-options-right-option` | two options declared via `:conflicts-with` / `exclusive-group` are both present |
| `cli-missing-positional` | `cli-missing-positional-name` | a required positional, or a rest positional under its `:min-count`, is absent |
| `cli-invalid-option-value` | `cli-invalid-option-value-name`, `cli-invalid-option-value-value`, `cli-invalid-option-value-cause` | an option's `:type`/`:parser`/`:choices` rejects the supplied value |
| `cli-invalid-positional-value` | `cli-invalid-positional-value-name`, `cli-invalid-positional-value-value`, `cli-invalid-positional-value-cause` | a positional's `:type`/`:parser`/`:choices` rejects the supplied value |
| `cli-unexpected-argument` | `cli-unexpected-argument-name` | an extra positional appears past a rest positional's `:max-count`, or with no positionals declared |
| `cli-invalid-specification` | `cli-error-message` only | `make-app`/`make-command`/`make-option`/`make-positional` receives an invalid spec |

`cli-usage-error` itself additionally carries `cli-usage-error-app` and
`cli-usage-error-command` readers, inherited by every concrete usage
condition above.
