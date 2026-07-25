# Changelog

All notable user-visible changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Conformance work against the org's
[PACKAGE_STANDARD.md](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).
No behavior of the `cl-cli` system itself changed; its dependency set is still
`uiop` alone.

### Changed

- **The test systems were renamed.** `cl-cli/tests` is now `cl-cli/test`, and
  `cl-cli/tests/shell-verification` is now `cl-cli/test/shell-verification`,
  matching the org-wide `<pkg>/test` convention. The Lisp package
  `cl-cli/tests` was renamed to `cl-cli/test` to match. Anything calling
  `(asdf:test-system "cl-cli/tests")` directly must be updated;
  `(asdf:test-system "cl-cli")` is unaffected.
- **Tests moved from `tests/` to `t/`,** and the loader moved from
  `tests/run-tests.lisp` to `run-tests.lisp` at the repository root. The
  documented invocation is now
  `sbcl --non-interactive --load run-tests.lisp --eval '(cl-cli/test:run-tests)' --quit`.
- **`flake.nix` declares `x86_64-linux` and `aarch64-darwin` only.**
  `aarch64-linux` and `x86_64-darwin` were declared but never built or tested
  anywhere, so the flake no longer advertises them.
- Sibling flake inputs are pinned to release tags instead of tracking each
  repository's default branch, so an upstream push can no longer break this
  repository's CI without warning.

### Added

- `packages.default` (`sbcl.buildASDFSystem`), `apps.test`, `checks.formatting`
  (treefmt/nixfmt) and `nix fmt` in `flake.nix`. `checks.default` is the SBCL
  suite; the ECL suite is `checks.ecl`.
- `release.yml` and `flake-update.yml` workflows, and a `nix-setup` composite
  action shared by all four workflows. Every `uses:` is pinned to a
  40-character commit SHA.

### Removed

