(in-package :cl-cli/test)

(describe-sequential "docs command"
  (it "dispatches the man format to stdout by default"
    (let* ((app (demo-app
                 :summary "Demo tool."
                 :commands (list (make-docs-command))))
           (exit-code nil)
           (text (with-string-output (stdout)
                   (setf exit-code (run-app app :argv '("demo" "docs") :stdout stdout)))))
      (expect (zerop exit-code))
      (assert-searches text ".TH \"DEMO\"" ".SH NAME")))

  (it "dispatches the markdown format"
    (let* ((app (demo-app
                 :summary "Demo tool."
                 :commands (list (make-docs-command))))
           (text (with-string-output (stdout)
                   (run-app app :argv '("demo" "docs" "markdown") :stdout stdout))))
      (assert-searches text "# demo" "## Usage")))

  (it "accepts the md alias"
    (let* ((app (demo-app :commands (list (make-docs-command))))
           (text (with-string-output (stdout)
                   (run-app app :argv '("demo" "docs" "md") :stdout stdout))))
      (assert-searches text "# demo")))

  (it "rejects an unsupported documentation format"
    (let ((app (demo-app :commands (list (make-docs-command)))))
      (signals cli-invalid-positional-value
        (parse-argv app '("demo" "docs" "pdf")))))

  (it "render-docs rejects an unsupported format"
    (signals cli-invalid-positional-value
      (render-docs (demo-app) "pdf")))

  (it "render-docs returns a string with no stream"
    (let ((man (render-docs (demo-app) "man"))
          (markdown (render-docs (demo-app) "markdown")))
      (expect (stringp man))
      (expect (stringp markdown))
      (assert-searches man ".TH \"DEMO\"")
      (assert-searches markdown "# demo")))

  (it "make-standard-commands can include a docs command"
    (let ((names (mapcar #'command-name
                         (make-standard-commands :include-docs-p t))))
      (expect (equal '("help" "version" "docs") names)))))
