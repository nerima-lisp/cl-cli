(in-package :cl-cli)

(defun make-command (&key name aliases group description examples options positionals
                       subcommands default-command handler hidden-p deprecated help-footer)
  "Create a command specification.

DEPRECATED marks the command as deprecated (T, or a reason string). A deprecated
command stays visible in help and completion, is annotated as deprecated in help
and generated docs, and triggers a stderr warning when RUN-APP dispatches it.
HELP-FOOTER is trailing prose printed after the command's help, mirroring the
app-level :help-footer.

SUBCOMMANDS is a list of nested command specs (built with MAKE-COMMAND); a
command that declares them dispatches like a mini-app (`git remote add`). The
next non-option token selects a subcommand, the command's own options remain
available to the whole subtree, and the command's :handler / :positionals still
run when no subcommand token is supplied.

DEFAULT-COMMAND names one of :subcommands to dispatch when no subcommand token
is present, mirroring the app-level :default-command."
  (let* ((resolved-name (and name (canonical-name name)))
         (resolved-aliases (normalize-command-aliases aliases)))
    (when (or (null resolved-name)
              (zerop (length resolved-name)))
      (signal-cli-error 'cli-invalid-specification
                        "A command needs a non-empty name."))
    (validate-non-empty-strings resolved-aliases "Command aliases")
    (validate-safe-identifier-names (list resolved-name) "Command name")
    (validate-safe-identifier-names resolved-aliases "Command aliases")
    (%make-command-spec :name resolved-name
                        :aliases resolved-aliases
                        :group (normalize-command-group group)
                        :description (normalize-positional-description description)
                        :examples (normalize-example-strings examples)
                        :options options
                        :positionals positionals
                        :subcommands subcommands
                        :default-command (and default-command (canonical-name default-command))
                        :handler handler
                        :hidden-p hidden-p
                        :deprecated (normalize-deprecated deprecated)
                        :help-footer (normalize-positional-description help-footer))))
