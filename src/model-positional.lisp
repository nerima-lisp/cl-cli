(in-package :cl-cli)

(defun make-positional (&key key name description parser type min max choices
                          completion-candidates value-hint complete
                          (default nil default-supplied-p) required-p rest-p
                          min-count max-count)
  "Create a positional argument specification.

TYPE selects a built-in value parser (:integer, :number, :float, :boolean, or
the default :string) and MIN / MAX add inclusive bounds for numeric types, just
as in MAKE-OPTION. A :type and an explicit :parser are mutually exclusive.
CHOICES restricts the value to a closed set, validated before the parser runs
(mismatches signal CLI-INVALID-POSITIONAL-VALUE) and shown in help.

MIN-COUNT / MAX-COUNT constrain how many values a rest positional (:rest-p t)
collects: too few signals CLI-MISSING-POSITIONAL, too many CLI-UNEXPECTED-ARGUMENT.
They require :rest-p and must be non-negative with MIN-COUNT <= MAX-COUNT."
  (when (and (null key)
             (null name))
    (signal-cli-error 'cli-invalid-specification
                      "A positional needs a key or name."))
  (when (and (null key)
             (zerop (length (ensure-string name))))
    (signal-cli-error 'cli-invalid-specification
                      "A positional name must be non-empty."))
  ;; Validate before OPTION-KEYWORD interns a symbol below: see the matching
  ;; comment in MAKE-OPTION. Only applies when NAME derives the key -- an
  ;; explicit KEY is already a keyword the caller chose directly in code, not
  ;; a string, so there is nothing to validate or intern here.
  (when (and (null key) name)
    (validate-safe-identifier-names (list (ensure-string name)) "Positional name"))
  (let ((resolved-key (or key
                          (option-keyword name)))
        (spec (%make-positional-spec)))
    (validate-typed-value-spec type min max parser
                               (format nil "Positional ~S" resolved-key))
    (validate-rest-count-spec resolved-key rest-p min-count max-count)
    (normalize-value-hint value-hint (format nil "Positional ~S" resolved-key))
    (when (and complete (not (functionp complete)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Positional ~S: :complete must be a function." resolved-key)))
    (setf (positional-key spec) resolved-key
          (positional-description spec) (normalize-positional-description description)
          (positional-value-type spec) type
          (positional-value-min spec) min
          (positional-value-max spec) max
          (positional-choices spec) (normalize-option-choices choices)
          (positional-completion-candidates spec)
          (normalize-option-completion-candidates completion-candidates)
          (positional-value-hint spec) value-hint
          (positional-complete spec) complete
          (positional-parser spec) (cond
                                          (type (build-typed-value-parser type min max))
                                          (parser parser)
                                          (t #'identity))
          (positional-default spec) default
          (positional-default-present-p spec) default-supplied-p
          (positional-required-p spec) required-p
          (positional-rest-p spec) rest-p
          (positional-min-count spec) min-count
          (positional-max-count spec) max-count)
    spec))