- `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `RELEASING.md`, `SECURITY.md` and
  `SUPPORT.md`. These are served org-wide from
  [nerima-lisp/.github](https://github.com/nerima-lisp/.github); the parts
  specific to this repository moved to `docs/src/development.md`.

### Fixed

- The documentation claimed the ECL check "currently fails". It has passed
  since the test suite was split at the system boundary; the shell-verification
  half is simply excluded there.

## [1.0.1] - 2026-07-26

Three renderer bugs that 1.0.0 shipped with, found by an adversarial audit that
reported after the tag went out. All three were reproduced against the real
consumer — elvish, zsh, and GitHub's own `cmark-gfm` — before and after the
fix, and each now has a regression test that fails on the old behavior.

### Fixed

- **Elvish dynamic completion threw on every Tab.** The renderer emitted
  `e:'app' __complete ...`; elvish's `e:` external-command namespace accepts
  only a bare word, so quoting the app name parsed as the bareword `e:`
  concatenated with a string, producing the plain string `"e:app"` — which
  elvish then refused to call (`command must be callable or string containing
  slash`). Any app with a `:complete` option was affected. Now emits
  `(external 'app')`, which takes a real string argument and so also stays
  correct for a name that needs quoting — dropping the quotes would have fixed
  the common case and broken that one.

  Two things let this ship: `elvish -compileonly` cannot see a runtime value
  error, and `tests/cases-dynamic-completion.lisp` asserted the broken string
  verbatim. The new check in `tests/cases-shell-verification.lisp` runs the
  generated completer and asserts on what it returns.
- **zsh truncated any candidate value containing a colon.** `_describe` splits
  each entry at the first unescaped colon, and only the description half was
  being sanitized. A candidate `host:8080` completed as `host`, with `8080`
  folded into the description — a silently wrong insertion, on exactly the
  `host:port` shape a candidate list tends to carry. The value half is now
  backslash-escaped (it cannot be sanitized the way the description is, since
  it is the text inserted on the command line). Only affected options whose
  candidates carry descriptions; a bare `:choices` list takes the `compadd`
  path, which was already correct.
- **Markdown tables broke on a `|` in a value name.** `%md-inline-code`
  renders the first column of every option and argument table but did not
  escape pipes, and a GFM cell ends at the first unescaped `|` even inside a
  code span. `--fmt <json|yaml|toml>` split its row across the wrong cells,
  destroyed the code span, dropped `toml>`, and lost the description column
  entirely. Verified against `cmark-gfm`. The escape is scoped to table cells;
  the per-command heading, the other caller, must not have it.

### Changed

- The real-shell verification watchdog goes from 10s to 60s. It is not a
  budget -- it exists only so a wedged child cannot block the run -- and 10s
  was smaller than `pwsh`'s cold start inside the Nix sandbox (0.2s outside
  it), which turned `nix flake check` intermittently red. The self-test that
  pins the timeout mechanism uses its own short deadline, so it still proves
  the watchdog fires.
- The ECL check no longer preloads a newer ASDF. That was needed only for
  `cl-log-kit`'s ASDF >= 3.3.1 requirement, and `cl-log-kit` is no longer on
  ECL's path since the test systems were split — so the check now runs exactly
  the `ecl --norc --load tests/run-tests.lisp` line the documentation gives.

### Documentation

- `docs/src/README.md` still said "Status: Pre-1.0".
- `RELEASING.md` and `docs/src/releasing.md` said `:version` appears twice in
  `cl-cli.asd`; the test-system split made it three, and a release that
  followed the old instruction would have shipped a mismatched system.
- README described the dynamic-completion mechanism backwards (it is bash,
  zsh, PowerShell and elvish that match the token before the cursor; fish is
  the one attaching per option), and both README and the guide claimed all six
  shells pass the partial word — nushell does not, and asks for the whole list
  instead, so a `:complete` callback sees an empty prefix there.
- `CONTRIBUTING.md` pointed new tests at `tests/run-tests.lisp`, which is the
  loader; it now names the `tests/cases-*.lisp` file and which of the two test
  systems a case belongs to, and warns against the assert-the-current-output
  habit that let the elvish bug through.
- README's constructor list omitted `define-app` / `define-command`.

## [1.0.0] - 2026-07-26

The API is now covered by Semantic Versioning. What that promise does and does
not cover is written down in
[docs/src/compatibility.md](https://github.com/nerima-lisp/cl-cli/blob/main/docs/src/compatibility.md),
along with the supported-implementation matrix and the deprecation policy.

This release is mostly about earning that promise rather than adding features.
The breaking changes below are deliberately concentrated here, because 1.0 is
the last point at which they are free: an accessor family that could not be
read, a condition taxonomy that made a programmer's bug look like a user's,
and a machine-readable format with no version marker would all otherwise have
been permanent. Verification was rebuilt to match: `nix flake check` was
previously guaranteed to fail, the checks that run generated scripts through
real shells were almost entirely skipping, and no non-SBCL implementation could
compile the suite at all.

### Added

- **The positional accessor family is exported.** `app-positionals`,
  `command-positionals`, and `make-positional` were all public, so callers
  legitimately received `positional-spec` structs -- but not one of its slot
  readers was exported, leaving them opaque unless you reached through
  `cl-cli::`. All sixteen are public now, renamed from the `positional-spec-`
  conc-name to `positional-` to match the `option-` / `command-` / `app-`
  families they sit beside. Also newly exported: `command-subcommands` and
  `command-default-command` (nested subcommands are a documented feature and
  `app-default-command` was already public), `option-group` plus
  `option-group-members` / `-mode` / `-required-p` (so a custom help renderer
  can render "exactly one of ..." instead of degrading to pairwise
  conflicts), and `built-in-option-specs` (so it can see the synthesized
  `--help` / `--version`). Between them, a third-party renderer can now
  reproduce everything the built-in one prints.
- **`cli-missing-required-option`**, a subtype of `cli-missing-option-value`
  for the single most common CLI mistake there is: a required option never
  supplied. It was previously indistinguishable from "`--output` typed with
  nothing after it". Being a subtype, a handler that does not need the
  distinction is unaffected.
- **`cli-response-file-error`** (with a `cli-response-file-error-path`
  reader), for the three `@file` expansion failures that previously signaled
  a bare `cli-usage-error` -- "your `@args.txt` is missing" deserves a
  different message from "you mistyped a flag".
- **Docstrings on every exported condition class and slot reader.** The
  condition hierarchy is the primary integration point for a consumer CLI and
  had no prose at all; `cli-invalid-option-value-cause` in particular was
  unguessable.
- `tests/cases-public-api.lisp`, which pins the exported symbol set in both
  directions. `:export` fails silently in the direction that matters -- a
  misspelled name interns a dead symbol rather than signaling -- and no other
  test would notice, since they all call these symbols from a package that
  `:use`s `cl-cli`. It also asserts that every exported condition is reachable
  from `cli-error` and that `cli-invalid-specification` stays out of the
  `cli-usage-error` branch.
- **`render-json` now emits a `schemaVersion` member first**, and exports
  `+json-schema-version+` (currently `1`). A machine-readable format with no
  version marker gives a consumer nothing to branch on; a tool written against
  today's shape would silently misread a future one. Adding it now, at the
  1.0 boundary, is the last point where it costs nothing. New members may
  still appear in a minor release -- readers should ignore unknown members --
  but a change that would break a reader of the previous shape bumps the
  number. **This changes `render-json` output**; a consumer that parses the
  0.3.0 document and rejects unknown keys needs updating.
- **`docs/src/compatibility.md`**, stating what the version number promises
  now that the project is on Semantic Versioning for real: the exported
  symbols of the `CL-CLI` package are covered, `cl-cli::` internals and the
  byte-for-byte text of rendered help/completion/man output are not, plus a
  supported-implementation matrix and a deprecation policy.
- Dedicated unit tests for the PowerShell, Nushell, and Elvish completion
  renderers (`tests/cases-completion-powershell.lisp`, `-nushell.lisp`,
  `-elvish.lisp`). Three of the six shipped renderers previously had no
  assertions on what they emit at all -- only a performance benchmark and a
  "does it parse" smoke check.
- An Elvish leg in `tests/cases-shell-verification.lisp`: the generated script
  is compiled by real `elvish -compileonly`. Because `elvish` only exposes its
  `edit:` module interactively, the check binds `edit:` to a stub namespace so
  the generated code itself is what gets compiled; a negative-control case
  asserts that a deliberately broken completer still fails, so the check
  cannot pass vacuously.

### Changed

- **`cli-invalid-specification` is no longer a `cli-usage-error`.** A new
  `cli-error` root splits the hierarchy in two: `cli-usage-error` for what the
  *user* typed, `cli-invalid-specification` for what the *programmer*
  declared. The idiomatic
  `(handler-case (run-app ...) (cli-usage-error (e) (print-usage) (exit 2)))`
  previously swallowed the developer's own malformed spec and answered it with
  a usage message shown to the end user. If such an error does reach
  `run-app`, it now exits with `:error-exit-code` (`70`, `EX_SOFTWARE`)
  instead of `:usage-exit-code` (`64`, `EX_USAGE`) -- which is what a bug in
  the program actually is. In practice the condition is raised while the spec
  is being built, before parsing.
  `cli-error-app` / `cli-error-command` are the new names for the context
  readers; `cli-usage-error-app` / `-command` still read the same slots.
- **The test suite is split into two ASDF systems.** `cl-cli/tests` is the
  portable core; `cl-cli/tests/shell-verification` adds the checks that shell
  out to real tools and is the only half that needs `cl-process-kit`. The
  transitive `cl-log-kit` dependency hard-codes `sb-thread:*`
  ([upstream #1](https://github.com/nerima-lisp/cl-log-kit/issues/1)), which
  previously made the *entire* suite fail to compile on any non-SBCL
  implementation. **ECL now runs 637 tests green** instead of not building.
  `tests/run-tests.lisp` prints which half it loaded, so a run covering less
  than expected cannot be mistaken for a pass.
- The fuzz suite and the benchmark budgets are now gated on the capability
  each actually needs, rather than failing where it is absent: the fuzz suite
  needs `cl-weave`'s `:timeout` platform capability, and the benchmark
  thresholds are absolute milliseconds calibrated against SBCL. Both report as
  skips with a reason. No threshold was widened and no assertion was removed.
- The benchmark workloads are resized so contention on a shared CI runner
  cannot fail them. One case measured 520ms idle and 2534ms against a 2000ms
  budget inside a concurrent `nix flake check` -- a flaky gate, and an
  intermittently red check gets read as noise, which is how a real regression
  gets waved through. Each case now targets an idle median around a tenth of
  its budget; the 2000ms convention itself is unchanged, since raising it is
  the one response that keeps the test green while destroying what it
  measures.
- `nix flake check` is green again, and now means something it did not before.
  The `ecl` check was previously guaranteed to fail, so CI on `main` was
  permanently red. Alongside the split above:
  - the flake defines outputs for `aarch64-linux`, `x86_64-darwin`, and
    `aarch64-darwin` as well as `x86_64-linux`, so `nix develop` and
    `nix flake check` work on a macOS machine instead of silently checking
    nothing;
  - the checks put `bash`, `zsh`, `fish`, `nushell`, `pwsh`, `elvish`, and
    `mandoc` on `PATH`. The shell-verification cases skip themselves when a
    tool is missing, so in CI they had been skipping almost entirely -- the
    generated scripts were never actually run by the shells that consume
    them. The SBCL suite is now 664 passed, **0 skipped**;
  - the documentation build is a check too, so a broken docs link fails CI
    rather than the Pages deploy.
- CI runs the flake check on `aarch64-darwin` as well as `x86_64-linux`, so
  the macOS support the project claims is verified rather than assumed.
- `consume-value-option` (`src/parser-option-consumption.lisp`) had a
  provably unreachable `:flag`-kind guard clause -- its sole call site is
  the `(:value :optional-value :key-value)` case arm of
  `consume-long-option-token`, so `(option-kind spec)` can never be `:flag`
  inside its body. Removed as dead code; no observable behavior changed.
- Bumped `cl-weave`, `cl-process-kit`, `cl-boundary-kit`, `cl-log-kit`, and
  `cl-json-kit` to their latest upstream revisions (`cl-prolog` was already
  current). Verified `cl-boundary-kit`'s new default 60-second process
  timeout (previously unbounded when `:timeout` was omitted) doesn't affect
  `cl-cli`: every `process-kit:run` call site in the test suite already
  passes an explicit `:timeout`.

### Security

- `expand-response-files` (`:expand-response-files t`) had no bound on the
  total bytes read across a response-file expansion -- only
  `+response-file-max-depth+` limited nesting depth, not fan-out (many
  files referenced at one depth) or a single huge file. A caller piping a
  response-file *path* derived from untrusted input into an app that
  opted into response-file expansion could exhaust memory. Added
  `+response-file-max-total-bytes+` (8 MiB, generous for any legitimate
  argument list) as a total-size budget checked after every file read;
  exceeding it signals `cli-usage-error` the same way exceeding the depth
  limit already did.

## [0.3.0] - 2026-07-25

### Added

- A full MkDocs (Material) documentation site under `docs/`, published to
  GitHub Pages via `nix build .#docs` and `.github/workflows/docs.yml`.
  Covers installation, a quick start, a per-topic guide (option values,
  option relations, commands, validation, CLI behavior, shell completion,
  documentation generation), an API reference, the migration guide, scope
  and non-goals, and the project's governance documents.
