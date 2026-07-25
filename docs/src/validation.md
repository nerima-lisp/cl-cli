# Validation and Exit Codes

## Custom parsers

When a domain rule does not fit a built-in [`:type`](option-values.md#typed-values),
option and positional parsers remain the right place for custom validation:

```lisp
(cl-cli:make-option
 :name "count"
 :kind :value
 :parser (lambda (value)
           (let ((number (parse-integer value)))
             (unless (plusp number)
               (error "Expected a positive integer."))
             number)))
```

Parser failures are reported as `cl-cli:cli-invalid-option-value` or
`cl-cli:cli-invalid-positional-value`, so `run-app` treats them as usage
errors instead of internal failures. Command handlers may return an integer
to choose the process exit code.

## Exit codes

`run-app` returns `0` on success — or the handler's own integer return value,
when it returns one — `64` (`EX_USAGE`) for a `cli-usage-error`, and `70`
(`EX_SOFTWARE`) for any other unhandled error — the BSD `sysexits.h`
conventions. Pass `:usage-exit-code` and/or `:error-exit-code` to match a
different policy (for example `:usage-exit-code 2` to mirror `argparse`):

```lisp
(cl-cli:run-app *app* :argv argv :usage-exit-code 2 :error-exit-code 1)
```

## Knowing where a value came from

`option-value-source` reports the provenance of an option value — one of
`:command-line`, `:env`, `:config`, or `:default` (or `nil` when the option
was never set). This is the analogue of clap's `ArgMatches::value_source`,
and lets a handler tell an explicit user choice apart from a fallback — the
key to "only override when the user actually set it" and to layered-config
merges:

```lisp
(lambda (invocation)
  (when (eq (cl-cli:option-value-source invocation :output) :command-line)
    (override-output (cl-cli:option-value invocation :output)))
  0)
```

`invocation-option-sources` exposes the full key → source map when a handler
needs to inspect provenance for more than one option at once.

## Handler I/O

Handlers can write through the invocation streams when `run-app` is used,
rather than assuming `*standard-output*` / `*error-output*`:

```lisp
(lambda (invocation)
  (format (cl-cli:invocation-stdout invocation) "ok~%")
  0)
```

## Conditions

Every condition below subclasses `cli-usage-error`, so `run-app` maps them all
to `:usage-exit-code`. Specification errors (invalid `make-app` /
`make-command` / `make-option` / `make-positional` arguments) signal
`cli-invalid-specification` — also a `cli-usage-error` subclass — immediately,
before any parsing happens.

Concrete usage conditions include `cli-unknown-option`, `cli-unknown-command`,
`cli-missing-option-value`, `cli-missing-dependent-option`,
`cli-missing-any-of-options`, `cli-conflicting-options`,
`cli-missing-positional`, `cli-invalid-option-value`,
`cli-invalid-positional-value`, and `cli-unexpected-argument`, each with
readers such as `cli-error-message` for structured handling — see the [API
Reference](api-reference.md#conditions) for the full list.
