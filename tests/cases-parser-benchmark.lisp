(in-package :cl-cli/tests)

;;; Regression coverage for the CPS-converted parser scan loops
;;; (%SCAN-OPTIONS-PREFIX, %SCAN-MIXED-ARGUMENTS, %SCAN-SHORT-CLUSTER in
;;; src/parser-consumption.lisp and src/parser-option-consumption.lisp). Each
;;; recurses once per token/character instead of looping with an accumulator;
;;; these benchmarks are a committed, re-runnable proof that SBCL still
;;; tail-call-optimizes every recursive case, so a large PARSE-ARGV input
;;; completes in milliseconds rather than overflowing the control stack.

(defparameter *benchmark-flag-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v
                                               :kind :flag))))

(defparameter *benchmark-rest-app*
  (make-app :name "bench"
            :positionals (list (make-positional :key :rest :rest-p t))))

(defparameter *benchmark-count-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v
                                               :kind :count))))

(defparameter *benchmark-subcommand-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v :kind :flag))
            :commands (list (make-command
                             :name "build"
                             :options (list (make-option :name "target" :kind :value)
                                           (make-option :name "release" :kind :flag))
                             :positionals (list (make-positional :key :input
                                                                 :required-p t))))))

(describe-sequential "parser benchmark"
  (it "caches each scope's built-in-augmented specs and lookup table once at MAKE-APP time"
    ;; PREPARE-OPTION-PARSER-STATE reuses these (SPECS . TABLE) conses instead
    ;; of rebuilding them (re-running MAKE-OPTION for --help/--version and
    ;; repopulating a hash table) on every PARSE-ARGV call -- see
    ;; src/model-validation.lisp's %VALIDATE-APP-SPEC/%VALIDATE-COMMAND-NODE.
    (expect (consp (cl-cli::app-global-option-cache *benchmark-subcommand-app*)))
    (let* ((build-command (first (app-commands *benchmark-subcommand-app*)))
           (cache (gethash build-command
                          (cl-cli::app-command-option-caches *benchmark-subcommand-app*))))
      (expect (consp cache))
      (expect (member :target (mapcar #'option-key (car cache))))))

  (it "caches built-in-option-specs once at MAKE-APP time for help/completion renderers too"
    ;; BUILT-IN-OPTION-SPECS is called directly by the help printers and every
    ;; completion renderer, not just PREPARE-OPTION-PARSER-STATE -- confirm it
    ;; reads a cache populated at MAKE-APP time instead of re-running
    ;; MAKE-OPTION to reconstruct --help/--version on every render.
    (let ((specs (cl-cli::built-in-option-specs *benchmark-subcommand-app*)))
      (expect (eq specs (cl-cli::app-cached-built-in-option-specs
                        *benchmark-subcommand-app*)))
      (expect (eq (option-key (first specs)) :help))))

  (it "repeated small parses against the same app stay well under budget"
    ;; The realistic cl-cli workload: many independent PARSE-ARGV calls
    ;; against one long-lived APP (a REPL, a server, or simply this loop),
    ;; not one huge argv -- exercises the per-scope caches above rather than
    ;; the CPS scan loops' own asymptotic behavior. 100,000 calls, same
    ;; 2000ms budget convention as the CPS benchmarks below.
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 100000)
                      (parse-argv *benchmark-subcommand-app*
                                 '("bench" "-v" "build" "--target" "x86" "in.lisp"))))))
      (expect (< (median-ms result) 2000))))

  (it "scans a 5,000-flag argv (%SCAN-OPTIONS-PREFIX) in well under budget"
    (let* ((argv (list* "bench" (loop repeat 5000 collect "--verbose")))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-flag-app* argv))))
      (expect (< (median-ms result) 2000))))

  (it "scans 5,000 positional tokens (%SCAN-MIXED-ARGUMENTS) in well under budget"
    (let* ((argv (list* "bench" "--" (loop for index below 5000
                                           collect (format nil "arg~D" index))))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-rest-app* argv))))
      (expect (< (median-ms result) 2000))))

  (it "scans a 20,000-character short cluster (%SCAN-SHORT-CLUSTER) in well under budget"
    (let* ((argv (list "bench" (format nil "-~A" (make-string 20000
                                                              :initial-element #\v))))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-count-app* argv))))
      (expect (< (median-ms result) 2000)))))
