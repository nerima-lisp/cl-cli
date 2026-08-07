(in-package :cl-cli)

(defun %scan-options-prefix (validated-specs table tokens values action
                              literal-separator-seen-p on-done)
  "Scan TOKENS for a flat (non-subcommand) option prefix, calling ON-DONE with
the final (values action literal-separator-seen-p remaining) once nothing more
can be consumed.

Genuine continuation-passing style: every terminal case calls ON-DONE instead
of returning through a chain of direct-style call frames. The recursive case is
in tail position, so implementations that optimize tail calls can process long
token streams without additional dynamic stack frames."
  (cond
    ((null tokens)
     (funcall on-done values tokens action literal-separator-seen-p))
    ((string= (first tokens) "--")
     (funcall on-done values (rest tokens) action t))
    (t
     (multiple-value-bind (status new-values new-remaining new-action)
         (%consume-option-token-step (first tokens) validated-specs table
                                     values action tokens)
       (case status
         (:unconsumed
          (funcall on-done values tokens action literal-separator-seen-p))
         (:done
          (funcall on-done new-values new-remaining new-action
                   literal-separator-seen-p))
         (t
          (%scan-options-prefix validated-specs table new-remaining new-values
                                new-action literal-separator-seen-p on-done)))))))

(defun parse-options-prefix (app tokens option-specs &optional initial-values cache)
  (let ((*abbreviated-option-entry-cache*
          (or *abbreviated-option-entry-cache*
              (and *allow-abbreviated-options*
                   (make-hash-table :test #'eq)))))
    (multiple-value-bind (validated-specs table)
        (prepare-option-parser-state app option-specs cache)
      (%scan-options-prefix validated-specs table tokens initial-values
                            :dispatch nil #'values))))

(defun %scan-mixed-arguments-consume-positional (pending positional-values remaining)
  "Consume one positional token, or signal CLI-USAGE-ERROR when none is pending.

Returns (values new-pending new-positional-values new-remaining)."
  (when (null pending)
    (signal-unexpected-positionals remaining))
  (let ((spec (first pending)))
    (multiple-value-bind (new-positional-values new-remaining)
        (apply-positional-spec spec positional-values remaining)
      (values (if (positional-rest-p spec) nil (rest pending))
              new-positional-values
              new-remaining))))

(defun %scan-mixed-arguments (validated-specs table remaining pending option-values
                              positional-values action literal-mode-p on-done)
  "Scan REMAINING as an interleaved option/positional stream, calling ON-DONE
with the final (pending option-values positional-values action) once every
token is consumed.

Genuine continuation-passing style, mirroring %SCAN-OPTIONS-PREFIX: every
terminal case calls ON-DONE, and every other case is a tail call threading the
full scan state through explicit arguments. Implementations that optimize tail
calls can process long token streams without additional dynamic stack frames."
  (cond
    ((null remaining)
     (funcall on-done pending option-values positional-values action))
    ((and (not literal-mode-p) (string= (first remaining) "--"))
     (%scan-mixed-arguments validated-specs table (rest remaining) pending
                            option-values positional-values action t on-done))
    (literal-mode-p
     (multiple-value-bind (new-pending new-positional-values new-remaining)
         (%scan-mixed-arguments-consume-positional pending positional-values
                                                    remaining)
       (%scan-mixed-arguments validated-specs table new-remaining new-pending
                              option-values new-positional-values action t
                              on-done)))
    (t
     (multiple-value-bind (status new-values new-remaining new-action)
         (%consume-option-token-step (first remaining) validated-specs table
                                     option-values action remaining)
       (case status
         ((:done :continue)
          (%scan-mixed-arguments validated-specs table new-remaining pending
                                 new-values positional-values new-action
                                 (eq status :done) on-done))
         (t
          (multiple-value-bind (new-pending new-positional-values new-remaining)
              (%scan-mixed-arguments-consume-positional pending positional-values
                                                         remaining)
            (%scan-mixed-arguments validated-specs table new-remaining
                                   new-pending option-values new-positional-values
                                   action literal-mode-p on-done))))))))

(defun %validate-mixed-option-relationships
    (app command option-values validated-specs)
  "Validate option relationship constraints for APP and optional COMMAND."
  (let ((key-table (if command
                       (gethash command (app-command-relation-key-tables app))
                       (app-global-relation-key-table app)))
        (target-table (if command
                          (gethash command (app-command-relation-target-tables app))
                          (app-global-relation-target-table app))))
    (validate-option-relationships
     option-values validated-specs
     (if command
         (gethash command (app-command-relation-graphs app))
         (app-global-relation-graph app))
     key-table target-table)
    (validate-required-option-groups option-values validated-specs key-table)
    (validate-inclusive-groups option-values validated-specs key-table)
    (validate-conditional-requirements option-values validated-specs target-table)))

(defun %finalize-mixed-parse
    (app command validated-specs pending option-values positional-values action)
  "Normalize a completed mixed parse and validate its option constraints."
  (unless (member action '(:help :version))
    (setf positional-values
          (finalize-pending-positionals pending positional-values)))
  (setf option-values (apply-option-defaults option-values validated-specs))
  (unless (member action '(:help :version))
    (validate-required-options option-values validated-specs)
    (%validate-mixed-option-relationships app command option-values
                                          validated-specs))
  (values option-values positional-values action))

(defun parse-mixed-arguments (app tokens option-specs positional-specs
                               &key initial-option-values command cache)
  (let ((*abbreviated-option-entry-cache*
          (or *abbreviated-option-entry-cache*
              (and *allow-abbreviated-options*
                   (make-hash-table :test #'eq)))))
    (multiple-value-bind (validated-specs table)
        (prepare-option-parser-state app option-specs cache)
      (%scan-mixed-arguments
       validated-specs table tokens positional-specs initial-option-values nil
       :dispatch nil
       (lambda (pending option-values positional-values action)
         (%finalize-mixed-parse app command validated-specs pending
                                option-values positional-values action))))))
