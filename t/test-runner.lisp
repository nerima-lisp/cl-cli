(in-package :cl-cli/test)

(defun run-tests ()
  "Run cl-weave suites with a timeout when the host supports it.

The empty-registry check prevents a broken loader from reporting success.
Portable implementations still run the full suite without a framework timeout."
  (unless (if (harness-timeout-available-p)
              (run-all :timeout-ms 120000
                       :pass-with-no-tests nil)
              (run-all :pass-with-no-tests nil))
    (error "Test suite failed."))
  t)
