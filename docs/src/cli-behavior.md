# CLI Behavior

## Colored, width-aware help

`print-app-help`, `print-command-help`, and `run-app` accept `:color t` to
wrap headings and option/command names in ANSI styling, and `:width N` to
word-wrap descriptions to column N (continuation lines align under the
description gutter).

Both accept `:auto` for terminal-aware detection so the common case needs no
manual probing:

- `:color :auto` disables color when `NO_COLOR` is set, forces it on when
  `CLICOLOR_FORCE` is set to anything but `0`, and otherwise enables it only
  when the target stream is a terminal (isatty; SBCL probes the real
  descriptor, other implementations fall back to the environment rules).
- `:width :auto` reads `$COLUMNS`, wrapping to that width when it is a
  positive integer and leaving output unwrapped otherwise.

Explicit `t` / `nil` / integer values still force the decision, and the
defaults stay `nil` (no styling, no wrapping) so nothing changes unless you
opt in:

```lisp
;; Follow the terminal and the NO_COLOR / CLICOLOR_FORCE / COLUMNS conventions:
(cl-cli:run-app *app* :argv (cl-cli:current-process-argv) :color :auto :width :auto)

;; Or force it, as before:
(cl-cli:run-app *app* :argv (cl-cli:current-process-argv) :color t :width 80)
```

To suppress the built-in `-h` / `--help` flag entirely — for a CLI that
manages its own help or forwards `--help` to a wrapped tool — pass
`:auto-help nil` to `make-app` (a `help` command from `make-standard-commands`
still works).

## Response files

Pass `:expand-response-files t` to `make-app` to expand a `@path` argument
into the whitespace-separated arguments read from that file before parsing
(useful when a command line grows past a shell's length limit). Expansion is
recursive, `@@` yields a literal leading `@`, and a missing file signals a
usage error:

```lisp
(cl-cli:run-app (cl-cli:make-app :name "tool" :expand-response-files t ...)
                :argv '("tool" "@args.txt"))
```

## Abbreviated options

Pass `:allow-abbreviated-options t` to `make-app` for GNU-style prefix
matching, where a unique unambiguous prefix of a long option stands in for the
full name (`--verb` for `--verbose`). An ambiguous prefix signals
`cli-unknown-option` listing the candidates, and an exact match always wins
over a longer option that merely shares the prefix. It is off by default to
preserve strict exact-match parsing.

## Negative-number arguments

By default a token like `-5` is parsed as a short-option cluster (and
rejected if `5` is not an option). Pass `:allow-negative-numbers t` to
`make-app` so a token that looks like a negative number (`-5`, `-1.5`) is
instead kept as a positional or option value — useful for numeric CLIs:

```lisp
(cl-cli:make-app :name "calc" :allow-negative-numbers t
                 :positionals (list (cl-cli:make-positional :key :n :type :number)))
```

## Interspersed arguments

Command and global options may also appear after command positionals when a
consumer CLI expects interspersed arguments, such as
`demo compile input.lisp --output out.fasl --verbose`.

## Stopping parsing for opaque tails

Use `:stop-parsing-p t` for options such as shell `-c COMMAND [ARGS...]`
where the option consumes one value and every following token — including
flag-like tokens — must remain positional arguments:

```lisp
(cl-cli:make-option :name "command"
                    :short #\c
                    :kind :value
                    :stop-parsing-p t)
```

For script-style options such as `--script FILE [ARGS...] [-- ...]`, keep the
opaque tail in a rest positional and normalize away a literal `--` separator
only when the downstream script runner should not see it:

```lisp
(let* ((app (cl-cli:make-app
             :name "cl-cc"
             :global-options
             (list (cl-cli:make-option :name "script"
                                       :kind :value
                                       :stop-parsing-p t))
             :positionals
             (list (cl-cli:make-positional :key :script-argv :rest-p t))))
       (invocation
        (cl-cli:parse-argv app
                           '("cl-cc" "--script" "ci/build.lisp"
                             "--" "--target" "release"))))
  (values
   (cl-cli:option-value invocation :script)
   (cl-cli:strip-argv-separators
    (cl-cli:positional-value invocation :script-argv))))
```

## Launcher-aware argv normalization

Use `application-argv` when a launcher such as SBCL or Nix inserts runtime
tokens before the real CLI arguments. It applies the library's default
SBCL/Nix runtime markers:

```lisp
(cl-cli:application-argv
 :argv (cl-cli:current-process-argv))

(cl-cli:application-argv
 :argv (cl-cli:current-process-argv)
 :separator "--")
```

Use `extract-application-argv` directly when a consumer needs fully custom
runtime markers:

```lisp
(cl-cli:extract-application-argv
 :argv (cl-cli:current-process-argv)
 :runtime-markers '("--no-userinit" "--end-toplevel-options"))
```

See [Migration Guide](migration-guide.md#cl-tmux) for a worked example of
normalizing launcher-inserted tokens before parsing.
