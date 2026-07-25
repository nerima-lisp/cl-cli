;;; Command-line entry point:
;;;   sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
;;;   ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'

(eval-when (:load-toplevel :execute)
  (require :asdf))

(eval-when (:load-toplevel :execute)
  (let* ((asdf-package (or (find-package :asdf)
                           (error "ASDF package is unavailable.")))
         (uiop-package (or (find-package :uiop)
                           (error "UIOP package is unavailable.")))
         (load-system (or (find-symbol "LOAD-SYSTEM" asdf-package)
                          (error "ASDF does not provide LOAD-SYSTEM.")))
         (getenv (or (find-symbol "GETENV" uiop-package)
                     (error "UIOP does not provide GETENV.")))
         (directory-pathname (or (find-symbol "PATHNAME-DIRECTORY-PATHNAME" uiop-package)
                                 (error "UIOP does not provide PATHNAME-DIRECTORY-PATHNAME.")))
         (test-file (or *load-truename* *compile-file-truename*))
         (project-root (merge-pathnames #P"../"
                                        (funcall directory-pathname test-file)))
         (weave-env-source (funcall getenv "CL_WEAVE_SOURCE_DIR"))
         (prolog-env-source (funcall getenv "CL_PROLOG_SOURCE_DIR"))
         (boundary-kit-env-source (funcall getenv "CL_BOUNDARY_KIT_SOURCE_DIR"))
         (log-kit-env-source (funcall getenv "CL_LOG_KIT_SOURCE_DIR"))
         (process-kit-env-source (funcall getenv "CL_PROCESS_KIT_SOURCE_DIR"))
         (weave-local-source (merge-pathnames #P"../cl-weave/" project-root))
         (prolog-local-source (merge-pathnames #P"../cl-prolog/" project-root))
         (boundary-kit-local-source (merge-pathnames #P"../cl-boundary-kit/" project-root))
         (log-kit-local-source (merge-pathnames #P"../cl-log-kit/" project-root))
         (process-kit-local-source (merge-pathnames #P"../cl-process-kit/" project-root)))
    (flet ((registered-source (env-source local-source)
             (or (and env-source
                      (plusp (length env-source))
                      (probe-file env-source))
                 (probe-file local-source)))
           (load-local-asd (source asd-name)
             (when source
               (load (merge-pathnames asd-name (truename source))))))
      (load-local-asd (registered-source weave-env-source weave-local-source)
                      #P"cl-weave.asd")
      (load-local-asd (registered-source prolog-env-source prolog-local-source)
                      #P"cl-prolog.asd")
      ;; cl-process-kit depends on cl-boundary-kit/cl-log-kit, so those two
      ;; must be registered with ASDF before cl-process-kit.asd loads.
      (load-local-asd (registered-source boundary-kit-env-source boundary-kit-local-source)
                      #P"cl-boundary-kit.asd")
      (load-local-asd (registered-source log-kit-env-source log-kit-local-source)
                      #P"cl-log-kit.asd")
      (load-local-asd (registered-source process-kit-env-source process-kit-local-source)
                      #P"cl-process-kit.asd"))
    (load (merge-pathnames #P"cl-cli.asd" project-root))
    (funcall load-system "cl-cli/tests")))
