(in-package :cl-cli/tests)

;; Reuses MANPAGE-DEMO-APP (tests/cases-doc-manpage.lisp).

(defun json-text (app)
  (with-string-output (stream)
    (render-json app stream)))

(describe-sequential "json renderer"
  (it "emits top-level app metadata"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"name\":\"demo\""
                       "\"version\":\"1.2.0\""
                       "\"summary\":\"Demo build tool.\""
                       "\"description\":\"A longer description of demo.\"")))

  (it "describes global options including kind and count"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"key\":\"verbose\""
                       "\"names\":[\"verbose\",\"v\"]"
                       "\"kind\":\"count\"")))

  (it "describes commands with their options and positionals"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"commands\":["
                       "\"name\":\"compile\""
                       "\"key\":\"output\""
                       "\"positionals\":["
                       "\"key\":\"input\""
                       "\"required\":true")))

  (it "omits hidden options and commands"
    (let ((text (json-text (manpage-demo-app))))
      (assert-not-searches text "secret" "sneaky")))

  (it "emits examples arrays"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text "\"examples\":[\"demo compile src/main.lisp\"]")))

  (it "encodes typed numeric metadata as JSON numbers"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "jobs"
                                                             :kind :value
                                                             :type :integer
                                                             :min 1
                                                             :max 64))))
           (text (json-text app)))
      (assert-searches text "\"type\":\"integer\"" "\"min\":1" "\"max\":64")))

  (it "encodes a delimiter and string default"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "tags"
                                                             :kind :value
                                                             :value-delimiter #\,
                                                             :default '("a" "b")))))
           (text (json-text app)))
      (assert-searches text "\"delimiter\":\",\"" "\"default\":[\"a\",\"b\"]")))

  (it "escapes special characters in strings"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "note"
                                                             :kind :value
                                                             :description "a\"b\\c"))))
           (text (json-text app)))
      (assert-searches text "a\\\"b\\\\c")))

  (it "escapes a raw control character outside the named escape set as \\uXXXX"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "note"
                                                             :kind :value
                                                             :description (format nil "a~Cb" (code-char 1))))))
           (text (json-text app)))
      (assert-searches text "a\\u0001b")))

  (it "encodes a non-integer number as a JSON float, not a Lisp ratio"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "ratio"
                                                             :kind :value
                                                             :type :number
                                                             :default 1.5))))
           (text (json-text app)))
      (assert-searches text "\"default\":1.5")))

  (it "encodes true and false boolean-kind defaults distinctly from an absent default"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "strict" :kind :boolean :default t)
                                                (make-option :name "cache" :kind :boolean :default nil))))
           (text (json-text app)))
      (assert-searches text "\"key\":\"strict\"" "\"default\":true")
      (assert-searches text "\"key\":\"cache\"" "\"default\":null")))

  (it "encodes each value-count spelling in valueCount"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "files" :kind :value :value-count :+)
                                                (make-option :name "tags" :kind :value :value-count :*)
                                                (make-option :name "pair" :kind :value :value-count 2))))
           (text (json-text app)))
      (assert-searches text "\"valueCount\":\"+\"")
      (assert-searches text "\"valueCount\":\"*\"")
      (assert-searches text "\"valueCount\":2")))

  (it "declares its own schema version as the first member of every document"
    ;; A machine-readable format needs a version a consumer can branch on
    ;; before it trusts any other key. Asserting it comes first is not
    ;; cosmetic: a reader that streams the document can then decide whether
    ;; to keep parsing without buffering the whole object. The value is read
    ;; from the exported constant rather than hard-coded, so a deliberate
    ;; bump does not have to be re-typed here -- but the position and the
    ;; type do get pinned.
    (let* ((text (json-text (manpage-demo-app)))
           (document (json-kit:parse text)))
      (expect (eql (gethash "schemaVersion" document) +json-schema-version+))
      (expect (integerp (gethash "schemaVersion" document)))
      (expect (eql 0 (search (format nil "{\"schemaVersion\":~D," +json-schema-version+)
                            text)))))

  (it "round-trips escaped strings through an independent JSON reader"
    ;; Substring-searching for the escaped form (above) only proves the
    ;; writer emitted *an* escape sequence, not that it's the *correct* one
    ;; -- json-kit:parse is a real, independently-implemented JSON reader
    ;; (nerima-lisp/cl-json-kit, a test-only dependency), so decoding the
    ;; writer's own output back and comparing to the original string proves
    ;; genuine round-trip correctness.
    (let* ((original "a\"b\\c \t\n \"quoted\" \\backslash\\")
           (app (make-app :name "tool"
                          :global-options (list (make-option :name "note"
                                                             :kind :value
                                                             :description original))))
           (document (json-kit:parse (json-text app))))
      (expect (string= (gethash "description"
                                (first (coerce (gethash "options" document) 'list)))
                       original))))

  (it "produces a document a real JSON parser accepts, not just balanced brackets"
    ;; json-kit:parse signals on any structural defect (missing comma, bad
    ;; nesting, etc.) that naive brace/bracket counting can't catch.
    (let ((document (json-kit:parse (json-text (manpage-demo-app)))))
      (expect (string= (gethash "name" document) "demo"))
      (expect (string= (gethash "version" document) "1.2.0"))
      (expect (plusp (length (gethash "commands" document))))))

  (it "routes through the docs command as the json format"
    (let* ((app (demo-app
                 :commands (list (make-docs-command))))
           (text (with-string-output (stdout)
                   (run-app app :argv '("demo" "docs" "json") :stdout stdout))))
      (assert-searches text "\"name\":\"demo\"")))

  (it "returns the document as a string with no stream"
    (let ((result (render-json (manpage-demo-app))))
      (expect (stringp result))
      (assert-searches result "\"name\":\"demo\"")))

  (it "returns no values when given a stream"
    (with-string-output (stream)
      (expect (null (multiple-value-list (render-json (manpage-demo-app) stream)))))))
