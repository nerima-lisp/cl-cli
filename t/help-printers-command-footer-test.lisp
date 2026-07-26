(in-package :cl-cli/test)

(describe-sequential "command help footer"
  (it "prints the command help footer in command help"
    (let* ((command (make-command :name "run"
                                  :help-footer "Run notes here."))
           (app (make-app :name "tool" :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Run notes here."))))

  (it "falls back to the app footer when the command has none"
    (let* ((command (make-command :name "run"))
           (app (make-app :name "tool"
                          :help-footer "App footer."
                          :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "App footer."))))

  (it "prefers the command footer over the app footer"
    (let* ((command (make-command :name "run" :help-footer "Command footer."))
           (app (make-app :name "tool"
                          :help-footer "App footer."
                          :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Command footer.")
        (assert-not-searches text "App footer."))))

  (it "includes the command footer in generated docs"
    (let* ((command (make-command :name "run" :help-footer "See docs online."))
           (app (make-app :name "tool" :commands (list command))))
      (let ((man (with-string-output (s) (render-manpage app s)))
            (markdown (with-string-output (s) (render-markdown app s)))
            (json (with-string-output (s) (render-json app s))))
        (assert-searches man "See docs online.")
        (assert-searches markdown "See docs online.")
        (assert-searches json "\"helpFooter\":\"See docs online.\"")))))
