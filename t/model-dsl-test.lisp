(in-package :cl-cli/test)

;;; DEFINE-APP/DEFINE-COMMAND are purely additive sugar over MAKE-APP/
;;; MAKE-COMMAND/MAKE-OPTION/MAKE-POSITIONAL (src/model-dsl.lisp) -- these
;;; cases exercise the clause vocabulary itself (:option, :positional,
;;; :command, :commands-from) rather than re-testing option/positional
;;; behavior already covered elsewhere.

(define-option *dsl-shared-json-option*
  :name "json" :kind :flag :description "Emit JSON.")

(define-positional *dsl-shared-input-positional*
  :key :input :required-p t :description "Input path.")

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

(defparameter *dsl-command-source-evaluation-count* 0)

(defparameter *dsl-functional-app-reusing-shared-specs*
  (make-app
   :name "functional-reuser"
   :global-options (list *dsl-shared-json-option*)
   :commands (list
              (make-command
               :name "convert"
               :positionals (list *dsl-shared-input-positional*)))))

(defun assert-invalid-dsl (form)
  (expect (lambda ()
            (macroexpand-1 form))
          :to-throw 'error))

(describe-sequential "define-app/define-command DSL"
  (it "binds DEFINE-OPTION and DEFINE-POSITIONAL names to reusable specs"
    (expect (equal (option-key *dsl-shared-json-option*) :json))
    (expect (equal (positional-key *dsl-shared-input-positional*) :input)))

  (it "builds global options via :option clauses"
    (expect (equal (mapcar #'option-key (app-global-options *dsl-demo-app*))
                  '(:verbose))))

  (it "builds positionals via :positional clauses"
    (expect (equal (mapcar #'positional-key (app-positionals *dsl-demo-app*))
                  '(:script-argv))))

  (it "splices :commands-from's list alongside :command clauses"
    (expect (equal (mapcar #'command-name (app-commands *dsl-demo-app*))
                  '("help" "version" "completion" "compile"))))

  (it "evaluates a :commands-from form once when binding an app"
    (setf *dsl-command-source-evaluation-count* 0)
    (let ((name (gensym "DSL-EVALUATED-APP-")))
      (eval
       (macroexpand-1
        `(define-app ,name
             (:name "dsl-evaluated")
           (:commands-from
            (progn
              (incf *dsl-command-source-evaluation-count*)
              (list *dsl-shared-status-command*))))))
      (expect (= *dsl-command-source-evaluation-count* 1))
      (expect (eq (first (app-commands (symbol-value name)))
                  *dsl-shared-status-command*))))

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

  (it "reuses DEFINE-OPTION and DEFINE-POSITIONAL specs through the functional API"
    (expect (eq (first (app-global-options *dsl-functional-app-reusing-shared-specs*))
               *dsl-shared-json-option*))
    (expect (eq (first (command-positionals
                        (first (app-commands *dsl-functional-app-reusing-shared-specs*))))
               *dsl-shared-input-positional*)))

  (it "signals a clear error for a clause headed by an unknown keyword"
    (signals error
      (macroexpand-1 '(define-app *bad-dsl-app* ()
                       (:not-a-real-clause "x"))))))

(describe-sequential "define-app/define-command validation"
  (it "requires exactly one :commands-from form"
    (assert-invalid-dsl
     '(define-app *bad-dsl-app* ()
       (:commands-from)))
    (assert-invalid-dsl
     '(define-app *bad-dsl-app* ()
       (:commands-from '(list) '(list)))))

  (it "rejects malformed DSL argument plists"
    (assert-invalid-dsl
     '(define-app *bad-dsl-app* (:name "bad" :summary)))
    (assert-invalid-dsl
     '(define-command *bad-dsl-command* (:name "bad" :options nil))))

  (it "rejects duplicate structure keys supplied by the DSL"
    (assert-invalid-dsl
     '(define-app *bad-dsl-app* (:name "bad" :commands nil)))
    (assert-invalid-dsl
     '(define-command *bad-dsl-command* (:name "bad" :subcommands nil)))))
