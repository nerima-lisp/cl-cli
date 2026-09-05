(in-package :cl-cli)

;;;; JSON schema renderer for the author-declared application surface.
;;;; Hidden options/commands and auto-added help/version commands are omitted.
;;;; Writers use a shared stream; low-level JSON primitives live in
;;;; DOC-RENDERERS-JSON-WRITER.

(defun %write-option-json (stream option)
  (with-json-object
   (stream)
   (json-required-member stream "key" %json-write-keyword-name (option-key option))
   (json-required-member stream "names" %json-write-string-array (option-names option))
   (json-optional-member stream "negatedNames" %json-write-string-array (option-negated-names option))
   (json-required-member stream "kind" %json-write-keyword-name (option-kind option))
   (json-optional-member stream "description" %json-write-escaped-string (option-description option))
   (json-required-member stream "required" %json-write-bool (option-required-p option))
   (json-required-member stream "multiple" %json-write-bool (option-multiple-p option))
   (json-optional-member stream "valueName" %json-write-escaped-string (option-value-name option))
   (json-optional-member stream "type" %json-write-keyword-name (option-value-type option))
   (json-optional-member stream "min" %json-write-number (option-value-min option))
   (json-optional-member stream "max" %json-write-number (option-value-max option))
   (json-optional-member stream "delimiter" %json-write-escaped-string (option-value-delimiter option))
   (let ((count (option-value-count option)))
     (json-member
      stream
      "valueCount"
      (or (eq count :+) (eq count :*) (and (integerp count) (> count 1)))
      (lambda ()
        (cond
          ((eq count :+) (%json-write-escaped-string stream "+"))
          ((eq count :*) (%json-write-escaped-string stream "*"))
          (t (%json-write-number stream count))))))
   (json-optional-member stream "choices" %json-write-string-array (option-choices option))
   (json-optional-member stream "envVars" %json-write-string-array (option-env-vars option))
   (json-optional-member stream "valueHint" %json-write-keyword-name (option-value-hint option))
   (json-optional-member stream "group" %json-write-escaped-string (option-help-group option))
   (json-optional-member
    stream
    "default"
    %json-write-scalar
    (option-default option)
    (option-default-present-p option))
   (json-optional-member stream "deprecated" %json-write-deprecated (option-deprecated option))))

(defun %write-positional-json (stream positional)
  (with-json-object
   (stream)
   (json-required-member stream "key" %json-write-keyword-name (positional-key positional))
   (json-optional-member stream "description" %json-write-escaped-string (positional-description positional))
   (json-required-member stream "required" %json-write-bool (positional-required-p positional))
   (json-required-member stream "rest" %json-write-bool (positional-rest-p positional))
   (json-optional-member stream "type" %json-write-keyword-name (positional-value-type positional))
   (json-optional-member stream "min" %json-write-number (positional-value-min positional))
   (json-optional-member stream "max" %json-write-number (positional-value-max positional))
   (json-optional-member stream "choices" %json-write-string-array (positional-choices positional))
   (json-member
    stream
    "completionCandidates"
    (positional-completion-candidates positional)
    (lambda ()
      (%json-write-string-array
       stream
       (mapcar #'car (positional-completion-candidates positional)))))
   (json-optional-member stream "valueHint" %json-write-keyword-name (positional-value-hint positional))
   (json-optional-member stream "minCount" %json-write-number (positional-min-count positional))
   (json-optional-member stream "maxCount" %json-write-number (positional-max-count positional))
   (json-optional-member
    stream
    "default"
    %json-write-scalar
    (positional-default positional)
    (positional-default-present-p positional))))

(defun %write-command-json (stream command)
  (with-json-object
   (stream)
   (json-required-member stream "name" %json-write-escaped-string (command-name command))
   (json-optional-member stream "aliases" %json-write-string-array (command-aliases command))
   (json-optional-member stream "group" %json-write-escaped-string (command-group command))
   (json-optional-member stream "description" %json-write-escaped-string (command-description command))
   (json-member
    stream
    "options"
    t
    (lambda ()
      (%json-write-array
       stream
       (%doc-visible-options (command-options command))
       #'%write-option-json)))
   (json-member
    stream
    "positionals"
    t
    (lambda ()
      (%json-write-array
       stream
       (command-positionals command)
       #'%write-positional-json)))
   (json-optional-member stream "examples" %json-write-string-array (command-examples command))
   (json-optional-member stream "helpFooter" %json-write-escaped-string (command-help-footer command))
   (json-optional-member stream "deprecated" %json-write-deprecated (command-deprecated command))
   (let ((subcommands (%visible-commands (command-subcommands command))))
     (json-member
      stream
      "subcommands"
      subcommands
      (lambda ()
        (%json-write-array stream subcommands #'%write-command-json))))))

(defconstant +json-schema-version+ 1
  "Version of the object shape RENDER-JSON emits, written as its first member.

This is the format's own version, independent of both the cl-cli release and
the app's `:version'. It gives a consumer something to branch on: a tool
written against schema 1 can refuse a document it does not understand instead
of silently misreading a renamed key. Bump it only when the shape changes in a
way that would break a reader of the previous version -- adding a new
member is not such a change, since JSON readers ignore members they do not
know.")

(defun %write-app-json (stream app)
  (with-json-object
   (stream)
   (json-required-member stream "schemaVersion" %json-write-number +json-schema-version+)
   (json-required-member stream "name" %json-write-escaped-string (app-name app))
   (json-optional-member stream "version" %json-write-escaped-string (app-version-string app))
   (json-optional-member stream "summary" %json-write-escaped-string (app-summary app))
   (json-optional-member stream "description" %json-write-escaped-string (app-description app))
   (json-member
    stream
    "options"
    t
    (lambda ()
      (%json-write-array
       stream
       (%doc-visible-options (app-global-options app))
       #'%write-option-json)))
   (json-member
    stream
    "positionals"
    t
    (lambda ()
      (%json-write-array stream (app-positionals app) #'%write-positional-json)))
   (json-member
    stream
    "commands"
    t
    (lambda ()
      (%json-write-array
       stream
       (%visible-commands (app-commands app))
       #'%write-command-json)))
   (json-optional-member stream "examples" %json-write-string-array (app-examples app))
   (json-optional-member stream "seeAlso" %json-write-string-array (app-see-also app))
   (json-optional-member stream "authors" %json-write-string-array (app-authors app))))

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
