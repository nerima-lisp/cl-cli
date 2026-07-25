(in-package :cl-cli)

(defun validate-option-relationships (values specs &optional graph key-table target-table)
  ;; Most CLIs declare no requires/conflicts at all. Skip building a relation
  ;; graph when there is nothing to validate -- otherwise every parse pays for
  ;; a graph build plus O(present log present) empty closure lookups that can
  ;; only ever succeed vacuously.
  (unless (some (lambda (spec)
                  (or (option-requires spec)
                      (option-requires-any-of spec)
                      (option-conflicts-with spec)))
                specs)
    (return-from validate-option-relationships values))
  ;; SPECS' :requires/:conflicts graph, key-table, and target-table are all
  ;; fixed at spec-construction time, so %VALIDATE-APP-SPEC already built and
  ;; cached all three on the app/command spec. Callers pass them in via GRAPH/
  ;; KEY-TABLE/TARGET-TABLE; only rebuild here as a fallback for callers
  ;; validating an ad hoc SPECS list that was never run through MAKE-APP.
  ;; Every transitive closure is already precomputed on GRAPH (see
  ;; OPTION-RELATION-GRAPH), so looking one up below is a plain O(1) hash
  ;; read -- no memoization layer needed here.
  (let* ((graph (or graph (make-option-relation-graph specs)))
         (present-specs
           (remove-if-not (lambda (spec)
                            (plist-has-key-p values (option-key spec)))
                          specs))
         (spec-by-key (or key-table (%option-key-table specs)))
         (spec-by-target (or target-table (%option-target-table specs))))
    (flet ((validate-requires (spec)
             (dolist (dependency-key (transitive-required-option-keys graph (option-key spec)))
               (let ((dependency (gethash dependency-key spec-by-key)))
                 (unless (plist-has-key-p values (option-key dependency))
                   (signal-cli-error 'cli-missing-dependent-option
                                     (if (option-hidden-p spec)
                                         (format nil "A hidden option requires ~A."
                                                 (public-option-display-name dependency))
                                         (format nil "Option ~A requires ~A."
                                                 (public-option-display-name spec)
                                                 (public-option-display-name dependency)))
                                     :option (option-key spec)
                                     :dependency (option-key dependency))))))
           (validate-requires-any-of (spec)
             (when (option-requires-any-of spec)
               (let* ((alternative-keys (any-of-required-option-keys graph (option-key spec)))
                      (alternatives (mapcar (lambda (key) (gethash key spec-by-key))
                                            alternative-keys)))
                 (unless (some (lambda (alternative)
                                 (plist-has-key-p values (option-key alternative)))
                               alternatives)
                   (signal-cli-error 'cli-missing-any-of-options
                                     (if (option-hidden-p spec)
                                         (format nil "A hidden option requires one of: ~{~A~^, ~}."
                                                 (mapcar #'public-option-display-name alternatives))
                                         (format nil "Option ~A requires one of: ~{~A~^, ~}."
                                                 (public-option-display-name spec)
                                                 (mapcar #'public-option-display-name alternatives)))
                                     :option (option-key spec)
                                     :alternatives (mapcar #'option-key alternatives))))))
           (validate-conflicts (spec)
             (dolist (target (option-conflicts-with spec))
               (let ((other (%lookup-option-target spec-by-target target)))
                 (when (plist-has-key-p values (option-key other))
                   (signal-cli-error 'cli-conflicting-options
                                     (if (option-hidden-p spec)
                                         (format nil "A hidden option conflicts with ~A."
                                                 (public-option-display-name other))
                                         (format nil "Option ~A conflicts with ~A."
                                                 (public-option-display-name spec)
                                                 (public-option-display-name other)))
                                     :left-option (option-key spec)
                                     :right-option (option-key other)))))))
      (let ((roots
              ;; Report the most upstream failure first: an option that (directly
              ;; or transitively) requires others is validated before them. A
              ;; requiring option always has a strictly larger required-closure
              ;; than anything it depends on, so ordering by closure size (with a
              ;; key-name tiebreaker) is a valid strict weak ordering -- unlike the
              ;; previous reachability comparator, which was non-transitive and so
              ;; gave SORT undefined behaviour (notably across implementations).
              (stable-sort-copy
               present-specs
               (lambda (left right)
                 (let ((left-size (length (transitive-required-option-keys
                                            graph (option-key left))))
                       (right-size (length (transitive-required-option-keys
                                             graph (option-key right)))))
                   (if (= left-size right-size)
                       (string< (string (option-key left))
                                (string (option-key right)))
                       (> left-size right-size)))))))
        (dolist (spec roots values)
          (validate-requires spec)
          (validate-requires-any-of spec)
          (validate-conflicts spec))))))

(defun validate-required-option-groups (values specs &optional key-table)
  "Signal CLI-MISSING-OPTION-VALUE when a required option group has no member set.

Exclusivity within a group is already enforced through :conflicts-with, so this
only checks the at-least-one obligation that REQUIRED-EXCLUSIVE-GROUP adds. Each
distinct group is checked once."
  ;; Most CLIs declare no required option groups at all -- skip building the
  ;; lookup tables when there is nothing to check.
  (unless (some (lambda (spec)
                  (let ((group (option-group spec)))
                    (and group (option-group-required-p group))))
                specs)
    (return-from validate-required-option-groups values))
  (let ((seen (make-hash-table :test #'eq))
        (spec-by-key (or key-table (%option-key-table specs))))
    (dolist (spec specs values)
      (let ((group (option-group spec)))
        (when (and group
                   (option-group-required-p group)
                   (not (gethash group seen)))
          (setf (gethash group seen) t)
          (unless (some (lambda (key) (plist-has-key-p values key))
                        (option-group-members group))
            (let ((member-specs
                    (remove nil
                            (mapcar (lambda (key)
                                      (gethash key spec-by-key))
                                    (option-group-members group)))))
              (signal-cli-error 'cli-missing-option-value
                                (format nil "Exactly one of ~{~A~^, ~} is required."
                                        (mapcar #'public-option-display-name
                                                member-specs))
                                :option (option-key (first member-specs))))))))))

(defun validate-inclusive-groups (values specs &optional key-table)
  "Signal when an all-or-none option group has some but not all members set.

Each distinct :INCLUSIVE group is checked once. Hidden members are named
generically in the error, mirroring the other relationship diagnostics."
  ;; Most CLIs declare no inclusive option groups at all -- skip building the
  ;; lookup tables when there is nothing to check.
  (unless (some (lambda (spec)
                  (let ((group (option-group spec)))
                    (and group (eq (option-group-mode group) :inclusive))))
                specs)
    (return-from validate-inclusive-groups values))
  (let ((seen (make-hash-table :test #'eq))
        (spec-by-key (or key-table (%option-key-table specs))))
    (dolist (spec specs values)
      (let ((group (option-group spec)))
        (when (and group
                   (eq (option-group-mode group) :inclusive)
                   (not (gethash group seen)))
          (setf (gethash group seen) t)
          (let* ((members (option-group-members group))
                 (present (remove-if-not (lambda (key) (plist-has-key-p values key)) members))
                 (missing (remove-if (lambda (key) (plist-has-key-p values key)) members)))
            (when (and present missing)
              (flet ((named (key) (gethash key spec-by-key)))
                (signal-cli-error
                 'cli-missing-dependent-option
                 (format nil "Options ~{~A~^, ~} must be used together; missing ~{~A~^, ~}."
                         (mapcar (lambda (key) (public-option-display-name (named key))) members)
                         (mapcar (lambda (key) (public-option-display-name (named key))) missing))
                 :option (option-key (named (first present)))
                 :dependency (first missing))))))))))

(defun %relation-target-present-p (values spec-by-target target)
  (let ((spec (%lookup-option-target spec-by-target target)))
    (and spec (plist-has-key-p values (option-key spec)))))

(defun validate-conditional-requirements (values specs &optional target-table)
  "Enforce :required-if / :required-unless for options absent from VALUES.

:required-if makes an option mandatory when any listed target is present;
:required-unless makes it mandatory unless any listed target is present."
  ;; Most CLIs declare no :required-if/:required-unless at all -- skip
  ;; building the target-lookup table when there is nothing to check,
  ;; mirroring VALIDATE-OPTION-RELATIONSHIPS' early exit.
  (unless (some (lambda (spec)
                  (or (option-required-if spec) (option-required-unless spec)))
                specs)
    (return-from validate-conditional-requirements values))
  (let ((spec-by-target (or target-table (%option-target-table specs))))
    (dolist (spec specs values)
      (unless (plist-has-key-p values (option-key spec))
        (let ((trigger (find-if (lambda (target)
                                  (%relation-target-present-p values spec-by-target target))
                                (option-required-if spec))))
          (when trigger
            (signal-cli-error
             'cli-missing-option-value
             (format nil "Option ~A is required when ~A is supplied."
                     (public-option-display-name spec)
                     (public-option-display-name
                      (%lookup-option-target spec-by-target trigger)))
             :option (option-key spec))))
        (when (and (option-required-unless spec)
                   (notany (lambda (target)
                             (%relation-target-present-p values spec-by-target target))
                           (option-required-unless spec)))
          (signal-cli-error
           'cli-missing-option-value
           (format nil "Option ~A is required unless one of ~{~A~^, ~} is supplied."
                   (public-option-display-name spec)
                   (mapcar (lambda (target)
                             (public-option-display-name
                              (%lookup-option-target spec-by-target target)))
                           (option-required-unless spec)))
           :option (option-key spec)))))))
