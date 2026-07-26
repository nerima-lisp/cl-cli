# Migration Guide

`cl-cli` already covers the shared parser shapes used by the current in-house
CLIs it is intended to replace. The practical question is not "can it parse
options?" but "which API reproduces each existing command surface without
local parser forks?".

Representative specs for all four migration targets below live in
[examples/consumer-migrations.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/examples/consumer-migrations.lisp).

## `cl-cc`

`cl-cc` needs a mix of ordinary subcommands and script-style execution:

- `compile`-style commands with `--flag`, `--key value`, `--key=value`, and `-o value`
- command dispatch on the first non-option token
- `--script FILE [ARGS...] [-- ...]` where everything after the script path stays opaque
- value kinds matching `:boolean`, `:value`, and `:optional-value`

Use these `cl-cli` features:

- `make-command` for first-token subcommand dispatch — see [Commands and
  Dispatch](commands.md)
- `make-option` with `:kind :flag`, `:kind :boolean`, `:kind :value`, and
  `:kind :optional-value` — see [Option Values and Kinds](option-values.md)
- `:stop-parsing-p t` on `--script` to preserve the opaque tail — see [CLI
  Behavior](cli-behavior.md#stopping-parsing-for-opaque-tails)
- `strip-argv-separators` when the downstream script runner should not
  receive a literal `--`

Existing coverage: script tail preservation and separator normalization are
exercised by "stop parsing option preserves remaining arguments", "supports
stop parsing short attached value", and "stop parsing script mode can
normalize opaque tail" in
[t/parser-option-consumption-test.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/t/parser-option-consumption-test.lisp).

## `cl-tmux`

`cl-tmux` needs launcher-aware argv handling and tmux-style attached short
values:

- runtime token stripping before application parsing
- attached short payloads such as `-Lmain` and `-S/tmp/tmux.sock`
- modes that forward the remaining argv tail verbatim
- root execution when no explicit subcommand token is present

Use these `cl-cli` features:

- `application-argv` or `extract-application-argv` before `run-app` — see
  [CLI Behavior](cli-behavior.md#launcher-aware-argv-normalization)
- short value options with `:short` plus `:kind :value`
- `:stop-parsing-p t` when a mode must forward the remaining tail unchanged
- root `:handler` or `:default-command` for no-subcommand entry points — see
  [Commands and Dispatch](commands.md#command-shapes)

Existing coverage: attached short value parsing is shown in the
`-S/tmp/tmux.sock` example in [Option Values and
Kinds](option-values.md#option-kinds); root/default dispatch is exercised by
"dispatches default command without command token" in
[t/parser-option-consumption-test.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/t/parser-option-consumption-test.lisp).

## `private-trade-fx`

`private-trade-fx` needs a stricter "single binary" interface:

- flat value options without subcommand routing
- hard failures for unknown options and missing required values
- built-in `--help`
- preservation of arguments after `--`
- option-local parsers for domain validation such as positive integers

Use these `cl-cli` features:

- app-level `:global-options` without defining commands
- the default strict parser behavior for unknown and malformed input
- built-in help/version handling
- `strip-argv-separators` only when downstream logic should hide the separator
- `:parser` on options and positionals for domain-specific validation — see
  [Validation and Exit Codes](validation.md#custom-parsers)

Existing coverage: parser-hook validation is demonstrated in the
positive-integer example in [Validation and Exit
Codes](validation.md#custom-parsers); separator-preserving and
separator-normalizing flows are covered by "extracts application argv after
separator" and "strip-argv-separators removes literal sentinels" in
[t/parser-dispatch-test.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/t/parser-dispatch-test.lisp).

## `nshell`

`nshell` needs a shell-like root entry point with a few special launch modes:

- root execution with no args
- built-in `--help`, `-h`, `--version`, and `-V`
- `-c COMMAND [ARGS...]`
- a leading script file followed by rest arguments

Use these `cl-cli` features:

- app-level `:handler` for the zero-arg root path
- built-in help/version flags
- `:stop-parsing-p t` on `-c`
- root positionals with a trailing `:rest-p t` positional for script argv —
  see the [root positional example](quick-start.md#root-positional-example)

Existing coverage: root positional parsing is shown in the `script-runner`
example in [Quick Start](quick-start.md#root-positional-example);
root/default dispatch behavior is covered by "supports root positionals and
rest" and "dispatches root handler" in
[t/parser-dispatch-test.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/t/parser-dispatch-test.lisp).

## Verification path

For the four target CLIs above, the remaining migration work is
consumer-side spec translation, not new parser primitives in `cl-cli`.

1. Read the representative specs in
   [examples/consumer-migrations.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/examples/consumer-migrations.lisp).
2. Load the system with ASDF.
3. Run [tests/run-tests.lisp](https://github.com/nerima-lisp/cl-cli/blob/main/tests/run-tests.lisp).
4. If you launch through SBCL, Nix, or a wrapper script, normalize argv first
   with `application-argv`.
