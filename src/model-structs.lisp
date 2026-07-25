(in-package :cl-cli)

(defstruct (option-spec
            (:constructor %make-option-spec)
            (:conc-name "OPTION-"))
  key
  names
  negated-names
  kind
  description
  value-name
  value-type
  value-min
  value-max
  value-delimiter
  value-count
  value-hint
  default
  env-vars
  choices
  completion-candidates
  complete
  parser
  required-p
  required-if
  required-unless
  requires
  requires-any-of
  conflicts-with
  multiple-p
  default-present-p
  consume-optional-value-p
  stop-parsing-p
  hidden-p
  deprecated
  help-group
  group)

(defstruct (positional-spec
            (:constructor %make-positional-spec)
            (:conc-name "POSITIONAL-"))
  key
  description
  value-type
  value-min
  value-max
  choices
  completion-candidates
  value-hint
  complete
  parser
  default
  default-present-p
  required-p
  rest-p
  min-count
  max-count)

(defstruct (command-spec
            (:constructor %make-command-spec)
            (:conc-name "COMMAND-"))
  name
  aliases
  group
  description
  examples
  options
  positionals
  subcommands
  default-command
  handler
  hidden-p
  deprecated
  help-footer)

(defstruct (app-spec
            (:constructor %make-app-spec)
            (:conc-name "APP-"))
  name
  version
  summary
  description
  global-options
  positionals
  commands
  default-command
  handler
  examples
  help-footer
  see-also
  authors
  manual-date
  allow-abbreviated-options
  expand-response-files
  allow-negative-numbers
  require-command
  (auto-help t)
  global-relation-graph
  dynamic-completion-index
  ;; A COMMAND-SPEC is an explicitly reusable, composable object (README:
  ;; "reusable app, command, option, and positional specs") -- the same
  ;; instance can be spliced into :COMMANDS for more than one MAKE-APP call.
  ;; Caching a command's relation graph ON the shared command struct would
  ;; let a later MAKE-APP call silently overwrite the graph an earlier,
  ;; already-in-use app depends on. Keyed by command object (EQ) instead, this
  ;; table lives on the APP -- which is never itself shared as another app's
  ;; input -- so each app owns an independent cache even when commands are.
  (command-relation-graphs (make-hash-table :test 'eq))
  ;; VALIDATE-OPTION-RELATIONSHIPS/-REQUIRED-OPTION-GROUPS/-INCLUSIVE-GROUPS/
  ;; -CONDITIONAL-REQUIREMENTS (src/parser-relation-validation.lisp) each ran
  ;; on every single PARSE-ARGV call and each independently rebuilt an
  ;; %OPTION-KEY-TABLE and/or %OPTION-TARGET-TABLE from the same specs list
  ;; the relation graph above was already built from -- for an app using
  ;; :requires-if/option-groups/etc, that's 2-4 redundant hash-table builds
  ;; per parse. Both tables are pure functions of an immutable specs list, so
  ;; cache them here too, keyed by command exactly like COMMAND-RELATION-GRAPHS.
  global-relation-key-table
  global-relation-target-table
  (command-relation-key-tables (make-hash-table :test 'eq))
  (command-relation-target-tables (make-hash-table :test 'eq))
  ;; Option specs are immutable and their built-ins/lookup table are fully
  ;; determined at MAKE-APP time, so both are computed once here (mirroring
  ;; the relation-graph caches above) instead of being rebuilt --
  ;; reconstructing the built-in --help/--version specs via MAKE-OPTION and
  ;; re-populating a hash table -- on every PARSE-ARGV call. Each cache is a
  ;; (SPECS . TABLE) cons; see PREPARE-OPTION-PARSER-STATE.
  global-option-cache
  (command-option-caches (make-hash-table :test 'eq))
  ;; Likewise, the app's root command-name/alias -> command lookup table and
  ;; each command's own subcommand-name/alias table are fully determined at
  ;; MAKE-APP time (commands/subcommands are immutable), so both are cached
  ;; once instead of PARSE-ARGV/dispatch rebuilding a hash table from scratch
  ;; on every call. COMMAND-SUBCOMMAND-TABLES is keyed by command, mirroring
  ;; COMMAND-RELATION-GRAPHS/COMMAND-OPTION-CACHES above.
  root-command-table
  (command-subcommand-tables (make-hash-table :test 'eq))
  ;; BUILT-IN-OPTION-SPECS (src/util.lisp) is called directly by the help and
  ;; completion renderers, not just PREPARE-OPTION-PARSER-STATE above -- cache
  ;; its result too so every one of those call sites shares one list instead
  ;; of each re-running MAKE-OPTION to reconstruct --help/--version.
  cached-built-in-option-specs)

(defstruct (invocation
            (:constructor %make-invocation)
            (:conc-name "INVOCATION-"))
  app
  command
  command-path
  action
  argv0
  raw-argv
  global-options
  command-options
  positionals
  option-sources
  stdout
  stderr)

(defstruct (option-group (:constructor %make-option-group))
  "A set of options that participate together in a group relationship.

MODE is :EXCLUSIVE (at most one member, via pairwise conflicts) or :INCLUSIVE
(all-or-none: if any member is supplied, all must be)."
  members
  required-p
  (mode :exclusive))
