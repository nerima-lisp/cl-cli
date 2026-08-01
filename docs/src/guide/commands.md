# Commands and Dispatch

## Command shapes

Use `:default-command` when a subcommand app should dispatch a command even
without an explicit command token. Use root `:positionals` plus a root
`:handler` for script-style CLIs such as `SCRIPT [ARGS...]` — see the [root
positional example](../getting-started.md#root-positional-example). Conversely, pass
`:require-command t` to `make-app` when a subcommand is mandatory: parsing
then fails with `cli-unknown-command` (listing the available commands) if the
root is invoked without one.

## Nested subcommands

A command may declare its own `:subcommands`, so it dispatches like a mini-app
(`git remote add`). The next non-option token after the command selects a
subcommand, and the parent command's options remain available to the whole
subtree; global options and counters accumulate across the entire path:

```lisp
(cl-cli:make-app
 :name "git"
 :global-options (list (cl-cli:make-option :name "verbose" :short #\v :kind :count))
 :commands
 (list (cl-cli:make-command
        :name "remote"
        :options (list (cl-cli:make-option :name "porcelain" :kind :flag))
        :subcommands
        (list (cl-cli:make-command
               :name "add"
               :positionals (list (cl-cli:make-positional :key :name :required-p t)
                                  (cl-cli:make-positional :key :url :required-p t))
               :handler (lambda (invocation)
                          (format t "add ~A ~A~%"
                                  (cl-cli:positional-value invocation :name)
                                  (cl-cli:positional-value invocation :url))))))))
```

`git -v remote --porcelain add origin URL` dispatches the `add` handler with
the global `--verbose` count and the parent `--porcelain` flag both visible.
Nesting works to arbitrary depth. `invocation-command` is the dispatched leaf
command and `invocation-command-path` is the full root-to-leaf chain. Command
help renders a path-qualified usage line (`Usage: git remote add ...`) and
lists a command's subcommands, and the man/Markdown/JSON renderers recurse
through the tree.

A parent command keeps its own `:handler` and `:positionals`: with no
subcommand token they still run, and when it has no handler either, running it
bare prints that command's help listing its subcommands. A mistyped
subcommand of a command that takes no positionals signals
`cli-unknown-command` with a spelling suggestion. A command may also declare
a `:default-command` naming one of its own subcommands to dispatch when no
subcommand token is present, mirroring the app-level `:default-command`.

## Declarative DSL

`define-app` and `define-command` are additive sugar over `make-app` /
`make-command` / `make-option` / `make-positional` — everything above this
section still applies; the macros just expand into those same functional
calls, expressing a spec as a flat list of clauses instead of nested
`:global-options (list ...)` / `:positionals (list ...)` / `:commands (list
...)` keyword arguments:

```lisp
(cl-cli:define-app *app*
    (:name "demo" :version "0.1.0")
  (:option "verbose" :short #\v :kind :flag)
  (:command "compile"
      (:aliases '("build")
       :handler (lambda (invocation)
                  (format t "compile ~A -> ~A~%"
                          (cl-cli:positional-value invocation :input)
                          (cl-cli:option-value invocation :output))))
    (:option "output" :short #\o :kind :value)
    (:positional :input :required-p t)))

(cl-cli:run-app *app* :argv '("demo" "compile" "-o" "out.bin" "input.lisp"))
```

Each clause is headed by `:option`, `:positional`, `:command`, or
`:commands-from`. A `:command` clause nests the same clause vocabulary for
that command's own options, positionals, and (recursively) subcommands.
Everything besides `:option` / `:positional` / `:command` — `:name`,
`:aliases`, `:handler`, `:description`, and so on — is passed straight
through to the underlying constructor as ordinary keyword arguments; the
macro only owns the `:global-options` / `:positionals` / `:commands` (or
`:options` / `:positionals` / `:subcommands` for `define-command`) keys, so a
clause list must not repeat them.

`define-command` binds a reusable command spec with the same clause
vocabulary, so it can be shared across more than one app. Splice in a list of
already-built commands — `make-standard-commands`, or a command shared via
`define-command` — with `:commands-from`:

```lisp
(cl-cli:define-command *status-command*
    (:name "status" :description "Show status.")
  (:option "json" :kind :flag))

(cl-cli:define-app *ops-app*
    (:name "ops")
  (:commands-from (cl-cli:make-standard-commands))
  (:commands-from (list *status-command*)))
```

## Aliases

`cl-cli:command-by-name` resolves both primary command names and aliases
case-insensitively among the app's top-level commands, which is useful when
custom commands need to reuse the same lookup semantics as the built-in `help`
command. Command aliases are shown in the command list and included in
generated completion candidates.

```lisp
(cl-cli:make-command :name "remove" :aliases '("rm" "delete") ...)
```

## Grouping large command surfaces

For larger CLIs, group related commands in app help without changing parsing:

```lisp
(list
 (cl-cli:make-command :name "compile"
                      :group "Build"
                      :description "Compile sources.")
 (cl-cli:make-command :name "test"
                      :group "Build"
                      :description "Run tests.")
 (cl-cli:make-command :name "doctor"
                      :group "Diagnostics"
                      :description "Inspect the environment."))
```

## Deprecating commands and options

Options and commands can be marked `:deprecated` (with an optional reason
string); they stay usable and visible but are annotated as deprecated in help
and generated docs, and a deprecated command prints a stderr warning when run.

## Curated examples in help

When help text should stay aligned with README snippets or a manpage, attach
examples to the app or command spec and let generated help reuse them:

```lisp
(cl-cli:make-app
 :name "demo"
 :examples '("demo compile src/main.lisp"
             "demo test --filter smoke")
 :commands
 (list
  (cl-cli:make-command
   :name "compile"
   :examples '("demo compile -o out.fasl src/main.lisp"))))
```

## Help output is context-sensitive

- command help includes an `[options]` usage token when the command or app
  has options
- subcommand apps render dispatch-oriented usage such as
  `Usage: demo [global-options] <command> [args]`
- app and command specs can expose curated `:examples` lines directly in help
- command aliases are shown in the command list
- command lists can be grouped with `:group` for large subcommand surfaces
- invalid app specs fail fast during `make-app`, not only during parsing
- spec constructors reject empty strings for user-facing identifiers such as
  names, aliases, value names, env vars, choices, completion candidates,
  groups, and examples
- app, command, and option names are restricted to safe identifier characters
  (letters, digits, `-`, `_`, `.`), so author- or config-supplied names cannot
  inject shell syntax into generated completion scripts
- two options may not resolve to the same key (for example via
  case-differing single-character names), since that would silently
  misassign or overwrite parsed values
- an option may not reuse the reserved `:help`/`:version` key
- unknown commands and options suggest the nearest known spelling when the
  typo is close enough
- `--version` is only shown in help when the app has a version string

See [Validation and Exit Codes](validation.md) for how handler return values
map to process exit codes, and [Option Relations and
Grouping](option-relations.md) for cross-option validation that spans an
entire command's options.
