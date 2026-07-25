(in-package :cl-cli/test)

;;; Mutation-testing coverage via cl-weave's RUN-MUTATIONS: each mutant flips
;;; one comparison operator in %CONTROL-CHARACTER-P's boundary logic
;;; (src/model-helpers.lisp), and the probe codes below span every boundary
;;; on both sides, so any single flipped comparison must disagree with the
;;; real function on at least one probe -- an assertion-quality guarantee
;;; ordinary example-based tests don't give: it proves the exact comparison
;;; operators (< not <=, >= not >), not just a handful of example inputs.

(defparameter +control-character-probe-codes+
  '(0 31 32 65 126 127 128 159 160 200)
  "Codes straddling every boundary in %CONTROL-CHARACTER-P: 31/32 (the < 32
guard), 127 (the = 127 guard), 127/128 and 159/160 (the >= 128 / < 160
guards), plus 0/65/200 as ordinary control/non-control sanity points.")

(describe-sequential "mutation testing"
  (it "kills every comparison-operator mutant of the control-character boundary logic"
    (let* ((expected (mapcar (lambda (code) (cl-cli::%control-character-p (code-char code)))
                             +control-character-probe-codes+))
           (results (run-mutations
                     '(or (< code 32) (= code 127) (and (>= code 128) (< code 160)))
                     (lambda (form mutation)
                       (declare (ignore mutation))
                       (equal (mapcar (lambda (code) (eval `(let ((code ,code)) ,form)))
                                     +control-character-probe-codes+)
                             expected))
                     :operators '(:comparison-operator))))
      (expect (>= (length results) 4))
      (assert-mutation-score results 1.0))))
