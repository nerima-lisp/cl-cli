# Quick Start

```lisp
(ql:quickload :cl-cli)

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
```

`make-app` builds an immutable spec — name, version, global options, and a
list of commands. `run-app` parses an argv list against that spec and
dispatches the matched command's `:handler`, returning a process exit code.
Call `parse-argv` directly instead when you want the parsed invocation
without running a handler (useful for tests); note that it takes argv as a
required positional argument — `(cl-cli:parse-argv *app* '("demo" "compile"
"input.lisp"))` — rather than as `:argv`.

## Root positional example

Not every CLI needs subcommands. Attach `:positionals` and a `:handler`
directly to the app for script-style tools that dispatch on positional
arguments alone:

```lisp
(defparameter *script-app*
  (cl-cli:make-app
   :name "script-runner"
   :positionals (list (cl-cli:make-positional :key :script :required-p nil)
                      (cl-cli:make-positional :key :script-args :rest-p t))
   :handler (lambda (invocation)
              (format t "script=~S args=~S~%"
                      (cl-cli:positional-value invocation :script)
                      (cl-cli:positional-value invocation :script-args)))))
```

## Built-in help and version

Every app gets `--help` / `-h` for free, and `--version` / `-V` once the app
declares a `:version` string:

```console
$ sbcl --script demo.lisp -- --help
Usage: demo [global-options] <command> [args]
...
```

If you want `help` and `version` as real subcommands instead of (or in
addition to) the built-in flags, splice in `cl-cli:make-standard-commands`. It
returns `help` and `version` by default; `completion` and `docs` are opt-in via
`:include-completion-p t` / `:include-docs-p t` — see
[Shell Completion](shell-completion.md) and
[Documentation Generation](documentation-generation.md).

## Where to go next

- [Option Values and Kinds](option-values.md) — the six option kinds, typed
  values, delimiters, and repeatable options
- [Option Relations and Grouping](option-relations.md) — `:requires`,
  `:conflicts-with`, exclusive/inclusive groups, and help grouping
- [Commands and Dispatch](commands.md) — nested subcommands, aliases, and
  `:default-command` policy
- [Validation and Exit Codes](validation.md) — custom parsers,
  `option-value-source`, and exit-code conventions
- [Migration Guide](migration-guide.md) — mapping an existing hand-rolled
  parser onto `cl-cli`
