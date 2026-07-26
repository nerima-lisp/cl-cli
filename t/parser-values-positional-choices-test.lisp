(in-package :cl-cli/test)

(defun positional-choice-app ()
  (make-app :name "tool"
            :positionals (list (make-positional :key :env
                                                :required-p t
                                                :description "Target env."
                                                :choices '("dev" "prod")))))

(describe-sequential "positional choices"
  (it "accepts a value in the choice set"
    (with-parsed-argv (inv (positional-choice-app) '("tool" "prod"))
      (expect (string= (positional-value inv :env) "prod"))))

  (it "rejects a value outside the choice set"
    (signals cli-invalid-positional-value
      (parse-argv (positional-choice-app) '("tool" "staging"))))

  (it "reports the expected choices in the error"
    (caught-signal= (cli-invalid-positional-value condition)
        (parse-argv (positional-choice-app) '("tool" "staging"))
      (:eq cli-invalid-positional-value-name :env)
      (:searches cli-error-message "expected one of: dev, prod")))

  (it "shows the choices in help output"
    (with-app-help-text (text (positional-choice-app))
      (assert-searches text "choices: dev | prod")))

  (it "emits the choices in json"
    (let ((text (with-string-output (stream)
                  (render-json (positional-choice-app) stream))))
      (assert-searches text "\"choices\":[\"dev\",\"prod\"]"))))
