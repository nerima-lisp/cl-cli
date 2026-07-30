(in-package :cl-cli)

(defun %option-table-entries (spec)
  (append (loop for name in (option-names spec)
                collect (list name nil))
          (loop for name in (option-negated-names spec)
                collect (list name t))))

(defun %validate-user-option-keys (specs owner-name)
  "Reject a user-declared option whose resolved key is :HELP or :VERSION.

BUILT-IN-OPTION-P and BUILT-IN-OPTION-ACTION (src/model-helpers.lisp,
src/parser-values.lisp) key off OPTION-KEY's value alone, not object identity
with the real built-in spec -- an ordinary option given :KEY :HELP or
:KEY :VERSION would silently force the :HELP/:VERSION dispatch action
whenever it is parsed, regardless of its own :KIND."
  (dolist (spec specs)
    (when (member (option-key spec) '(:help :version))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Option ~A for ~A cannot use the reserved key ~S."
                                (%option-display-name spec)
                                owner-name
                                (option-key spec))))))

(defun %validate-option-key-uniqueness (specs owner-name)
  "Reject two options in SPECS that resolve to the same OPTION-KEY.

Distinct declared names can still collide on key -- OPTION-KEYWORD downcases
its argument, so single-character names \"-a\" and \"-A\" (deliberately
case-sensitive as CLI tokens; see CANONICAL-OPTION-NAME) both resolve to
:A. A key collision means the two specs share one storage slot in the parsed
values plist, silently overwriting each other, and only the last spec with
that key survives :requires/:conflicts-with resolution."
  (let ((table (make-hash-table :test 'eq)))
    (dolist (spec specs)
      (%register-table-entry table
                             (option-key spec)
                             t
                             (format nil "option key for ~A" owner-name)
                             (format nil "~S" (option-key spec))))))

(defun %validate-option-table (specs)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (spec specs specs)
      (dolist (entry (%option-table-entries spec))
        (destructuring-bind (name negated-p) entry
          (declare (ignore negated-p))
          (let ((key (canonical-option-name name)))
            (%register-table-entry table
                                   key
                                   t
                                   "option name"
                                   (option-token-display-name key))))))))

(defun %validate-command-table (commands)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (command commands table)
      (%register-table-entry table
                             (command-name command)
                             t
                             "command name"
                             (command-name command))
      (dolist (alias (command-aliases command))
        (%register-table-entry table
                               alias
                               t
                               "command name"
                               alias)))))

(defun %validate-positional-sequence (positionals owner-name)
  (let ((seen-keys (make-hash-table :test 'eq))
        (rest-seen-p nil)
        (optional-seen-p nil))
    (dolist (spec positionals positionals)
      (let ((key (positional-key spec)))
        (when (gethash key seen-keys)
          (signal-cli-error 'cli-invalid-specification
                            (format nil "Duplicate positional key for ~A: ~A"
                                    owner-name
                                    key)))
        (setf (gethash key seen-keys) t))
      (when rest-seen-p
        (signal-cli-error 'cli-invalid-specification
                          (format nil "Rest positional for ~A must be last."
                                  owner-name)))
      ;; Tokens are assigned to positionals greedily in declared order with no
      ;; backtracking (APPLY-POSITIONAL-SPEC), so a required positional after
      ;; an optional one can never receive a value: the optional one consumes
      ;; it first, then the required one fails as "missing" even though a
      ;; value was supplied.
      (if (positional-required-p spec)
          (when optional-seen-p
            (signal-cli-error 'cli-invalid-specification
                              (format nil "Required positional for ~A must not follow ~
                                           an optional positional."
                                      owner-name)))
          (setf optional-seen-p t))
      (when (positional-rest-p spec)
        (setf rest-seen-p t)))))

(defun %validate-default-command-exists (label default-command table)
  "Signal CLI-INVALID-SPECIFICATION when DEFAULT-COMMAND isn't a key in TABLE.

Shared by %VALIDATE-COMMAND-NODE (a command's own default subcommand) and
%VALIDATE-APP-SPEC (an app's own default command) -- same check, same
message, differing only in which name/default-command/table triple is
being validated."
  (when (and default-command (null (gethash default-command table)))
    (signal-cli-error 'cli-invalid-specification
                      (format nil "Unknown :default-command for ~A: ~A"
                              label
                              default-command))))

(defun %validate-command-node (app command accumulated-specs)
  "Validate COMMAND and, recursively, its subcommands.

ACCUMULATED-SPECS is the option-spec set in scope from the app root down to (but
not including) COMMAND -- built-ins, globals, and every ancestor command's
options. COMMAND's own options extend that scope for both its own validation and
its subcommands', mirroring how a nested command inherits its ancestors'
options at parse time. The per-command relation graph is cached on the app
keyed by the command object."
  (%validate-positional-sequence (command-positionals command)
                                 (command-name command))
  (%validate-user-option-keys (command-options command) (command-name command))
  (let ((command-specs (append accumulated-specs (command-options command))))
    (multiple-value-bind (validated-command-specs command-graph)
        (validate-option-relationships-declared command-specs)
      (declare (ignore validated-command-specs))
      (setf (gethash command (app-command-relation-graphs app))
            command-graph))
    (setf (gethash command (app-command-relation-key-tables app))
          (%option-key-table command-specs))
    (setf (gethash command (app-command-relation-target-tables app))
          (%option-target-table command-specs))
    (setf (gethash command (app-command-option-caches app))
          (cons command-specs (option-table-from-specs command-specs)))
    (%validate-option-table command-specs)
    (%validate-option-key-uniqueness command-specs (command-name command))
    (if (command-subcommands command)
        (let ((subcommand-table (%validate-command-table (command-subcommands command))))
          (setf (gethash command (app-command-subcommand-tables app))
                (command-table-from-specs (command-subcommands command)))
          (%validate-default-command-exists (command-name command)
                                            (command-default-command command)
                                            subcommand-table)
          (dolist (subcommand (command-subcommands command))
            (%validate-command-node app subcommand command-specs)))
        (when (command-default-command command)
          (signal-cli-error 'cli-invalid-specification
                            (format nil "Command ~A declares :default-command but has ~
                                         no :subcommands."
                                    (command-name command)))))))

(defun %validate-app-spec (app)
  (let* ((built-ins (setf (app-cached-built-in-option-specs app)
                          (%compute-built-in-option-specs app)))
         (global-specs (append built-ins (app-global-options app)))
         (command-table (%validate-command-table (app-commands app))))
    (%validate-positional-sequence (app-positionals app)
                                   (app-name app))
    (%validate-user-option-keys (app-global-options app) (app-name app))
    (multiple-value-bind (validated-global-specs global-graph)
        (validate-option-relationships-declared global-specs)
      (declare (ignore validated-global-specs))
      (setf (app-global-relation-graph app) global-graph))
    (setf (app-global-relation-key-table app) (%option-key-table global-specs))
    (setf (app-global-relation-target-table app) (%option-target-table global-specs))
    (setf (app-global-option-cache app)
          (cons global-specs (option-table-from-specs global-specs)))
    (setf (app-root-command-table app) (command-table-from-specs (app-commands app)))
    (%validate-option-table global-specs)
    (%validate-option-key-uniqueness global-specs (app-name app))
    (let ((accumulated-specs (append built-ins (app-global-options app))))
      (dolist (command (app-commands app))
        (%validate-command-node app command accumulated-specs)))
    (%validate-default-command-exists (app-name app)
                                      (app-default-command app)
                                      command-table)
    (when (and (app-require-command app)
               (null (app-commands app)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A declares :require-command but has no :commands."
                                (app-name app)))))
  app)
