(in-package :cl-cli)

(defun %join-help-metadata (parts)
  (if parts
      (format nil " (~{~A~^; ~})" parts)
      ""))

(defun %public-relation-targets
    (option options relation-targets &optional (target-table (%option-target-table options)))
  (collecting
    (dolist (target relation-targets)
      (let ((resolved (%lookup-option-target target-table target)))
        (when (and resolved
                   (not (eq (option-key resolved) (option-key option)))
                   (public-option-candidate-p resolved))
          (collect target))))))

(defun %option-group-member-names
    (option options &optional (target-table (%option-target-table options)))
  "Public display names of the members of OPTION's exclusive group, or NIL."
  (let ((group (option-group option)))
    (when group
      (loop for key in (option-group-members group)
            for spec = (%lookup-option-target target-table key)
            when (and spec (public-option-candidate-p spec))
              collect (option-token-display-name (first (option-names spec)))))))

(defun %option-intra-group-conflict-p
    (option options target &optional (target-table (%option-target-table options)))
  "True when TARGET is another member of OPTION's own exclusive group."
  (let ((group (option-group option)))
    (and group
         (let ((resolved (%lookup-option-target target-table target)))
           (and resolved
                (member (option-key resolved)
                        (option-group-members group)))))))

(defun %deprecation-note (deprecated)
  "A help/doc note for a DEPRECATED designator (T or reason string), or NIL."
  (cond
    ((null deprecated) nil)
    ((stringp deprecated) (format nil "deprecated: ~A" (%terminal-safe-text deprecated)))
    (t "deprecated")))

(defun %value-hint-note (hint)
  "A help-metadata fragment for a :value-hint, or NIL."
  (case hint
    (:file "expects a file")
    (:dir "expects a directory")
    (t nil)))

(defun %numeric-range-metadata (min max)
  "Render inclusive numeric bounds as a help-metadata fragment, or NIL."
  (cond
    ((and min max) (format nil "range: ~A..~A" min max))
    (min (format nil "min: ~A" min))
    (max (format nil "max: ~A" max))
    (t nil)))

(defparameter +option-relation-labels+
  (list (cons #'option-requires "requires")
        (cons #'option-requires-any-of "requires one of")
        (cons #'option-required-if "required if")
        (cons #'option-required-unless "required unless"))
  "Each option relation kind's accessor paired with its help-metadata label.

Shared by %OPTION-METADATA-PARTS' :requires/:requires-any-of/:required-if/
:required-unless lines -- :conflicts-with is deliberately excluded since it
has an extra intra-group-conflict filter the other four don't share.")

(defun %relation-line (option options target-table accessor label)
  (let ((visible-targets (%public-relation-targets option options
                                                    (funcall accessor option)
                                                    target-table)))
    (when visible-targets
      (format nil "~A: ~{~A~^, ~}" label
              (mapcar #'option-relation-target-display-name visible-targets)))))

(defun %option-metadata-parts
    (option options &optional (target-table (%option-target-table options)))
  (collecting
    (let ((deprecation (%deprecation-note (option-deprecated option))))
      (when deprecation
        (collect deprecation)))
    (when (option-multiple-p option)
      (collect "repeatable"))
    (when (eq (option-kind option) :count)
      (collect "count"))
    (when (option-required-p option)
      (collect "required"))
    (when (and (option-value-type option)
               (not (eq (option-value-type option) :string)))
      (collect (format nil "type: ~(~A~)" (option-value-type option))))
    (let ((range (%numeric-range-metadata (option-value-min option)
                                          (option-value-max option))))
      (when range
        (collect range)))
    (when (option-value-delimiter option)
      (collect (format nil "list (delimited by '~A')" (option-value-delimiter option))))
    (let ((hint (%value-hint-note (option-value-hint option))))
      (when hint (collect hint)))
    ;; A :count option's implicit 0 default is conventional noise, so suppress
    ;; it; a caller-chosen non-zero starting count is still worth surfacing.
    (when (and (option-default-present-p option)
               (not (and (eq (option-kind option) :count)
                         (eql (option-default option) 0))))
      (collect (format nil "default: ~A" (option-default option))))
    (when (option-env-vars option)
      (collect (format nil "env: ~{~A~^, ~}" (option-env-vars option))))
    (when (option-choices option)
      (collect (format nil "choices: ~{~A~^ | ~}" (option-choices option))))
    (let ((group-members (%option-group-member-names option options target-table)))
      (when group-members
        (collect (if (eq (option-group-mode (option-group option)) :inclusive)
                     (format nil "all or none of: ~{~A~^ | ~}" group-members)
                     (format nil "~A one of: ~{~A~^ | ~}"
                             (if (option-group-required-p (option-group option))
                                 "exactly"
                                 "at most")
                             group-members)))))
    (dolist (entry +option-relation-labels+)
      (let ((line (%relation-line option options target-table (car entry) (cdr entry))))
        (when line (collect line))))
    ;; Conflicts among members of this option's own group are already conveyed by
    ;; the "one of" line above; only surface conflicts with options outside it.
    (let ((visible-conflicts
            (remove-if (lambda (target)
                         (%option-intra-group-conflict-p option options target
                                                        target-table))
                       (%public-relation-targets option options
                                                 (option-conflicts-with option)
                                                 target-table))))
      (when visible-conflicts
        (collect (format nil "conflicts: ~{~A~^, ~}"
                         (mapcar #'option-relation-target-display-name
                                 visible-conflicts)))))))

(defun %option-metadata-string
    (option options &optional (target-table (%option-target-table options)))
  (%join-help-metadata (%option-metadata-parts option options target-table)))
