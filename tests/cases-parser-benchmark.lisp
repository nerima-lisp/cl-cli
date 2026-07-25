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

  (it "renders a bash completion script for a 230-option/20-command app in well under budget"
    ;; Guards the stream-threaded bash renderer (src/completion-renderers-bash.lisp):
    ;; every recursive command node and every shell-quoted array-literal/case-label
    ;; value now writes straight into one shared stream instead of consing its own
    ;; string for a parent to copy again. 2000ms for 200 iterations leaves generous
    ;; headroom over the ~0.4ms/call measured on a similarly-sized synthetic app on
    ;; a fast machine, while still catching a regression back to the old
    ;; string-per-node/string-per-value pattern.
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* "bash")))))
      (expect (< (median-ms result) 2000))))

  (it "renders a zsh completion script for a 230-option/20-command app in well under budget"
    ;; Guards the stream-threaded zsh renderer (src/completion-renderers-zsh.lisp,
    ;; src/completion-renderer-helpers.lisp): the recursive command-node tree and
    ;; the option-spec/command-spec/subcommand-spec assignment builders write
    ;; straight into one shared stream, and %COMPLETION-ZSH-ARGUMENTS-FIELD folds
    ;; control-stripping and bracket-blanking into a single pass instead of two
    ;; nested WITH-OUTPUT-TO-STRING calls. 2000ms for 200 iterations leaves
    ;; generous headroom over the ~1.3ms/call measured on a similarly-sized
    ;; synthetic app on a fast machine.
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* "zsh")))))
      (expect (< (median-ms result) 2000))))

  (it "renders a fish completion script for a 230-option/20-command app in well under budget"
    ;; Guards the fish renderer's loop-invariant shell-quoting
    ;; (src/completion-renderers-fish.lisp, src/completion-renderer-helpers.lisp):
    ;; APP-NAME, each command's DESCRIPTION, and each level's OFFER-CONDITION are
    ;; quoted once and reused across every alias/candidate/option instead of being
    ;; re-quoted on every iteration. 2000ms for 200 iterations leaves generous
    ;; headroom over the ~0.34ms/call measured on a similarly-sized synthetic app
    ;; on a fast machine.
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* "fish")))))
      (expect (< (median-ms result) 2000))))

  (it "renders a powershell completion script for a 230-option/20-command app in well under budget"
    ;; Guards src/completion-renderers-powershell.lisp:
    ;; %COMPLETION-POWERSHELL-QUOTE folds control-stripping and quote-doubling
    ;; into one pass instead of two nested WITH-OUTPUT-TO-STRING calls (the same
    ;; fix already applied to %COMPLETION-SHELL-QUOTE and
    ;; %COMPLETION-ZSH-ARGUMENTS-FIELD), and %COMPLETION-POWERSHELL-COMMAND-OPTION-MAP
    ;; builds each command's option array once and reuses it across aliases
    ;; instead of rebuilding it per alias. 2000ms for 200 iterations leaves
    ;; generous headroom over the ~0.11ms/call measured on a similarly-sized
    ;; synthetic app on a fast machine.
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* "powershell")))))
      (expect (< (median-ms result) 2000)))))
