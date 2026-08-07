(in-package #:cl-cli/test)

(defun concurrent-test-app ()
  (make-app
   :name "batch"
   :commands
   (list
    (make-command
     :name "compile"
     :positionals (list (make-positional :key :input :required-p t))))))

(describe-sequential "concurrent parsing"
  (it "preserves input order for independent requests"
    (let* ((app (concurrent-test-app))
           (batches '(("batch" "compile" "one.lisp")
                      ("batch" "compile" "two.lisp")
                      ("batch" "compile" "three.lisp")))
           (actual (cl-cli/concurrent:parse-argv-batch
                    app batches :parallelism 2 :max-in-flight 2))
           (expected
             (mapcar (lambda (argv)
                       (positional-value (parse-argv app argv) :input))
                     batches)))
      (expect (equal batches (mapcar #'invocation-raw-argv actual)))
      (expect (equal expected
                     (mapcar (lambda (invocation)
                               (positional-value invocation :input))
                             actual)))))

  (it "returns no results for an empty batch"
    (expect (null (cl-cli/concurrent:parse-argv-batch
                   (concurrent-test-app) nil))))

  (it "requires positive concurrency bounds"
    (let ((app (concurrent-test-app)))
      (signals type-error
        (cl-cli/concurrent:parse-argv-batch app nil :parallelism 0))
      (signals type-error
        (cl-cli/concurrent:parse-argv-batch app nil :parallelism -1))
      (signals type-error
        (cl-cli/concurrent:parse-argv-batch app nil :parallelism "two"))
      (signals type-error
        (cl-cli/concurrent:parse-argv-batch app nil :max-in-flight 0))
      (signals type-error
        (cl-cli/concurrent:parse-argv-batch app nil :max-in-flight "two"))))

  (it "propagates parser errors after the batch settles"
    (signals cli-unknown-option
      (cl-cli/concurrent:parse-argv-batch
       (concurrent-test-app)
       '(("batch" "compile" "ok.lisp")
         ("batch" "compile" "--unknown" "bad.lisp"))
       :parallelism 2
       :max-in-flight 2))))
