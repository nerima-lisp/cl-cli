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

(defparameter *benchmark-large-completion-app*
  (make-app
   :name "bench-large"
   :global-options (loop for i below 30
                         collect (make-option :name (format nil "global-opt-~D" i)
                                              :kind :value))
   :commands (loop for i below 20
                   collect (make-command
                            :name (format nil "cmd-~D" i)
                            :options (loop for j below 10
                                          collect (make-option
                                                   :name (format nil "cmd~D-opt-~D" i j)
                                                   :kind :value))))))

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
      (expect (< (median-ms result) 2000))))

  (it "deduplicates a large candidate list in well under budget (guards against an O(n^2) regression)"
    ;; %COMPLETION-SPACE-JOINED and the bash/zsh renderers' shell-quoting
    ;; writers use :TEST #'EQUAL rather than #'STRING= -- semantically
    ;; identical for strings, but lets SBCL dispatch REMOVE-DUPLICATES to a
    ;; hash-table-based scan. On 10,000 strings (1,000 distinct, so real
    ;; duplicates get removed), :TEST #'STRING= takes ~35ms on a fast
    ;; machine; :TEST #'EQUAL is sub-millisecond. 50ms budget leaves
    ;; generous room for a slow CI machine while still failing hard if this
    ;; regresses to #'STRING=.
    (let* ((strings (loop for i below 10000 collect (format nil "cmd-~D" (mod i 1000))))
           (result (benchmark (:warmup 1 :samples 5)
                     (cl-cli::%completion-space-joined strings))))
      (expect (< (median-ms result) 50))))

  ;; One `it-each` case per shell, all guarding the same property: rendering
  ;; a 230-option/20-command app 200 times stays well under budget. This
  ;; catches a regression back to a per-node/per-value string-consing
  ;; pattern for ANY renderer, including the ones a stream-threading or
  ;; single-pass-quoting fix hasn't touched yet -- elvish and nushell had no
  ;; benchmark at all before this, despite getting the same double-pass-
  ;; quoting fix as powershell and markdown in the same commit that added
  ;; the bash/zsh/fish/powershell cases below.
  (it-each (("bash") ("zsh") ("fish") ("powershell") ("nushell") ("elvish"))
      "renders a ~A completion script for a 230-option/20-command app in well under budget"
      (shell)
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* shell)))))
      (expect (< (median-ms result) 2000)))))
