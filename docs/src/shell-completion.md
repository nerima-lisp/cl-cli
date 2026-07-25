# Shell Completion

## Static completion scripts

Generate a static completion script directly from the app definition:

```lisp
(write-string
 (cl-cli:render-completion *app* "bash")
 *standard-output*)
```

Shell-specific renderers are also available:

```lisp
(cl-cli:render-bash-completion *app*)
(cl-cli:render-zsh-completion *app*)
(cl-cli:render-fish-completion *app*)
```

Like `format`, these renderers take an optional stream: called with no stream
they return the script as a string, and called with a stream they write to it
and return no values. Pass an explicit stream to avoid building an
intermediate string:

```lisp
(cl-cli:render-completion *app* "bash" *standard-output*)
```

If you want a standard built-in `completion` subcommand, splice
`cl-cli:make-standard-commands` into the app's commands with
`:include-completion-p t` (it also returns `help` and `version` by default;
`version` prints just the app name when the app has no version string):

```lisp
(setf *app*
      (cl-cli:make-app
       :name "demo"
       :commands (append
                  (cl-cli:make-standard-commands
                   :include-completion-p t)
                  (list ...))))
```

Then users can install completion with:

```bash
eval "$($(command -v demo) completion bash)"
```

For Zsh and Fish:

```bash
autoload -U compinit && compinit
source <($(command -v demo) completion zsh)

source <($(command -v demo) completion fish)
```

Current built-in support is `bash`, `zsh`, `fish`, `powershell` (alias
`pwsh`), `nushell` (alias `nu`), and `elvish`. Generated completion offers
command names, their options, and positional values from a positional's
`:choices` or `:completion-candidates`. The bash, zsh, and fish completers
descend the full nested-subcommand tree (`app remote add`, with each level's
accumulated option scope); the remaining shells complete the top command level
(PowerShell additionally narrows options to a top-level subcommand, as below). Hidden commands and hidden options are omitted from the generated
script. Aliases are included in generated completion candidates. Options
declared with `:choices` also feed shell value completion candidates.

The PowerShell renderer emits a `Register-ArgumentCompleter -Native` script
block that suggests subcommands and option tokens, switching to a
subcommand's own options once that subcommand appears on the line; the
Nushell renderer emits an `export extern` module covering subcommands and
global option flags:

```lisp
(cl-cli:render-powershell-completion *app*)
(cl-cli:render-nushell-completion *app*)
```

## Curated candidates independent of validation

When a CLI accepts free-form values but shell completion should still suggest
a curated set, keep validation open and attach `:completion-candidates`
separately. Candidates may be plain values or `(value . description)` pairs:

```lisp
(cl-cli:make-option :name "profile"
                    :kind :value
                    :completion-candidates '(("dev" . "Local development")
                                             ("prod" . "Production release"))
                    :description "Runtime profile.")
```

Use `:completion-candidates` when shell suggestions should be broader or
differently documented than parser validation — `:choices` instead enforces
that the same set is the only thing the parser accepts (see [Option Values
and Kinds](option-values.md#choices)).

## Dynamic completion

For candidates that are only known at runtime (branch names, hostnames,
records in a database), attach a `:complete` function to an option and add the
hidden callback command with `make-standard-commands :include-dynamic-p t` (or
`make-complete-command`):

```lisp
(cl-cli:make-app
 :name "demo"
 :global-options (list (cl-cli:make-option
                        :name "branch"
                        :kind :value
                        :complete (lambda (partial)
                                    (remove-if-not
                                     (lambda (b) (eql 0 (search partial b)))
                                     (list-git-branches)))))
 :commands (cl-cli:make-standard-commands :include-dynamic-p t))
```

All six generated completions — bash, zsh, fish, PowerShell, nushell, and
elvish — then call `demo __complete branch <partial>` at completion time and
offer whatever the function prints:

- bash, zsh, PowerShell, and elvish match the token before the cursor against
  the app's dynamic options, then shell out
- fish attaches the callback per option, as a `complete -a '(command ...)'`
  expression
- nushell attaches a per-flag custom completer

Because the shell already knows which slot it is completing, the callback
only receives the option key and the partial word — the full command line is
never re-parsed. A candidate may be a plain string or a `(value . description)`
cons; descriptions are emitted tab-separated and shown by shells that support
them.

A positional may also declare `:complete`, and `__complete` resolves positional
keys, but no generated script wires a positional slot to the callback — only
options are.

`cl-cli:render-complete-reply` performs the same lookup directly if you wire
the callback yourself instead of using `make-complete-command`.
