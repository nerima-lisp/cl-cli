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

(describe-sequential "parser benchmark"
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
