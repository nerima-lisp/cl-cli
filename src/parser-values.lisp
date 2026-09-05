(in-package :cl-cli)

(defvar *option-value-sources* nil
  "Accumulates the provenance of every option value NOT taken from the argv.

A plist of option-key -> one of :ENV, :CONFIG, or :DEFAULT, populated by
APPLY-OPTION-DEFAULTS as it fills absent keys. It is bound fresh per PARSE-ARGV
and read into the resulting invocation. A key that carries a value but is absent
from this map necessarily came from the command line, which is how
OPTION-VALUE-SOURCE derives :COMMAND-LINE without threading state through the
whole parser.")

(defvar *option-value-tail-cells* nil
  "Per-parse cache of tail cons cells for accumulating option values.

PARSE-ARGV binds this to :LAZY rather than an already-allocated hash table:
most parses never touch a :MULTIPLE-P/accumulating option, so the table
itself -- not just its entries -- is built lazily, on the first value that
actually needs one. NIL (the global default) instead means \"not inside
PARSE-ARGV's dynamic extent at all\", the signal %APPEND-ACCUMULATING-OPTION-
VALUE uses to fall back to a plain O(n) APPEND for standalone callers.")

(defun %record-option-source (spec source)
  "Note that SPEC's value was supplied by SOURCE (:env / :config / :default)."
  (setf (getf *option-value-sources* (option-key spec)) source))

(defun option->plist-key (spec)
  (if (typep spec 'option-spec)
      (option-key spec)
      (positional-key spec)))

(defun %ensure-option-value-tail-cells ()
  "Materialize *OPTION-VALUE-TAIL-CELLS* on first use, replacing its :LAZY
placeholder with a real hash table. Only ever called when the variable is
already known truthy (:LAZY or a hash table), never when it is the NIL
\"outside PARSE-ARGV\" signal."
  (if (hash-table-p *option-value-tail-cells*)
      *option-value-tail-cells*
      (setf *option-value-tail-cells* (make-hash-table :test #'eq))))

(defun %remember-option-value-tail (key list)
  (when (and *option-value-tail-cells* list)
    (setf (gethash key (%ensure-option-value-tail-cells)) (last list))))

(defun %append-accumulating-option-value (values key value)
  (let ((cell (list value)))
    (cond
      ((not (plist-has-key-p values key))
       (setf (getf values key) cell)
       (%remember-option-value-tail key cell))
      (*option-value-tail-cells*
       (let* ((table (%ensure-option-value-tail-cells))
              (current (getf values key))
              (tail (or (gethash key table)
                        (when current
                          (setf (gethash key table) (last current))))))
         (if tail
             (setf (cdr tail) cell
                   (gethash key table) cell)
             (progn
               (setf (getf values key) cell)
               (%remember-option-value-tail key cell)))))
      (t
       (setf (getf values key) (append (getf values key) cell)))))
  values)

(defun store-option-value (values spec value)
  (let ((key (option->plist-key spec)))
    (if (and (typep spec 'option-spec)
             (option-multiple-p spec))
        (setf values (%append-accumulating-option-value values key value))
        (setf (getf values key) value)))
  values)

(defun %validate-choice-value (choices raw-value condition message &rest initargs)
  (when (and choices
             (stringp raw-value)
             (not (member raw-value choices :test #'string=)))
    (apply #'signal-cli-error condition message initargs)))

(defmacro %parse-value-with-handler (parser raw-value condition message &rest initargs)
  `(with-value-parse-errors (,condition
                             ,message
                             ,@initargs)
     (funcall ,parser ,raw-value)))

(defun validate-option-choice (spec raw-value)
  (let ((choices (option-choices spec)))
    (%validate-choice-value
     choices
     raw-value
     'cli-invalid-option-value
     (format nil "Invalid value for ~A: ~A (expected one of: ~{~A~^, ~})~A"
             (%option-display-name spec)
             raw-value
             choices
             (format-suggestion-suffix raw-value choices))
     :option (option-key spec)
     :value raw-value)))

(defun parse-option-value (spec raw-value)
  (validate-option-choice spec raw-value)
  (%parse-value-with-handler
   (option-parser spec)
   raw-value
   'cli-invalid-option-value
   (format nil "Invalid value for ~A: ~A"
           (%option-display-name spec)
           raw-value)
   :option (option-key spec)
   :value raw-value))

(defun validate-positional-choice (spec raw-value)
  (let ((choices (positional-choices spec)))
    (%validate-choice-value
     choices
     raw-value
     'cli-invalid-positional-value
     (format nil "Invalid value for positional ~A: ~A ~
                  (expected one of: ~{~A~^, ~})~A"
             (positional-key spec)
             raw-value
             choices
             (format-suggestion-suffix raw-value choices))
     :name (positional-key spec)
     :value raw-value)))

(defun parse-positional-value (spec raw-value)
  (validate-positional-choice spec raw-value)
  (%parse-value-with-handler
   (positional-parser spec)
   raw-value
   'cli-invalid-positional-value
   (format nil "Invalid value for positional ~A: ~A"
           (positional-key spec)
           raw-value)
   :name (positional-key spec)
   :value raw-value))

(defun prepare-option-parser-state (app option-specs &optional cache)
  ;; MAKE-APP validates immutable option relationships and caches each scope's
  ;; built-in-augmented specs/table. Reuse that cache during parsing; the
  ;; fallback keeps standalone callers with ad hoc specs supported.
  (if cache
      (values (car cache) (cdr cache))
      (let* ((specs (option-specs-with-built-ins app option-specs))
             (table (option-table-from-specs specs)))
        (values specs table))))

(defun map-option-values (specs parsed-values fn)
  (dolist (spec specs)
    (let ((key (option-key spec)))
      (when (plist-has-key-p parsed-values key)
        (funcall fn spec key (getf parsed-values key))))))

(defun validate-required-options (values specs)
  (dolist (spec specs values)
    (when (and (option-required-p spec)
               (not (plist-has-key-p values (option-key spec))))
      ;; The more specific subtype: a required option never supplied at all,
      ;; as opposed to one typed with no value after it. Both remain
      ;; CLI-MISSING-OPTION-VALUE for a handler that does not care.
      (signal-cli-error 'cli-missing-required-option
                        (format nil "Missing required option: ~A"
                                (%option-display-name spec))
                        :option (option-key spec)))))

(defun merge-option-values (base-values specs parsed-values)
  (let ((values base-values))
    (map-option-values specs parsed-values
                       (lambda (spec key value)
                         (declare (ignore spec))
                         (setf (getf values key) value)))
    values))

(defun collect-option-values (specs parsed-values)
  (collecting
    (map-option-values specs parsed-values
                       (lambda (spec key value)
                         (declare (ignore spec))
                         (collect key)
                         (collect value)))))
