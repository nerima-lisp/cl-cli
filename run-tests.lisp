;;; Command-line entry point:
;;;   sbcl --non-interactive --load run-tests.lisp --eval '(cl-cli/test:run-tests)' --quit
;;;   ecl --norc --load run-tests.lisp --eval '(cl-cli/test:run-tests)'

(eval-when (:load-toplevel :execute)
  (require :asdf))

(eval-when (:load-toplevel :execute)
  (let* ((asdf-package (or (find-package :asdf)
                           (error "ASDF package is unavailable.")))
         (uiop-package (or (find-package :uiop)
                           (error "UIOP package is unavailable.")))
         (load-system (or (find-symbol "LOAD-SYSTEM" asdf-package)
                          (error "ASDF does not provide LOAD-SYSTEM.")))
         (load-asd (or (find-symbol "LOAD-ASD" asdf-package)
                       (error "ASDF does not provide LOAD-ASD.")))
         (getenv (or (find-symbol "GETENV" uiop-package)
                     (error "UIOP does not provide GETENV.")))
         (directory-pathname (or (find-symbol "PATHNAME-DIRECTORY-PATHNAME" uiop-package)
                                 (error "UIOP does not provide PATHNAME-DIRECTORY-PATHNAME.")))
         (test-file (or *load-truename* *compile-file-truename*))
         ;; This script sits at the repository root (PACKAGE_STANDARD.md fixes
         ;; the test entry point there), so its own directory IS the root.
         (project-root (funcall directory-pathname test-file))
         (weave-env-source (funcall getenv "CL_WEAVE_SOURCE_DIR"))
         (prolog-env-source (funcall getenv "CL_PROLOG_SOURCE_DIR"))
         (boundary-kit-env-source (funcall getenv "CL_BOUNDARY_KIT_SOURCE_DIR"))
         (log-kit-env-source (funcall getenv "CL_LOG_KIT_SOURCE_DIR"))
         (process-kit-env-source (funcall getenv "CL_PROCESS_KIT_SOURCE_DIR"))
         (json-kit-env-source (funcall getenv "CL_JSON_KIT_SOURCE_DIR"))
         (weave-local-source (merge-pathnames #P"../cl-weave/" project-root))
         (prolog-local-source (merge-pathnames #P"../cl-prolog/" project-root))
         (boundary-kit-local-source (merge-pathnames #P"../cl-boundary-kit/" project-root))
         (log-kit-local-source (merge-pathnames #P"../cl-log-kit/" project-root))
         (process-kit-local-source (merge-pathnames #P"../cl-process-kit/" project-root))
         (json-kit-local-source (merge-pathnames #P"../cl-json-kit/" project-root))
         (shell-verification-p nil))
    (flet ((registered-source (env-source local-source)
             (or (and env-source
                      (plusp (length env-source))
                      (probe-file env-source))
                 (probe-file local-source)))
           (load-local-asd (source asd-name)
             (when source
               (funcall load-asd (merge-pathnames asd-name (truename source)))
               t)))
      (load-local-asd (registered-source weave-env-source weave-local-source)
                      #P"cl-weave.asd")
      (load-local-asd (registered-source prolog-env-source prolog-local-source)
                      #P"cl-prolog.asd")
      (load-local-asd (registered-source json-kit-env-source json-kit-local-source)
                      #P"cl-json-kit.asd")
      ;; cl-process-kit depends on cl-boundary-kit/cl-log-kit, so those two
      ;; must be registered with ASDF before cl-process-kit.asd loads. All
      ;; three are needed only by the shell-verification half of the suite --
      ;; see the split rationale in cl-cli.asd.
      ;;
      ;; The guard is a capability check, not a "did we find the sources"
      ;; check: cl-log-kit calls SB-THREAD unconditionally, so it compiles
      ;; only where that package exists, and a host that merely happens to
      ;; have the checkouts sitting next to cl-cli must not be talked into
      ;; trying. Tracked upstream at
      ;; https://github.com/nerima-lisp/cl-log-kit/issues/1; once that is
      ;; fixed, drop the FIND-PACKAGE test and every implementation runs the
      ;; whole suite.
      (setf shell-verification-p
            (when (find-package "SB-THREAD")
              (and (load-local-asd (registered-source boundary-kit-env-source
                                                      boundary-kit-local-source)
                                   #P"cl-boundary-kit.asd")
                   (load-local-asd (registered-source log-kit-env-source
                                                      log-kit-local-source)
                                   #P"cl-log-kit.asd")
                   (load-local-asd (registered-source process-kit-env-source
                                                      process-kit-local-source)
                                   #P"cl-process-kit.asd")))))
    (load (merge-pathnames #P"cl-cli.asd" project-root))
    ;; Say which half is running, every time. A suite that quietly shrinks
    ;; when a dependency goes missing reads exactly like a suite that passed.
    (format *error-output*
            "~&; cl-cli tests: running the ~:[core suite only (shell-~
             verification cases excluded: cl-process-kit unavailable on ~A)~;~
             full suite including shell verification~].~%"
            shell-verification-p (lisp-implementation-type))
    (funcall load-system (if shell-verification-p
                             "cl-cli/test/shell-verification"
                             "cl-cli/test"))))
