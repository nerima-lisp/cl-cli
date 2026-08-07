(in-package :cl-cli/test)

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

;; Keep the basic success and expected-error contracts outside the timeout
;; capability gate. A missing cl-weave timeout must not hide these checks.
(describe-sequential "parser fuzz deterministic contracts"
  (it "accepts a valid empty invocation"
    (expect (parse-argv (make-app :name "fuzz")
                        '("fuzz"))))
  (it "preserves values for a valid structured invocation"
    (let ((app (make-app
                :name "fuzz"
                :global-options
                (list (make-option :name "verbose" :kind :flag))
                :commands
                (list (make-command
                       :name "run"
                       :options
                       (list (make-option :name "output" :kind :value))
                       :positionals
                       (list (make-positional :key :input :required-p t)))))))
      (with-parsed-argv (invocation app
                                    '("fuzz" "--verbose" "run"
                                      "--output" "out" "input"))
        (option-values= invocation :verbose t :output "out")
        (positional-values= invocation :input "input")
        (expect (string= (command-name (invocation-command invocation))
                         "run")))))
  (it "reports an unknown option as a usage error"
    (signals cli-unknown-option
      (parse-argv (make-app :name "fuzz")
                  '("fuzz" "--unknown")))))

;; IT-FUZZ needs cl-weave's :TIMEOUT capability to bound a runaway trial; see
;; HARNESS-TIMEOUT-AVAILABLE-P in t/helpers-gates.lisp for why that gates
;; the suite rather than being asserted inside it.
(cl-weave:describe-run-if (harness-timeout-available-p) "parser fuzz"
  (it-fuzz "parse-argv never signals outside CLI-USAGE-ERROR on adversarial argv"
      ((builder (gen-member *parser-fuzz-app-builders*))
       (tokens (gen-list (gen-member *parser-fuzz-tokens*)
                         :min-length 0 :max-length 12)))
      ()
    (let ((app (funcall builder)))
      (handler-case
          (progn (parse-argv app (cons (app-name app) tokens)) t)
        (cli-usage-error () t)))))
