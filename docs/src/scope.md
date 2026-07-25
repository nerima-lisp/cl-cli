# Scope and Non-Goals

`cl-cli` aims for feature parity with the mainstream CLI frameworks (clap,
cobra, click, argparse) on everything that is fundamentally a *parsing,
dispatch, help, or completion* concern.

A few capabilities those frameworks offer are deliberately left to the
application, because they are runtime-I/O or policy concerns rather than
argument handling:

- **Interactive prompting** for missing values, hidden/password input, and
  confirmation prompts (click's `prompt=` / `hide_input=`). Reading a
  terminal with echo disabled is an I/O concern; clap and cobra defer it too.
  A handler can prompt from `invocation-stdout` / `invocation-stderr` as
  needed.
- **Filesystem-touching validators** (existence/readability checks). Declare
  intent with `:value-hint :file` / `:dir` for completion, and enforce with a
  custom `:parser`; whether a path must already exist is per-app policy.
- **Config-file *parsing*** (TOML/YAML). The `:config` layer accepts an
  already-parsed plist and slots it between environment variables and
  literal defaults (see
  [`option-value-source`](validation.md#knowing-where-a-value-came-from));
  choosing and reading the file format stays with the caller.
- **Stdin values, progress bars, and completion-script installation** are
  pure runtime behavior; the library gives you a `-`-token you can
  special-case, the streams to draw on, and `render-*-completion` output to
  install where you like.

Everything else the reference frameworks expose — including terminal-aware
color/width, value provenance, "did you mean" suggestions, and configurable
exit codes — is built in and covered in the [Guide](option-values.md).
