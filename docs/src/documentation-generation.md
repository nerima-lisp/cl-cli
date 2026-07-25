# Documentation Generation

Beyond interactive `--help`, `cl-cli` can render offline reference
documentation directly from an app spec, reusing the same option/command
metadata so the docs never drift from the parser. Both renderers follow the
completion renderers' stream contract (no stream returns a string; a stream
is written to and returns no values):

```lisp
(cl-cli:render-manpage *app*)   ; a section-1 man page (roff)
(cl-cli:render-markdown *app*)  ; GitHub-flavored Markdown reference
(cl-cli:render-json *app*)      ; machine-readable spec for tooling
```

The man page covers NAME, SYNOPSIS, DESCRIPTION, OPTIONS, ARGUMENTS,
COMMANDS, EXIT STATUS, EXAMPLES, and an ENVIRONMENT section for env-backed
options, plus SEE ALSO / AUTHORS sections and a `.TH` date when the app
declares `:see-also` / `:authors` / `:manual-date` (it passes
`mandoc -T lint` cleanly).

The Markdown output produces a title, a usage block, option/argument tables,
per-command sections, and examples.

`render-json` emits the declared spec — options, positionals, commands, and
their `:type`, range, delimiter, choices, and default metadata — as a
minified JSON object that external tooling can consume.

Hidden options and commands are omitted from all three renderers.

## The `docs` command

To let users generate these themselves, add the built-in `docs [FORMAT]`
command — the documentation counterpart to `completion [SHELL]`. It defaults
to `man` and also accepts `markdown` and `json`:

```lisp
(cl-cli:make-app
 :name "demo"
 :commands (append
            (cl-cli:make-standard-commands :include-docs-p t)
            (list ...)))
```

```bash
demo docs man       > demo.1
demo docs markdown  > docs/demo.md
demo docs json      > demo.schema.json
```

`cl-cli:render-docs` dispatches to the two renderers by format name if you
need the same routing without the command wrapper.

`cl-cli` uses its own renderers this way: this documentation site is written
by hand, but any consumer CLI can wire `docs markdown` into its own release
pipeline to keep a generated reference in sync with its parser automatically.
