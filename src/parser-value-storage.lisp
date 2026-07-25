(in-package :cl-cli)

(defun store-boolean-option (values spec negated-p)
  (store-option-value values spec
                      (parse-option-value spec (not negated-p))))

(defun built-in-option-action (spec action)
  (if (built-in-option-p spec)
      (if (eq (option-key spec) :help) :help :version)
      action))

(defun store-flag-option (values spec action)
  (values (store-option-value values spec t)
          (built-in-option-action spec action)))

(defun store-count-option (values spec action)
  "Increment the integer counter stored under SPEC's key.

Each occurrence of a :count option adds one, so `-vvv` or a repeated
`--verbose` accumulates. A count option is never a built-in, so ACTION passes
through unchanged."
  (let ((key (option-key spec)))
    (setf (getf values key) (1+ (or (getf values key) 0))))
  (values values (built-in-option-action spec action)))

(defun store-boolean-option-value (values spec action negated-p)
  (values (store-boolean-option values spec negated-p)
          (built-in-option-action spec action)))

(defun %append-option-value (values spec value)
  "Append VALUE to SPEC's accumulating list value, regardless of :multiple-p.

Used by delimited options, whose value is always a list: one occurrence such as
`--tags a,b` appends every split piece, and a later occurrence keeps appending."
  (let ((key (option->plist-key spec)))
    (%append-accumulating-option-value values key value)))

(defun store-delimited-option-value (values spec raw-value)
  "Split RAW-VALUE on SPEC's delimiter, parse each piece, and append them all."
  (dolist (piece (split-delimited-value raw-value (option-value-delimiter spec))
                 values)
    (setf values (%append-option-value values spec
                                       (parse-option-value spec piece)))))

(defun store-key-value-pair (values spec raw-value)
  "Parse RAW-VALUE as key=value and append the pair to SPEC's accumulating alist.

A bare `key` (no `=`) records (key . T), so a flag-like define such as `-DNDEBUG`
still records the key. Values stay strings; only the split is interpreted."
  (multiple-value-bind (key value) (split-string-once raw-value #\=)
    (%append-option-value values spec (cons key (if value value t)))))

(defun store-parsed-option-value (values spec action raw-value)
  (values (cond
            ((eq (option-kind spec) :key-value)
             (store-key-value-pair values spec raw-value))
            ((and (typep spec 'option-spec)
                  (option-value-delimiter spec))
             (store-delimited-option-value values spec raw-value))
            (t
             (store-option-value values spec (parse-option-value spec raw-value))))
          (built-in-option-action spec action)))

(defun signal-option-does-not-take-value (token-name)
  (signal-cli-error 'cli-usage-error
                    (format nil "Option ~A does not take a value." token-name)))