- `define-app` / `define-command` (`src/model-dsl.lisp`): a declarative,
  clause-based DSL over `make-app` / `make-command` / `make-option` /
  `make-positional`. `:option`, `:positional`, and `:command` clauses replace
  the nested `:global-options (list ...)` / `:positionals (list ...)` /
  `:commands (list ...)` keyword arguments; `:command` clauses nest the same
  vocabulary for a command's own options, positionals, and subcommands, and
  `:commands-from` splices in an already-built command list (e.g.
  `make-standard-commands`, or another spec bound via `define-command`).
  Purely additive -- the functional API is unchanged and remains
  independently usable. See README's "Declarative DSL" section.
- Adopted [`cl-json-kit`](https://github.com/nerima-lisp/cl-json-kit) as a
  test-only dependency (mirroring `cl-process-kit`'s test-only role): the
  `json renderer` test suite now parses `render-json`'s own output back
  through `cl-json-kit`'s independent reader as an additional correctness
  oracle, catching structural/escaping defects that substring-matching the
  writer's output can't. Not needed to use `cl-cli` itself.

### Fixed

- Two README code examples called `run-app` with `argv` as a positional
  argument instead of `:argv`, which signals `odd number of &KEY arguments`
  if copy-pasted as-is.

### Changed

- The Nushell and Elvish completion renderers' quoting functions
  (`%COMPLETION-NUSHELL-QUOTE`, `%COMPLETION-ELVISH-QUOTE`) and the
  Markdown documentation renderer's prose-escaping functions
  (`%MD-ESCAPE-PROSE`, `%MD-SINGLE-LINE`, `%MD-MAX-BACKTICK-RUN`, all in
  `src/doc-renderers-markdown.lisp`) had the same double-nested
  `WITH-OUTPUT-TO-STRING` pattern found and fixed in bash/zsh/PowerShell's
  quoting functions earlier in this changelog -- each ran its own escaping
  pass over the *already-built* result of a separate control-character-
  stripping pass, rather than folding both into one. `%MD-SINGLE-LINE`'s
  second pass turned out to be provably dead code once traced through
  (its input can never contain the newline/return characters it was
  checking for, since the upstream control-stripping pass already maps
  them to a space), so it now simply delegates. `%MD-MAX-BACKTICK-RUN`
  needed care: a character control-stripping *drops* entirely doesn't
  break a backtick run in the final output, while one it *maps to a
  space* does, so its merged single pass reproduces that distinction
  exactly rather than just concatenating both transformations (see the
  new regression test in `tests/cases-doc-markdown.lisp`, which checks a
  control character between two backticks counts as one run of 2 while a
  newline between them counts as two runs of 1). Nushell and Elvish
  completion rendering were separately profiled and found already fast
  enough (tens of microseconds per call on a 330-option benchmark app)
  that this fix's effect is not separately measurable there; it is applied
  for consistency with the other renderers, not for a measured win. No
  public API or observable output changed.
- The PowerShell completion renderer (`RENDER-POWERSHELL-COMPLETION`):
  `%COMPLETION-POWERSHELL-QUOTE` folds control-character-stripping and
  single-quote-doubling into one pass instead of two nested
  `WITH-OUTPUT-TO-STRING` calls (the same fix already applied to
  `%COMPLETION-SHELL-QUOTE` and `%COMPLETION-ZSH-ARGUMENTS-FIELD`), and
  `%COMPLETION-POWERSHELL-COMMAND-OPTION-MAP` now builds each command's
  option-array literal once and reuses it across every alias instead of
  rebuilding it (re-quoting every token again) per alias. (Profiled all
  four remaining completion renderers this round: nushell and elvish are
  already tens of microseconds per call -- optimizing them further would
  be immeasurable -- so only PowerShell needed work.) Measured on a
  330-option/33-command benchmark app: PowerShell rendering is roughly 1.3x
  faster. No public API or observable script output changed; see
  `tests/cases-parser-benchmark.lisp`.
- The fish completion renderer (`RENDER-FISH-COMPLETION`) no longer
  re-shell-quotes the same loop-invariant value on every iteration of a
  loop it's constant across: the app name, each level's "already seen a
  sibling command" condition, and each command's description are now
  quoted once and reused, instead of being re-quoted once per command
  alias, once per option candidate, or once per `complete` line as
  before. (Profiling on a 330-option/33-command benchmark app after fixing
  the bash and zsh renderers, above, found fish was the next-most-expensive
  renderer, dominated almost entirely by this redundant re-quoting rather
  than the tree-copy pattern those two had; nushell and elvish were also
  profiled and are already fast enough -- tens of microseconds per call --
  that optimizing them further would be immeasurable.) Measured: fish
  rendering on the same benchmark app is roughly 1.5x faster. No public API
  or observable script output changed; see
  `tests/cases-parser-benchmark.lisp`.
- The bash and zsh completion renderers (`RENDER-BASH-COMPLETION`,
  `RENDER-ZSH-COMPLETION`) write directly into one shared output stream
  instead of building a separate string per recursive subcommand node (each
  of which a parent then copied again via `WRITE-STRING`) and per
  shell-quoted or array/case-label value (each of which was quoted into its
  own string, joined into a second string, then copied a third time into a
  parent's buffer). Profiling a 330-option/33-command benchmark app showed
  this quote-then-join-then-copy pattern accounting for the large majority
  of sampled render time in both renderers, dominated by repeated
  `WITH-OUTPUT-TO-STRING` setup/copy overhead rather than the actual
  shell-quoting logic. `%COMPLETION-SHELL-QUOTE`'s core loop is now also
  exposed as `%COMPLETION-WRITE-SHELL-QUOTED`, which writes straight to a
  caller-supplied stream, with shared `%COMPLETION-WRITE-CASE-LABELS` /
  `%COMPLETION-WRITE-SPACE-JOINED-QUOTED` writers built on top of it used by
  both renderers (`%COMPLETION-BASH-ARRAY-LITERAL` and
  `%COMPLETION-CASE-LABELS`, now dead, were removed). Zsh's
  `%COMPLETION-ZSH-ARGUMENTS-FIELD` (used to build every `_arguments`
  bracket/placeholder field) also folded its control-character-stripping and
  bracket-blanking into one pass instead of two nested
  `WITH-OUTPUT-TO-STRING` calls, the same fix already applied to
  `%COMPLETION-SHELL-QUOTE`. Measured on the 330-option benchmark app: bash
  rendering is roughly 1.5x faster and zsh rendering roughly 1.5x faster
  than before this round of changes. No public API or observable script
  output changed; see `tests/cases-parser-benchmark.lisp`.
- `PARSE-ARGV` is dramatically faster, especially across repeated calls
  against the same `APP` (a REPL, a long-running server, or simply a hot
  loop). `MAKE-APP` now precomputes and caches, once per app/command scope,
  the built-in-augmented option list, its name/alias lookup table, and the
  command-name/alias lookup table -- previously all three were rebuilt from
  scratch (including re-running `MAKE-OPTION` for the built-in `--help`/
  `--version` specs) on every single `PARSE-ARGV` call. Three option-
  relationship validators (`VALIDATE-CONDITIONAL-REQUIREMENTS`,
  `VALIDATE-REQUIRED-OPTION-GROUPS`, `VALIDATE-INCLUSIVE-GROUPS`) now skip
  building their lookup tables entirely when the app declares none of the
  corresponding feature (conditional requirements / option groups), mirroring
  `VALIDATE-OPTION-RELATIONSHIPS`' existing early exit. The per-parse
  accumulating-option-value hash table is now allocated lazily, on the first
  value that actually needs it, instead of unconditionally on every call.
  Measured on a representative subcommand-dispatch benchmark: ~4.5x faster
  for repeated parses against one app, up to ~15x for a flag-only app with
  no subcommands. `BUILT-IN-OPTION-SPECS` -- also called directly by every
  help and completion renderer, not just the parser -- is cached the same
  way, so generating help text or a shell-completion script no longer
  reruns `MAKE-OPTION` for the built-ins either. No public API or
  observable behavior changed; see `tests/cases-parser-benchmark.lisp`.
- `CANONICAL-OPTION-NAME` (the hot path for every long-option token during
  parsing) now strips a leading `-`/`--` and downcases the remainder in one
  pass instead of two separate allocations (`SUBSEQ` then
  `STRING-DOWNCASE`). Shell-completion rendering is also faster on apps
  with many options: `%COMPLETION-SHELL-QUOTE` (used by the bash/zsh/fish
  renderers) now strips control characters and quote-escapes in a single
  pass rather than two nested string streams, and three
  `REMOVE-DUPLICATES` call sites switched from `:TEST #'STRING=` to
  `:TEST #'EQUAL` -- semantically identical for strings, but lets SBCL use
  its hash-table-based dedup instead of an O(n^2) pairwise scan. Measured
  on a 330-option benchmark app: shell-completion rendering is noticeably
  faster; no observable behavior changed.
- `cl-cli` no longer depends on `cl-prolog` at runtime. Option-relation
  validation (`:requires`, `:requires-any-of`, `:conflicts-with`) is now a
  plain in-memory adjacency graph (`src/option-relations.lisp`) with the same
  public behavior and error messages. `cl-cli`'s only dependency is now
  `uiop`; `cl-prolog` remains a test-only dependency (used as an independent
  validation oracle in the test suite).
- The test suite's real-shell verification (`tests/cases-shell-verification.lisp`)
  now launches every subprocess (`bash -n`, `zsh -n`, `fish --no-execute`,
  `mandoc -T lint`, ...) through `cl-process-kit` with an explicit timeout
  instead of an unbounded `uiop:run-program` call. A hung or misbehaving
  tool is now terminated (SIGTERM escalating to SIGKILL, in its own process
  group) rather than blocking the test run indefinitely; a regression test
  proves the timeout actually fires. Test-only; does not affect `cl-cli`
  itself, which never spawns subprocesses.
- The man page and Markdown doc renderers (`%MANPAGE-OPTION-ENTRY`,
  `%MD-OPTION-TABLE`) no longer rebuild a full `%OPTION-TARGET-TABLE` from
  scratch for every single option in their loop -- an O(n^2) hash-table-
  construction cost that dominated both renderers' profiles on a large app.
  Each loop now hoists one table build to the top and threads it through
  explicitly, mirroring the plain-text help renderer's existing pattern.
  Measured on a 330-option/33-command benchmark app: `render-manpage` ~40%
  faster (682us -> 406us), `render-markdown` ~50% faster (1073us -> 534us).
  No public API or observable output changed; see
  `tests/cases-parser-benchmark.lisp`.
- `render-json` writes directly into a shared stream instead of each layer
  (`%option->json`, `%command->json`, `%app->json`, ...) building and
  returning its own string for its caller to copy again one level up --
  the same allocation-cascade bug already fixed in the bash/zsh/PowerShell
  completion renderers, one level removed. `render-json`'s public contract
  (a string when called without a stream, no return value when passed one)
  is unchanged. Measured on a 330-option/33-command benchmark app: ~3.7x
  faster (963us -> 263us per call), verified against `cl-json-kit`'s
  independent reader to confirm the output is still valid and semantically
  identical, not just byte-similar. See `tests/cases-parser-benchmark.lisp`.
- `MAKE-APP`-time option-relation validation (`:requires`,
  `:requires-any-of`, `:required-if`, `:required-unless`, `:conflicts-with`)
  no longer rebuilds a full option target-table from scratch once per
  declared relation target, plus again independently in cycle detection and
  relation-graph construction -- the table is now built once per `MAKE-APP`
  call and threaded through. Measured on a relation-heavy 100-option
  benchmark app: `MAKE-APP` ~36% faster (4.822ms -> 3.109ms). Apps declaring
  no option relations at all also skip relation-graph construction entirely
  now, rather than building an empty one: ~27% faster `MAKE-APP` on a
  330-option/33-command app with no relations declared (1.755ms -> 1.288ms).
  No public API or observable behavior changed; see
  `tests/cases-parser-benchmark.lisp`.
- `PARSE-ARGV`'s four option-relation validators (`VALIDATE-OPTION-
  RELATIONSHIPS`, `VALIDATE-REQUIRED-OPTION-GROUPS`, `VALIDATE-INCLUSIVE-
  GROUPS`, `VALIDATE-CONDITIONAL-REQUIREMENTS`) no longer each independently
  rebuild their own key/target lookup tables from the validated-specs list
  on every parse; the tables are now cached once per app/command scope
  (alongside the existing relation-graph cache) and threaded through.
  Measured on an app combining multiple relation kinds on overlapping
  options: `PARSE-ARGV` ~37% faster (2.862us -> 1.801us per call). No public
  API or observable behavior changed; see `tests/cases-parser-benchmark.lisp`.

## [0.2.0] - 2026-07-20

### Added

- Dynamic (runtime) completion now works in all six generated shells. Previously
  only bash, zsh, and fish shelled out to the `__complete` callback for a
  `:complete` option; PowerShell, nushell, and elvish offered only a static
  candidate pool. PowerShell now inspects the token before the cursor, elvish
  branches on the previous word, and nushell attaches a per-flag custom
  completer — each invoking `app __complete KEY <partial>`. The generated
  scripts were verified against real `pwsh`, `nu`, and `elvish`.
- Terminal-aware help: `print-app-help`, `print-command-help`, and `run-app`
  now accept `:color :auto` and `:width :auto`. `:color :auto` honors `NO_COLOR`
  and `CLICOLOR_FORCE` and otherwise enables ANSI styling only when the target
  stream is a terminal (isatty on SBCL; environment-only elsewhere); `:width
  :auto` reads `$COLUMNS`. Explicit `t` / `nil` / integer values still force the
  decision, and the defaults remain `nil` so existing behavior is unchanged.
- `option-value-source` reports the provenance of an option value —
  `:command-line`, `:env`, `:config`, or `:default` (or `nil` when unset) — the
  analogue of clap's `ArgMatches::value_source`, so a handler can tell an
  explicit choice apart from a fallback. `invocation-option-sources` exposes the
  raw map.
- Required options are now spelled out in the one-line usage synopsis (for
  example `Usage: demo run [options] --config <FILE>`) instead of being hidden
  inside the `[options]` catch-all; non-required and hidden options stay in the
  catch-all.
- `run-app` accepts `:usage-exit-code` and `:error-exit-code` to override the
  exit codes returned for usage errors (default `64`, `EX_USAGE`) and other
  unhandled errors (default `70`, `EX_SOFTWARE`).
- Dynamic (runtime) completion: an option or positional may carry a `:complete`
  function `(lambda (partial) => candidates)`. Add `make-complete-command` (or
  `make-standard-commands :include-dynamic-p t`) and the generated bash, zsh, and
  fish completions call back into the program (`app __complete KEY PARTIAL`) at
  completion time to offer runtime candidates — no re-parsing of the command
  line. A candidate may be a plain value or a `(value . description)` cons
  (emitted tab-separated; fish shows the description). `render-complete-reply`
  exposes the same lookup directly, and `option-complete` reads the function.
- Bash, zsh, and fish completion now complete nested subcommands at every level
  of a command tree (`app remote <TAB>` offers `add` / `remove`), with each
  command's options — and its ancestors' — completing once that command is on
  the line. All three were verified by exercising the generated scripts under the
  real shells, not just syntax-checking them.
- The built-in `completion` and `docs` commands now carry
  `:completion-candidates`, so generated shell completion suggests the shell
  names (`demo completion <TAB>`) and documentation formats
  (`demo docs <TAB>`) while the parsers still accept aliases (`pwsh`, `nu`,
  `md`, `roff`).
- `:value-hint` (`:file` / `:dir`) on `make-option` (value-bearing) and
  `make-positional`: the generated bash, zsh, and fish completions offer file or
  directory path completion at the hinted slot (`compgen -f/-d`, `_files`/`_files -/`,
  the fish directory completer). Surfaced in help ("expects a file/directory")
  and JSON. Reader `option-value-hint`.
- Positional value completion: `make-positional` now accepts
  `:completion-candidates` (like options), and all six shell completers
  (bash, zsh, fish, powershell, nushell, elvish) offer a positional's
  `:choices` / `:completion-candidates` values at its argument slot. Positional
  candidates also appear in the JSON schema.
- Opt-in help description word-wrapping: `print-app-help`, `print-command-help`,
  and `run-app` accept `:width N` to word-wrap option/command/positional
  descriptions to column N, with continuation lines aligned under the
  description gutter. No terminal-width detection; off by default.
- `:auto-help` on `make-app` (default `t`): pass `nil` to suppress the built-in
  `-h` / `--help` flag for a CLI that manages its own help or forwards `--help`
  to a wrapped tool. A `help` command added via `make-standard-commands` is
  unaffected. Reader `app-auto-help`.
- Greedy variadic `:value-count` on a `:value` option: `:+` (one or more) and
  `:*` (zero or more) consume every following token up to the next option-like
  token (`--files a b c`), storing the list. `:+` requires at least one value.
  Help shows `<NAME>...` and JSON emits `"+"` / `"*"`.
- `:see-also`, `:authors`, and `:manual-date` on `make-app`: rendered as the SEE
  ALSO / AUTHORS sections and the `.TH` date of `render-manpage`, and exposed in
  `render-json` (the first two). `render-manpage` also emits standard EXIT STATUS
  (0 / 64 / 70) and ENVIRONMENT (env-backed options) sections, and the generated
  page passes `mandoc -T lint` cleanly. Readers `app-see-also`, `app-authors`,
  `app-manual-date`.
- `:required-if` / `:required-unless` on `make-option`: conditional
  requirements. `:required-if` makes an option mandatory when any listed option
  is present; `:required-unless` makes it mandatory unless any listed option is
  present. Both signal `cli-missing-option-value`, are hidden-target safe, and
  render in help. Readers `option-required-if`, `option-required-unless`.
- `:require-command` on `make-app`: parsing fails with `cli-unknown-command`
  (listing the available commands) unless a subcommand is dispatched, expressing
  a "subcommand mandatory" contract. Reader `app-require-command`.
- Invalid `:choices` values (for options and positionals) now append a
  nearest-match "Did you mean: ...?" suggestion to the error, reusing the same
  suggestion machinery as unknown options and commands.
- `:value-count N` on a `:value` option: consume exactly N following tokens as a
  parsed list (`--point 1 2` => `(1 2)`); too few remaining tokens signal
  `cli-missing-option-value`, and with `:multiple-p` each occurrence contributes
  its own N-element list. Reader `option-value-count`.
- `:kind :key-value`: each occurrence parses `key=value` (a bare `key` records
  value `t`) and accumulates the pairs into an alist, so `-D a=1 -D b=2` reads as
  `(("a" . "1") ("b" . "2"))` — the compiler-define / docker-env shape.
- `inclusive-group`: an all-or-none option group (if any member is supplied, all
  must be), the complement of `exclusive-group`; rendered as "all or none of" in
  help and signalling `cli-missing-dependent-option` on a partial set.
- `:allow-negative-numbers` on `make-app`: keeps a token that looks like a
  negative number (`-5`, `-1.5`) from being parsed as a short-option cluster, so
  it can serve as a positional or option value. Reader
  `app-allow-negative-numbers`.
- `:group` on `make-option`: a help-section label that groups related options
  under their own heading in help output (mirroring a command's `:group`) and is
  exposed in JSON. Reader `option-help-group`.
- Response-file expansion: `make-app :expand-response-files t` expands a `@path`
  argument into the whitespace-separated arguments read from that file before
  parsing (recursively; `@@` escapes a literal leading `@`; a missing file is a
  usage error), mirroring the gcc/clap convention. Reader
  `app-expand-response-files`.
- `:min-count` / `:max-count` on a rest `make-positional`: constrain how many
  values it collects (too few signals `cli-missing-positional`, too many
  `cli-unexpected-argument`); shown in help and JSON.
- `:default-command` on `make-command`: a command with `:subcommands` can name a
  default subcommand dispatched when no subcommand token is present, mirroring
  the app-level `:default-command`.
- Opt-in colored help: `print-app-help`, `print-command-help`, and `run-app`
  accept `:color t` to wrap headings and names in ANSI styling. There is no
  automatic terminal detection, so callers stay in control; off by default.
- Nested subcommands: `make-command` accepts `:subcommands` (a list of command
  specs), so a command dispatches like a mini-app (`git remote add`). The next
  non-option token selects a subcommand; the parent command's options stay
  available to the whole subtree and global counters accumulate across the path.
  Parsing, help (path-qualified usage plus a subcommand list), the man/Markdown/
  JSON renderers, and `run-app` dispatch all recurse to arbitrary depth. The new
  `invocation-command-path` accessor returns the full root-to-leaf chain.
- `:choices` on `make-positional`: restricts a positional to a closed set,
  validated before the parser runs (`cli-invalid-positional-value` on mismatch)
  and shown in help and JSON output, matching option `:choices`.
- `:help-footer` on `make-command`: trailing help/epilog prose for a command,
  mirroring the app-level `:help-footer` and falling back to it; reflected in the
  man/Markdown/JSON renderers. Reader `command-help-footer`.
- `:allow-abbreviated-options` on `make-app`: opt-in GNU-style unambiguous
  long-option prefix matching (`--verb` for `--verbose`); an ambiguous prefix
  signals `cli-unknown-option` listing the matches. Off by default to preserve
  strict exact-match parsing. Reader `app-allow-abbreviated-options`.
- `render-elvish-completion` and `elvish` support in `render-completion` and the
  `completion` command, bringing built-in completion coverage to six shells
  (bash, zsh, fish, powershell, nushell, elvish).
- `:config` on `parse-argv` and `run-app`: an optional plist of
  `option-key -> value` that supplies option defaults, slotting into the
  precedence chain below CLI arguments and environment variables but above a
  literal `:default`. Values are coerced like defaults (a string runs through
  the option parser, a list is spread, a delimited option splits a string), so a
  caller can layer in configuration loaded from a file without forking the
  parser.
- `:deprecated` on `make-option` and `make-command` (`t` or a reason string):
  the entity stays visible in help and completion but is annotated as deprecated
  in help, man, Markdown, and JSON output; dispatching a deprecated command
  makes `run-app` print a warning to stderr. Readers `option-deprecated` and
  `command-deprecated`.
- `:value-delimiter` on `make-option`: a single-character delimiter that makes a
  `:value` option split one occurrence into a list (`--tags a,b,c` =>
  `("a" "b" "c")`), parsing each piece (honoring `:type`) and accumulating across
  occurrences. Empty pieces are dropped, and string/list `:default`s and
  environment values are split the same way.
- `render-nushell-completion` and `nushell`/`nu` support in `render-completion`
  and the `completion` command: a Nushell module with an `export extern`
  covering subcommands and global option flags.
- `render-json`: emits the app's declared spec (options, positionals, commands,
  types, ranges, delimiters, defaults) as a machine-readable JSON object for
  external tooling. Also available as the `json` format of the `docs` command.
- Typed values on `make-option` and `make-positional`: `:type` selects a
  built-in value parser (`:integer`, `:number`, `:float`, `:boolean`, or the
  default `:string`), and `:min`/`:max` add inclusive bounds for numeric types.
  This replaces most hand-written `:parser` lambdas for common domain
  validation. The chosen type and range appear in help metadata, and both
  are validated at `make-*` time (`:type` and `:parser` are mutually exclusive,
  bounds require a numeric type, and `:min` must not exceed `:max`). Numeric
  parsing binds `*read-eval*` off so a value can never execute reader code.
- `:kind :count` on `make-option`: a repeatable counter option where each
  occurrence increments an integer (`-vvv` => 3, or a repeated `--verbose`),
  defaulting to 0. Ideal for verbosity flags.
- `render-manpage`: generates a section-1 man page (roff) from an app spec,
  covering NAME, SYNOPSIS, DESCRIPTION, OPTIONS, ARGUMENTS, COMMANDS, and
  EXAMPLES, and honoring hidden options/commands.
- `render-markdown`: generates GitHub-flavored Markdown reference documentation
  (title, usage block, option/argument tables, per-command sections, examples).
- `make-docs-command` and `render-docs`: a built-in `docs [FORMAT]` command
  (parallel to `completion [SHELL]`) that prints the generated man page or
  Markdown to stdout; `make-standard-commands` gains `:include-docs-p`.
- `render-powershell-completion` and `powershell`/`pwsh` support in
  `render-completion` and the `completion` command: a
  `Register-ArgumentCompleter -Native` script that offers subcommands and
  option tokens, narrowing to a subcommand's own options once it appears.
- Option readers `option-value-type`, `option-value-min`, and `option-value-max`
  for the new typed-value metadata.
- `:requires-any-of` on `make-option`: declares that at least one of a set of
  alternative options must also be supplied (unlike `:requires`, which demands
  all of them). Signals the new `cli-missing-any-of-options` condition and
  renders as `requires one of: ...` in help. `make-app` rejects a
  `:requires-any-of` whose every alternative conflicts with the option itself,
  since such an option could never be validly supplied.
- Contributor, support, and release-process documentation.

### Changed

- Completion renderers (`render-completion`, `render-bash-completion`,
  `render-zsh-completion`, `render-fish-completion`) now return the generated
  script as a string when called without a stream, mirroring the `format`
  destination contract; passing a stream still writes to it and returns no
  values. Previously the no-stream form wrote to `*standard-output*` and
  returned no values, so there was no way to obtain the script as a string
  through the public API.
- Expanded package metadata for ASDF consumers and package indexes.
- Documented the `cl-prolog` git-dependency install path, since `cl-cli` is not
  yet resolvable through a bare Quicklisp `quickload`.
- Option `:requires`/`:conflicts-with` validation now reuses the Prolog
  rulebase built once at `make-app` time instead of rebuilding and re-querying
  it on every `parse-argv` call.
- Option resolution, relation validation, and completion metadata now build the
  option and target lookup once as a hash table instead of scanning the option
  list linearly on every access; the dynamic-completion index and subcommand
  lookup are likewise cached per app, and repeated-option value accumulation is
  now O(1) per token rather than O(n²).

### Fixed

- Fish completion never offered top-level command names: they were emitted with
  a `__fish_seen_subcommand_from <command>` guard (true only *after* the command
  was typed) instead of `__fish_use_subcommand`, so `app <TAB>` completed
  nothing. Confirmed and fixed via behavioral `fish -c 'complete -C ...'` testing
  (syntax-only checks could not catch it).
- Generated bash completion never completed a separated option value
  (`--mode <TAB>`): the `case "$prev"` scan set `expect_value` / `value_source`
  but nothing turned them into `COMPREPLY`. The completer now consumes them and
  uses `_init_completion -s` so an attached value (`--mode=<TAB>`) completes
  through the same path. Verified against the real `bash-completion` library.
- Fish completion offered file paths alongside an option's closed `:choices`
  value set; choice/candidate value options are now `-f` (exclusive) so only the
  declared values are suggested.
- An option's `:value-hint` never drove shell completion (only positionals did):
  bash now completes files for a plain / `:file`-hint value option (via
  `complete -o default`) and directories for a `:dir` hint (`compgen -d`), fish
  completes directories for a `:dir`-hint option, and zsh completes files/dirs
  for a `:file` / `:dir`-hint option (`_files` / `_files -/`).
- Generated bash completion never completed a subcommand's options: the root
  `-*` fallback returned the global options and stopped before any command case
  ran, and the first-word command completion pre-empted `app -<TAB>`. Both are
  now guarded, so subcommand (and nested-subcommand) option completion works.
  Found via behavioral testing (sourcing the script and inspecting `COMPREPLY`).
- Generated bash completion emitted an empty `case` label (a bash syntax error)
  for a `:value` option that had no `:choices` / `:completion-candidates`; such
  an option now falls through to the shell's default file completion. The bash,
  zsh, and fish generators are now checked with real `bash -n` / `zsh -n` /
  `fish --no-execute` in the test suite's manual verification.
- Bash completion never offered attached-value candidates (`--option=value`)
  for command-scoped options.
- A short-option cluster silently dropped characters that followed a
  mid-cluster `:stop-parsing-p` flag or boolean instead of surfacing them as
  positional input.
- An `:optional-value` option configured with `:consume-optional-value-p t`
  could not accept a separated bare `-` (the stdin/stdout idiom) as its value.
- `make-app` no longer accepts a positional sequence with a required positional
  after an optional one, since such a spec could never assign the later
  positional correctly.
- `make-app` now rejects two options whose keys collide (e.g. case-differing
  single-character names like `-a`/`-A`) instead of letting them silently share
  one storage slot.
- `make-app` now rejects a user-declared option that reuses the reserved
  `:help`/`:version` key, which previously could hijack CLI dispatch into the
  help/version action.
- `extract-application-argv`/`application-argv` no longer strip a literal
  application argument that happens to match a runtime marker when it appears
  after the `--` separator.
- `make-option`/`make-positional` now validate identifier safety before
  interning the option/positional key, instead of after.
- A relation rulebase cached on a shared, reused `command-spec` (per the
  library's own "reusable command spec" pattern) could be silently overwritten
  by a second, unrelated `make-app` call that spliced in the same command
  object, corrupting validation for the first app. The cache now lives per-app,
  keyed by command object, instead of being stored on the shared command
  struct.
- Corrected broken absolute-path documentation links and gave `SECURITY.md` a
  concrete private vulnerability-reporting path.
- Generated shell completion now emits candidates through a more robust
  protocol: bash builds `COMPREPLY` as an array with prefix filtering, dynamic
  completion reads tab-delimited `value<TAB>description` records with
  `while read` (instead of `cut -f1`, which mangled values containing tabs),
  and PowerShell matches the current word with an ordinal `StartsWith`.

### Security

- Rendered output no longer trusts declared spec metadata verbatim: help,
  usage, version, and deprecation text, generated shell completions, and
  generated man-page / Markdown documentation now strip terminal control
  characters (and, for Markdown, escape markup) from option names,
  descriptions, and values, so hostile metadata can no longer inject ANSI
  escape or other terminal control sequences into a user's terminal. Spec
  construction additionally rejects control characters in option value names.

[Unreleased]: https://github.com/nerima-lisp/cl-cli/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/nerima-lisp/cl-cli/releases/tag/v1.0.1
[1.0.0]: https://github.com/nerima-lisp/cl-cli/releases/tag/v1.0.0
[0.3.0]: https://github.com/nerima-lisp/cl-cli/releases/tag/v0.3.0
[0.2.0]: https://github.com/nerima-lisp/cl-cli/releases/tag/v0.2.0
