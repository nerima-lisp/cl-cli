(in-package #:cl-cli/concurrent)

(defun parse-argv-batch (app argv-batches &key (parallelism 4) max-in-flight)
  "Parse independent ARGV-BATCHES concurrently and preserve their input order.

APP should be an immutable CL-CLI application specification. PARALLELISM is
the number of worker threads. MAX-IN-FLIGHT bounds admitted requests and
defaults to twice PARALLELISM. Parser errors propagate after all submitted
requests settle."
  (check-type parallelism (integer 1 *))
  (let ((in-flight-limit (or max-in-flight (* 2 parallelism))))
    (check-type in-flight-limit (integer 1 *))
    (let ((requests (coerce argv-batches 'vector)))
      (unless (zerop (array-total-size requests))
        (cl-concurrent-kit:with-executor
            (executor
             :size parallelism
             :queue-capacity in-flight-limit
             :name "cl-cli parse-argv-batch")
          (cl-concurrent-kit:executor-map
           executor
           (lambda (argv)
             (cl-cli:parse-argv app argv))
           requests
           :max-in-flight in-flight-limit))))))
