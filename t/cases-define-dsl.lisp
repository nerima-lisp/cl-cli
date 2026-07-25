(in-package :cl-cli/test)

;;; DEFINE-APP/DEFINE-COMMAND are purely additive sugar over MAKE-APP/
;;; MAKE-COMMAND/MAKE-OPTION/MAKE-POSITIONAL (src/model-dsl.lisp) -- these
;;; cases exercise the clause vocabulary itself (:option, :positional,
;;; :command, :commands-from) rather than re-testing option/positional
;;; behavior already covered elsewhere.

(define-app *dsl-demo-app*
    (:name "dsl-demo" :summary "A DEFINE-APP smoke test app.")
  (:option "verbose" :short #\v :kind :flag)
  (:positional :script-argv :rest-p t)
  (:commands-from (make-standard-commands :include-completion-p t))
  (:command "compile" (:aliases '("build") :description "Compile a source file.")
    (:option "output" :short #\o :kind :value)
    (:positional :input :required-p t)
    (:command "verify" (:description "Verify a compiled artifact.")
      (:option "strict" :kind :flag))))

(define-command *dsl-shared-status-command*
    (:name "status" :description "Show shared status.")
  (:option "json" :kind :flag))

(define-app *dsl-app-reusing-shared-command*
    (:name "dsl-reuser")
  (:commands-from (list *dsl-shared-status-command*)))

(describe-sequential "define-app/define-command DSL"
  (it "builds global options via :option clauses"
    (expect (equal (mapcar #'option-key (app-global-options *dsl-demo-app*))
                  '(:verbose))))

  (it "builds positionals via :positional clauses"
    (expect (equal (mapcar #'positional-key (app-positionals *dsl-demo-app*))
                  '(:script-argv))))

  (it "splices :commands-from's list alongside :command clauses"
    (expect (equal (mapcar #'command-name (app-commands *dsl-demo-app*))
                  '("help" "version" "completion" "compile"))))

  (it "builds a :command clause's own options and positionals"
    (let ((compile-command (find "compile" (app-commands *dsl-demo-app*)
                                 :key #'command-name :test #'string=)))
      (expect (equal (mapcar #'option-key (command-options compile-command))
                    '(:output)))
      (expect (equal (mapcar #'positional-key
                             (command-positionals compile-command))
                    '(:input)))
      (expect (equal (command-aliases compile-command) '("build")))))

  (it "recursively builds a :command clause's nested subcommands"
    (let* ((compile-command (find "compile" (app-commands *dsl-demo-app*)
                                  :key #'command-name :test #'string=))
           (verify-command (find "verify" (cl-cli::command-subcommands compile-command)
                                 :key #'command-name :test #'string=)))
      (expect verify-command)
      (expect (equal (mapcar #'option-key (command-options verify-command))
                    '(:strict)))))

  (it "dispatches through a DEFINE-APP-built app exactly like MAKE-APP"
    (with-parsed-argv (invocation *dsl-demo-app*
                                  (list "dsl-demo" "--verbose" "compile"
                                        "--output" "a.out" "in.lisp"))
      (option-values= invocation :verbose t :output "a.out")
      (positional-values= invocation :input "in.lisp")))

  (it "binds DEFINE-COMMAND's name to an independently reusable command spec"
    (expect (string= (command-name *dsl-shared-status-command*) "status"))
    (expect (equal (mapcar #'option-key
                          (command-options *dsl-shared-status-command*))
                  '(:json))))

  (it "reuses a DEFINE-COMMAND spec across more than one DEFINE-APP via :commands-from"
    (expect (equal (mapcar #'command-name
                          (app-commands *dsl-app-reusing-shared-command*))
                  '("status")))
    (expect (eq (first (app-commands *dsl-app-reusing-shared-command*))
               *dsl-shared-status-command*)))

  (it "signals a clear error for a clause headed by an unknown keyword"
    (signals error
      (macroexpand-1 '(define-app *bad-dsl-app* ()
                       (:not-a-real-clause "x"))))))
