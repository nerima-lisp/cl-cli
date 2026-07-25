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
    (setf (positional-spec-key spec) resolved-key
          (positional-spec-description spec) (normalize-positional-description description)
          (positional-spec-value-type spec) type
          (positional-spec-value-min spec) min
          (positional-spec-value-max spec) max
          (positional-spec-choices spec) (normalize-option-choices choices)
          (positional-spec-completion-candidates spec)
          (normalize-option-completion-candidates completion-candidates)
          (positional-spec-value-hint spec) value-hint
          (positional-spec-complete spec) complete
          (positional-spec-parser spec) (cond
                                          (type (build-typed-value-parser type min max))
                                          (parser parser)
                                          (t #'identity))
          (positional-spec-default spec) default
          (positional-spec-default-present-p spec) default-supplied-p
          (positional-spec-required-p spec) required-p
          (positional-spec-rest-p spec) rest-p
          (positional-spec-min-count spec) min-count
          (positional-spec-max-count spec) max-count)
    spec))
