# Option Values and Kinds

## Option kinds

Every option declares a `:kind`:

| Kind | Shape | Example |
| --- | --- | --- |
| `:flag` | boolean presence, no value | `--verbose` |
| `:boolean` | positive/negated pair | `--threads` / `--no-threads` |
| `:value` | takes one value | `--output out.bin` |
| `:optional-value` | value optional, bare or attached | `--coverage`, `--coverage=mcdc` |
| `:count` | repeatable counter, defaults to `0` | `-vvv` → `3` |
| `:key-value` | `key=value` pairs accumulated into an alist | `-D a=1 -D b=2` |

```lisp
(cl-cli:make-option :name "verbose" :short #\v :kind :count
                    :description "Increase verbosity.")

(cl-cli:make-option :name "define" :short #\D :kind :key-value)
;; -D a=1 -D b=2  =>  (("a" . "1") ("b" . "2"))
```

A `:key-value` option parses each occurrence as `key=value` — a bare `key`
records value `t` — and accumulates the pairs into an alist, matching the
compiler-define / container-env shape used by tools such as `docker run -e`
or `cc -D`.

Boolean options accept positive and auto-generated negated long forms: a
`:boolean` option named `"threads"` supports both `--threads` and
`--no-threads`. Optional values accept bare and attached forms by default
(`--coverage` and `--coverage=mcdc`); pass `:consume-optional-value-p t` when
a CLI must also accept a separated non-option value such as `--coverage true`.

The built-in help/version flags are `--help`, `-h`, `--version`, and `-V`.
`--version` / `-V` are available only when the app declares a version string.
Value-bearing short options also accept attached forms out of the box, so
`-Lmain` or `-S/tmp/tmux.sock` parse without special-case handling.

## Typed values

Declare a `:type` instead of writing a `:parser` lambda for the common case of
numeric or boolean domain validation. Supported types are `:integer`,
`:number`, `:float`, `:boolean`, and the default `:string`; `:min` and `:max`
add inclusive bounds for numeric types. Both `make-option` and
`make-positional` accept them:

```lisp
(cl-cli:make-option :name "jobs"
                    :kind :value
                    :type :integer
                    :min 1
                    :max 64
                    :description "Parallel job count.")

(cl-cli:make-positional :key :port
                        :type :integer
                        :min 1
                        :max 65535)
```

A `:type` and an explicit `:parser` are mutually exclusive, `:min`/`:max`
require a numeric `:type`, and `:min` may not exceed `:max`; all three are
checked at `make-*` time. The resolved type and range appear in help metadata
(for example `type: integer; range: 1..64`). Type failures and out-of-range
values are reported as `cl-cli:cli-invalid-option-value` /
`cl-cli:cli-invalid-positional-value` — see
[Validation and Exit Codes](validation.md). Numeric parsing binds
`*read-eval*` off, so a crafted value can never execute code.

## Repeatable, delimited, and multi-token values

Value-bearing options can be made repeatable with `:multiple-p t`; repeated
occurrences accumulate in input order and `option-value` returns a list:

```lisp
(cl-cli:make-option :name "include"
                    :short #\I
                    :kind :value
                    :multiple-p t
                    :default '("src"))
```

A `:value` option can also split a single occurrence into a list with
`:value-delimiter` (a single character), so `--tags a,b,c` yields
`("a" "b" "c")`. Each piece is parsed (honoring `:type`), repeated occurrences
keep accumulating, and a string or list `:default` and an environment value
are split the same way:

```lisp
(cl-cli:make-option :name "tags"
                    :kind :value
                    :value-delimiter #\,
                    :default '("core"))
```

A `:value` option can consume a fixed number of separate tokens with
`:value-count N`, returning a parsed list (`--point 1 2` ⇒ `(1 2)`); with
`:multiple-p` each occurrence contributes its own N-element list:

```lisp
(cl-cli:make-option :name "point" :kind :value :type :integer :value-count 2)
```

`:value-count` may also be `:+` (one or more) or `:*` (zero or more), which
greedily consume following tokens up to the next option-like token
(`--files a b c`); help shows the value as `<NAME>...`:

```lisp
(cl-cli:make-option :name "files" :kind :value :value-count :+)
```

## Choices

When an option accepts a closed set of CLI values, declare them once and let
both parsing and help output share the same source of truth:

```lisp
(cl-cli:make-option :name "mode"
                    :kind :value
                    :choices '("dev" "prod")
                    :description "Execution mode.")
```

Positionals accept `:choices` too, validated the same way (mismatches signal
`cli-invalid-positional-value`) and surfaced in help and JSON output:

```lisp
(cl-cli:make-positional :key :env
                        :required-p t
                        :choices '("dev" "prod"))
```

Unknown commands and options — and invalid `:choices` values — suggest the
nearest known spelling when the typo is close enough.

## File and directory hints

For file-path arguments, attach `:value-hint :file` or `:value-hint :dir` to
an option or positional; the generated bash, zsh, and fish completions then
offer file or directory completion at that slot (and the hint is shown in
help and JSON):

```lisp
(cl-cli:make-option :name "config" :kind :value :value-hint :file)
(cl-cli:make-positional :key :dir :value-hint :dir)
```

## Environment variables and layered config

Options may source their default from environment variables with `:env-var`
or `:env-vars`:

```lisp
(cl-cli:make-option :name "threads"
                    :short #\t
                    :kind :boolean
                    :env-var "APP_THREADS")
```

Callers may layer in values loaded from a config file by passing a `:config`
plist to `parse-argv` / `run-app`. The full precedence is
**CLI argument > environment variable > `:config` > literal `:default`**:

```lisp
(cl-cli:run-app *app*
                :argv (cl-cli:current-process-argv)
                :config '(:profile "prod" :threads 8))
```

The config plist is keyed by option key, and its values are coerced exactly
like a literal `:default` — a string is parsed through the option's
`:type`/`:parser`, a list is spread across a repeatable option, and a
delimited option splits a string value. Help output can surface this metadata
directly, including `:required-p`, `:default`, `:env-var` / `:env-vars`,
enumerated `:choices`, and option relationships. Use `option-value-source` at
runtime to tell an explicit CLI value apart from a fallback — see
[Validation and Exit Codes](validation.md).

## Positionals and rest arguments

`make-positional` mirrors most option facilities — `:type`, `:min`/`:max`,
`:choices`, `:value-hint`, and a custom `:parser` — plus positional-specific
shape:

```lisp
(cl-cli:make-positional :key :files :rest-p t :min-count 1 :max-count 8)
```

A rest positional (`:rest-p t`) collects every remaining token and can bound
how many values it accepts with `:min-count` / `:max-count` (too few signals
`cli-missing-positional`, too many `cli-unexpected-argument`). A required
positional may not follow an optional one — declaring one signals
`cli-invalid-specification` from `make-app`, since it would make the boundary
between them ambiguous at parse time.
