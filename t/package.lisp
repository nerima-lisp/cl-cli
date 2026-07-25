(defpackage :cl-cli/test
  (:use :cl :cl-cli)
  (:import-from :cl-prolog
                :assertz
                :make-rulebase
                :query-prolog)
  (:import-from :cl-prolog/weave
                :deftest-queries)
  (:import-from :cl-weave
                :assert-mutation-score
                :benchmark
                :describe-sequential
                :describe-skip
                :expect
                :gen-list
                :gen-member
                :gen-string
                :it
                :it-each
                :it-fuzz
                :it-property
                :it-run-if
                :median-ms
                :run-all
                :run-mutations
                :signals
                :with-soft-assertions)
  (:export :run-tests))

(in-package :cl-cli/test)

(defmacro with-string-output ((stream) &body body)
  `(let ((,stream (make-string-output-stream)))
     ,@body
     (get-output-stream-string ,stream)))
