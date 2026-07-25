(in-package :cl-cli/tests)

;;; Fuzz coverage for the parser: PARSE-ARGV must never signal anything other
;;; than CLI-USAGE-ERROR (or a subtype) for adversarial argv, regardless of the
;;; app spec. This complements the example-based and property-based parser
;;; tests by hunting for inputs neither anticipated -- an uncaught TYPE-ERROR,
;;; unbound-variable, or similar would mean a real spec/argv combination can
;;; crash a consumer's CLI outright instead of reporting a usage error.

(defparameter *parser-fuzz-app-builders*
  (list #'cl-cli/examples:make-cl-cc-app
        #'cl-cli/examples:make-cl-tmux-app
        #'cl-cli/examples:make-private-trade-fx-app
        #'cl-cli/examples:make-nshell-app)
  "Every example app in EXAMPLES/CONSUMER-MIGRATIONS.LISP, as zero-argument
constructors so each fuzz trial can build a fresh, unshared app spec.")

(defparameter *parser-fuzz-tokens*
  '("--help" "-h" "--version" "--verbose" "-v" "-vvv" "--"
    "-x" "--tag" "--tag=x" "--count" "--count=abc" "" "-"
    "--unknown-long-option" "positional-arg" "999" "-1" "=" "--=")
  "A pool of option-like, malformed, and plain-argument tokens for IT-FUZZ to
combine adversarially; deliberately includes tokens no example app declares.")

(describe-sequential "parser fuzz"
  (it-fuzz "parse-argv never signals outside CLI-USAGE-ERROR on adversarial argv"
      ((builder (gen-member *parser-fuzz-app-builders*))
       (tokens (gen-list (gen-member *parser-fuzz-tokens*)
                         :min-length 0 :max-length 12)))
      ()
    (let ((app (funcall builder)))
      (handler-case
          (parse-argv app (cons (app-name app) tokens))
        (cli-usage-error () nil)))))
