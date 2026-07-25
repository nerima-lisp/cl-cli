(in-package :cl-cli)

;;;; A JSON schema renderer: emits an app spec as a machine-readable object for
;;;; external tooling (doc generators, GUIs, shell integrations). Dependency
;;;; light -- a small self-contained JSON writer, no external JSON library.
;;;;
;;;; The output describes the author-declared surface: hidden options/commands
;;;; and the auto-added help/version built-ins are omitted, matching the man and
;;;; Markdown renderers. Follows the same optional-stream convention.
;;;;
;;;; Every %WRITE-*-JSON/%JSON-WRITE-* function writes straight to a shared
;;;; STREAM instead of building and returning its own string for a parent to
;;;; copy again -- for a nested app (many commands each with many options),
;;;; the old string-returning design copied a leaf option's text once per
;;;; ancestor (option -> its command's options array -> the command object ->
;;;; the app's commands array -> the app object), the same allocation-cascade
;;;; shape already fixed for the bash/zsh/powershell completion renderers.

(defvar *json-object-first-member-p*
  "True when no member of the JSON object currently being written via
WITH-JSON-OBJECT has been written yet -- rebound per object (including
nested objects), so JSON-MEMBER knows whether to emit a leading comma.")

(defun %json-write-escaped-string (stream text)
  (write-char #\" stream)
  (loop for char across (or text "")
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (t (if (< (char-code char) #x20)
                    (format stream "\\u~4,'0X" (char-code char))
                    (write-char char stream)))))
  (write-char #\" stream))

(defun %json-write-number (stream number)
  "Write NUMBER as a valid JSON numeric token.

Integers print directly; any other real is coerced to a double and printed in
fixed notation so a Lisp exponent marker (`1.5d0`) never leaks into the output."
  (if (integerp number)
      (format stream "~D" number)
      (format stream "~F" (coerce number 'double-float))))

(defun %json-write-bool (stream value)
  (write-string (if value "true" "false") stream))

(defun %json-write-keyword-name (stream keyword)
  (%json-write-escaped-string stream (string-downcase (symbol-name keyword))))

(defun %json-write-array (stream items writer)
  "Write a JSON array to STREAM: '[' then WRITER called as (FUNCALL WRITER
STREAM ITEM) for each of ITEMS, comma-separated, then ']'."
  (write-char #\[ stream)
  (loop for item in items
        for first = t then nil
        do (unless first (write-char #\, stream))
           (funcall writer stream item))
  (write-char #\] stream))

(defun %json-write-string-array (stream strings)
  (%json-write-array stream strings #'%json-write-escaped-string))

(defun %json-write-scalar (stream value)
  "Write a Lisp default VALUE as a JSON scalar or array."
  (cond
    ((null value) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((stringp value) (%json-write-escaped-string stream value))
    ((numberp value) (%json-write-number stream value))
    ((listp value) (%json-write-array stream value #'%json-write-scalar))
    (t (%json-write-escaped-string stream (princ-to-string value)))))

(defun %json-write-deprecated (stream deprecated)
  "Write a :deprecated designator as a JSON value, or do nothing (the caller
must have already checked presence) when DEPRECATED is a bare T."
  (if (stringp deprecated)
      (%json-write-escaped-string stream deprecated)
      (write-string "true" stream)))

(defmacro with-json-object ((stream) &body body)
  "Write a JSON object to STREAM: BODY should call JSON-MEMBER for each
potential key. Handles the leading brace, trailing brace, and the
leading-comma-before-every-member-after-the-first bookkeeping, so each
JSON-MEMBER call only needs to decide whether it has a value at all."
  `(progn
     (write-char #\{ ,stream)
     (let ((*json-object-first-member-p* t))
       ,@body)
     (write-char #\} ,stream)))

(defun json-member (stream key present-p writer)
  "Write \"KEY\":<value> to STREAM via (FUNCALL WRITER) when PRESENT-P is
true, with a leading comma if this isn't the first member written inside the
enclosing WITH-JSON-OBJECT. WRITER receives no arguments -- it closes over
STREAM and whatever value it needs to write, matching every call site's
existing style of computing its own value expression inline."
  (when present-p
    (unless *json-object-first-member-p* (write-char #\, stream))
    (setf *json-object-first-member-p* nil)
    (%json-write-escaped-string stream key)
    (write-char #\: stream)
    (funcall writer)))

(defun %write-option-json (stream option)
  (with-json-object (stream)
    (json-member stream "key" t
                 (lambda () (%json-write-keyword-name stream (option-key option))))
    (json-member stream "names" t
                 (lambda () (%json-write-string-array stream (option-names option))))
    (json-member stream "negatedNames" (option-negated-names option)
                 (lambda () (%json-write-string-array stream (option-negated-names option))))
    (json-member stream "kind" t
                 (lambda () (%json-write-keyword-name stream (option-kind option))))
    (json-member stream "description" (option-description option)
                 (lambda () (%json-write-escaped-string stream (option-description option))))
    (json-member stream "required" t
                 (lambda () (%json-write-bool stream (option-required-p option))))
    (json-member stream "multiple" t
                 (lambda () (%json-write-bool stream (option-multiple-p option))))
    (json-member stream "valueName" (option-value-name option)
                 (lambda () (%json-write-escaped-string stream (option-value-name option))))
    (json-member stream "type" (option-value-type option)
                 (lambda () (%json-write-keyword-name stream (option-value-type option))))
    (json-member stream "min" (option-value-min option)
                 (lambda () (%json-write-number stream (option-value-min option))))
    (json-member stream "max" (option-value-max option)
                 (lambda () (%json-write-number stream (option-value-max option))))
    (json-member stream "delimiter" (option-value-delimiter option)
                 (lambda () (%json-write-escaped-string stream (option-value-delimiter option))))
    (let ((count (option-value-count option)))
      (json-member stream "valueCount"
                   (or (eq count :+) (eq count :*) (and (integerp count) (> count 1)))
                   (lambda ()
                     (cond
                       ((eq count :+) (%json-write-escaped-string stream "+"))
                       ((eq count :*) (%json-write-escaped-string stream "*"))
                       (t (%json-write-number stream count))))))
    (json-member stream "choices" (option-choices option)
                 (lambda () (%json-write-string-array stream (option-choices option))))
    (json-member stream "envVars" (option-env-vars option)
                 (lambda () (%json-write-string-array stream (option-env-vars option))))
    (json-member stream "valueHint" (option-value-hint option)
                 (lambda () (%json-write-keyword-name stream (option-value-hint option))))
    (json-member stream "group" (option-help-group option)
                 (lambda () (%json-write-escaped-string stream (option-help-group option))))
    (json-member stream "default" (option-default-present-p option)
                 (lambda () (%json-write-scalar stream (option-default option))))
    (json-member stream "deprecated" (option-deprecated option)
                 (lambda () (%json-write-deprecated stream (option-deprecated option))))))

(defun %write-positional-json (stream positional)
  (with-json-object (stream)
    (json-member stream "key" t
                 (lambda () (%json-write-keyword-name stream (positional-spec-key positional))))
    (json-member stream "description" (positional-spec-description positional)
                 (lambda () (%json-write-escaped-string stream (positional-spec-description positional))))
    (json-member stream "required" t
                 (lambda () (%json-write-bool stream (positional-spec-required-p positional))))
    (json-member stream "rest" t
                 (lambda () (%json-write-bool stream (positional-spec-rest-p positional))))
    (json-member stream "type" (positional-spec-value-type positional)
                 (lambda () (%json-write-keyword-name stream (positional-spec-value-type positional))))
    (json-member stream "min" (positional-spec-value-min positional)
                 (lambda () (%json-write-number stream (positional-spec-value-min positional))))
    (json-member stream "max" (positional-spec-value-max positional)
                 (lambda () (%json-write-number stream (positional-spec-value-max positional))))
    (json-member stream "choices" (positional-spec-choices positional)
                 (lambda () (%json-write-string-array stream (positional-spec-choices positional))))
    (json-member stream "completionCandidates" (positional-spec-completion-candidates positional)
                 (lambda ()
                   (%json-write-string-array
                    stream (mapcar #'car (positional-spec-completion-candidates positional)))))
    (json-member stream "valueHint" (positional-spec-value-hint positional)
                 (lambda () (%json-write-keyword-name stream (positional-spec-value-hint positional))))
    (json-member stream "minCount" (positional-spec-min-count positional)
                 (lambda () (%json-write-number stream (positional-spec-min-count positional))))
    (json-member stream "maxCount" (positional-spec-max-count positional)
                 (lambda () (%json-write-number stream (positional-spec-max-count positional))))
    (json-member stream "default" (positional-spec-default-present-p positional)
                 (lambda () (%json-write-scalar stream (positional-spec-default positional))))))

(defun %write-command-json (stream command)
  (with-json-object (stream)
    (json-member stream "name" t
                 (lambda () (%json-write-escaped-string stream (command-name command))))
    (json-member stream "aliases" (command-aliases command)
                 (lambda () (%json-write-string-array stream (command-aliases command))))
    (json-member stream "group" (command-group command)
                 (lambda () (%json-write-escaped-string stream (command-group command))))
    (json-member stream "description" (command-description command)
                 (lambda () (%json-write-escaped-string stream (command-description command))))
    (json-member stream "options" t
                 (lambda ()
                   (%json-write-array stream (%doc-visible-options (command-options command))
                                      #'%write-option-json)))
    (json-member stream "positionals" t
                 (lambda ()
                   (%json-write-array stream (command-positionals command) #'%write-positional-json)))
    (json-member stream "examples" (command-examples command)
                 (lambda () (%json-write-string-array stream (command-examples command))))
    (json-member stream "helpFooter" (command-help-footer command)
                 (lambda () (%json-write-escaped-string stream (command-help-footer command))))
    (json-member stream "deprecated" (command-deprecated command)
                 (lambda () (%json-write-deprecated stream (command-deprecated command))))
    (let ((subcommands (%visible-commands (command-subcommands command))))
      (json-member stream "subcommands" subcommands
                   (lambda () (%json-write-array stream subcommands #'%write-command-json))))))

(defparameter +json-schema-version+ 1
  "Version of the object shape RENDER-JSON emits, written as its first member.

This is the format's own version, independent of both the cl-cli release and
the app's `:version'. It gives a consumer something to branch on: a tool
written against schema 1 can refuse a document it does not understand instead
of silently misreading a renamed key. Bump it only when the shape changes in a
way that would break a reader of the previous version -- adding a new
member is not such a change, since JSON readers ignore members they do not
know.")

(defun %write-app-json (stream app)
  (with-json-object (stream)
    (json-member stream "schemaVersion" t
                 (lambda () (%json-write-number stream +json-schema-version+)))
    (json-member stream "name" t
                 (lambda () (%json-write-escaped-string stream (app-name app))))
    (json-member stream "version" (app-version-string app)
                 (lambda () (%json-write-escaped-string stream (app-version-string app))))
    (json-member stream "summary" (app-summary app)
                 (lambda () (%json-write-escaped-string stream (app-summary app))))
    (json-member stream "description" (app-description app)
                 (lambda () (%json-write-escaped-string stream (app-description app))))
    (json-member stream "options" t
                 (lambda ()
                   (%json-write-array stream (%doc-visible-options (app-global-options app))
                                      #'%write-option-json)))
    (json-member stream "positionals" t
                 (lambda () (%json-write-array stream (app-positionals app) #'%write-positional-json)))
    (json-member stream "commands" t
                 (lambda ()
                   (%json-write-array stream (%visible-commands (app-commands app))
                                      #'%write-command-json)))
    (json-member stream "examples" (app-examples app)
                 (lambda () (%json-write-string-array stream (app-examples app))))
    (json-member stream "seeAlso" (app-see-also app)
                 (lambda () (%json-write-string-array stream (app-see-also app))))
    (json-member stream "authors" (app-authors app)
                 (lambda () (%json-write-string-array stream (app-authors app))))))

(defun render-json (app &optional stream)
  "Render APP's spec as a machine-readable JSON object.

With no STREAM, return the JSON as a string. With a STREAM, write to it and
return no values. The object captures the author-declared surface (name,
version, summary, description, global options, positionals, and per-command
options/positionals); hidden entities and the help/version built-ins are
omitted. Output is minified single-line JSON.

The first member is always `schemaVersion', the version of this output shape
itself -- see +JSON-SCHEMA-VERSION+. Consumers should check it before reading
the rest."
  (ensure-output-stream stream render-json app)
  (%write-app-json stream app)
  (terpri stream)
  (values))
