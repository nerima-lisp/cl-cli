(in-package :cl-cli)

(defun %command-display-name (command)
  (if (command-aliases command)
      (format nil "~A (~{~A~^, ~})"
              (command-name command)
              (command-aliases command))
      (command-name command)))

(defun %usage-options-token (label)
  (format nil "[~A]" label))

(defun %option-display-string (option)
  (with-output-to-string (out)
    (let ((index 0))
      (labels ((write-option-name (name)
                 (when (> index 0)
                   (write-string ", " out))
                 (write-string (option-token-display-name name) out)
                 (incf index)))
        (dolist (name (option-names option))
          (write-option-name name))
        (dolist (name (option-negated-names option))
          (write-option-name name))))
    (when (%option-carries-value-p option)
      (let ((value-name (or (option-value-name option)
                            (symbol-name (option-key option))))
            (count (or (option-value-count option) 1)))
        (cond
          ((eq (option-kind option) :optional-value)
           (format out "[=<~A>]" value-name))
          ((variadic-value-count-p count)
           (format out " <~A>..." value-name))
          ((and (integerp count) (> count 1))
           (dotimes (i count)
             (format out " <~A>" value-name)))
          (t
           (format out " <~A>" value-name)))))))

(defun %required-option-synopsis-token (option)
  "Render OPTION as a compact required-option synopsis fragment.

Just the primary name and, for value-bearing kinds, a `<VALUE>` placeholder --
e.g. `--output <FILE>`. Unlike %OPTION-DISPLAY-STRING this omits aliases and
short forms, which belong in the OPTIONS listing, not the one-line synopsis."
  (with-output-to-string (out)
    (write-string (option-token-display-name (first (option-names option))) out)
    (when (%option-carries-value-p option)
      (let ((value-name (or (option-value-name option)
                            (symbol-name (option-key option)))))
        (format out " <~A>" value-name)))))

(defun %required-options-synopsis (options)
  "A leading-space synopsis of the visible, required options in OPTIONS.

Required options are spelled out in the usage line -- e.g. `--output <FILE>` --
so the synopsis shows what the user must supply instead of burying it in the
`[options]` catch-all. Non-required and hidden options stay in the catch-all;
built-ins are never required, so they never appear here. Returns \"\" when there
are no required options, leaving existing usage lines untouched."
  (with-output-to-string (out)
    (dolist (option options)
      (when (and (option-required-p option)
                 (not (option-hidden-p option)))
        (format out " ~A" (%required-option-synopsis-token option))))))

(defun %option-description-string
    (option options &optional (target-table (%option-target-table options)))
  (concatenate 'string
               (or (option-description option) "")
               (%option-metadata-string option options target-table)))

(defun %print-option-row
    (stream option options &optional (target-table (%option-target-table options)))
  (%emit-help-row stream
                  (%style-padded-name (%option-display-string option) 24)
                  (%option-description-string option options target-table)))

(defun %usage-positionals-string (positionals)
  (with-output-to-string (out)
    (dolist (positional positionals)
      (format out " ~A" (%format-positional-token positional)))))

(defun %format-root-usage (app)
  (with-output-to-string (out)
    (format out "Usage: ~A" (%terminal-safe-text (app-name app)))
    (when (app-global-options app)
      (format out " ~A" (%usage-options-token "global-options")))
    (write-string (%required-options-synopsis (app-global-options app)) out)
    (cond
      ((app-positionals app)
       (write-string (%usage-positionals-string (app-positionals app)) out))
      ((app-handler app)
       (format out " ~A" (%usage-options-token "args"))))
    (terpri out)))

(defun %format-positional-token (positional)
  (let ((name (symbol-name (positional-spec-key positional))))
    (cond
      ((positional-spec-rest-p positional)
       (if (positional-spec-required-p positional)
           (format nil "~A..." name)
           (format nil "[~A...]" name)))
      ((positional-spec-required-p positional)
       name)
      (t
       (format nil "[~A]" name)))))

(defun %visible-commands (commands)
  (stable-sort-copy (remove-if #'command-hidden-p commands)
                    #'string<
                    :key #'command-name))

(defun %command-sections (commands)
  (let ((ungrouped nil)
        (group-order nil)
        (group-table (make-hash-table :test #'equal)))
    (dolist (command commands)
      (let ((group (command-group command)))
        (if group
            (progn
              (unless (gethash group group-table)
                (setf (gethash group group-table) nil)
                (push group group-order))
              (push command (gethash group group-table)))
            (push command ungrouped))))
    (nconc (when ungrouped
             (list (cons nil (nreverse ungrouped))))
           (mapcar (lambda (group)
                     (cons group (nreverse (gethash group group-table))))
                   (nreverse group-order)))))

(defun %command-description-string (command)
  "COMMAND's description with a trailing deprecation note when applicable.

Shared by the interactive help printer and the man/Markdown doc renderers so a
deprecated command reads the same everywhere."
  (let ((deprecation (%deprecation-note (command-deprecated command)))
        (description (or (command-description command) "")))
    (cond
      ((null deprecation) description)
      ((plusp (length description)) (format nil "~A (~A)" description deprecation))
      (t (format nil "(~A)" deprecation)))))

(defun %print-command-row (stream command)
  (%emit-help-row stream
                  (%style-padded-name (%command-display-name command) 24)
                  (%command-description-string command)))

(defun %format-command-dispatch-usage (app)
  (format nil "Usage: ~A~A <command> [args]~%"
          (%terminal-safe-text (app-name app))
          (%required-options-synopsis (app-global-options app))))

(defun %print-commands (stream commands)
  (let ((sections (%command-sections (%visible-commands commands))))
    (when sections
      (format stream "~&~A~%" (%style-heading "Commands:"))
      (dolist (section sections)
        (when (car section)
          (format stream "~&~A~%" (%style-heading (format nil "~A:" (car section)))))
        (dolist (command (cdr section))
          (%print-command-row stream command))))))

(defun %positional-metadata-parts (positional)
  (let ((parts nil))
    (when (positional-spec-default-present-p positional)
      (push (format nil "default: ~A" (positional-spec-default positional)) parts))
    (when (and (positional-spec-value-type positional)
               (not (eq (positional-spec-value-type positional) :string)))
      (push (format nil "type: ~(~A~)" (positional-spec-value-type positional)) parts))
    (let ((range (%numeric-range-metadata (positional-spec-value-min positional)
                                          (positional-spec-value-max positional))))
      (when range
        (push range parts)))
    (when (positional-spec-choices positional)
      (push (format nil "choices: ~{~A~^ | ~}" (positional-spec-choices positional))
            parts))
    (let ((hint (%value-hint-note (positional-spec-value-hint positional))))
      (when hint (push hint parts)))
    (let ((min (positional-spec-min-count positional))
          (max (positional-spec-max-count positional)))
      (cond
        ((and min max) (push (format nil "~A..~A values" min max) parts))
        (min (push (format nil "at least ~A value~:P" min) parts))
        (max (push (format nil "at most ~A value~:P" max) parts))))
    (nreverse parts)))

(defun %positional-description-string (positional)
  (concatenate 'string
               (or (positional-spec-description positional) "")
               (%join-help-metadata (%positional-metadata-parts positional))))

(defun %print-positional-row (stream positional)
  (%emit-help-row stream
                  (%style-padded-name (%format-positional-token positional) 24)
                  (%positional-description-string positional)))

(defun %print-examples (stream examples)
  (when examples
    (format stream "~&~A~%" (%style-heading "Examples:"))
    (dolist (example examples)
      (format stream "  ~A~%" (%terminal-safe-text example)))))
