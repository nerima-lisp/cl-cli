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
            (:conc-name "POSITIONAL-SPEC-"))
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
  (command-relation-graphs (make-hash-table :test 'eq)))

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
