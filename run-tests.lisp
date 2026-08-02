;;; Command-line entry point:
;;;   sbcl --script run-tests.lisp
;;;   ecl --shell run-tests.lisp
;;;
;;; This script LOADS AND RUNS the suite, and exits with its verdict. That is
;;; what PACKAGE_STANDARD.md means by a universal test entry point, and what
;;; lets flake.nix's `checks.default`, `checks.ecl` and `apps.test` all invoke
;;; the same file a contributor invokes by hand.
;;;
;;; It used to only load, leaving the running to an
;;; `--eval '(cl-cli/test:run-tests)'` that every caller had to remember to
;;; append -- so a caller that forgot got a green run meaning nothing more than
;;; "the tests compiled". The older two-step invocations still work unchanged,
;;; because the exit below happens during `--load` and the trailing `--eval`
;;; is simply never reached.

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
         (find-system (or (find-symbol "FIND-SYSTEM" asdf-package)
                          (error "ASDF does not provide FIND-SYSTEM.")))
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
         (codec-kit-env-source (funcall getenv "CL_CODEC_KIT_SOURCE_DIR"))
         (process-kit-env-source (funcall getenv "CL_PROCESS_KIT_SOURCE_DIR"))
         (json-kit-env-source (funcall getenv "CL_JSON_KIT_SOURCE_DIR"))
         (weave-local-source (merge-pathnames #P"../cl-weave/" project-root))
         (prolog-local-source (merge-pathnames #P"../cl-prolog/" project-root))
         (boundary-kit-local-source (merge-pathnames #P"../cl-boundary-kit/" project-root))
         (log-kit-local-source (merge-pathnames #P"../cl-log-kit/" project-root))
         (codec-kit-local-source (merge-pathnames #P"../cl-codec-kit/" project-root))
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
      ;; cl-process-kit depends on cl-boundary-kit/cl-log-kit/cl-codec-kit, so
      ;; those three must be registered with ASDF before cl-process-kit.asd
      ;; loads. All four are needed only by the shell-verification half of
      ;; the suite -- see the split rationale in cl-cli.asd.
      (load-local-asd (registered-source boundary-kit-env-source
                                         boundary-kit-local-source)
                      #P"cl-boundary-kit.asd")
      (load-local-asd (registered-source log-kit-env-source
                                         log-kit-local-source)
                      #P"cl-log-kit.asd")
      (load-local-asd (registered-source codec-kit-env-source
                                         codec-kit-local-source)
                      #P"cl-codec-kit.asd")
      (load-local-asd (registered-source process-kit-env-source
                                         process-kit-local-source)
                      #P"cl-process-kit.asd")
      ;; Two independent conditions, and neither is "did the LOAD-LOCAL-ASD
      ;; calls above find anything".
      ;;
      ;; SB-THREAD, because cl-log-kit calls it unconditionally and so compiles
      ;; only where that package exists; a host that merely happens to have the
      ;; checkouts sitting next to cl-cli must not be talked into trying.
      ;; Tracked upstream at
      ;; https://github.com/nerima-lisp/cl-log-kit/issues/1; once that is
      ;; fixed, drop the FIND-PACKAGE test and every implementation runs the
      ;; whole suite.
      ;;
      ;; FIND-SYSTEM, because a sibling directory is only one of the ways these
      ;; systems arrive. Under Nix, cl-nix-forge builds each one and resolves
      ;; the closure onto CL_SOURCE_REGISTRY, so there is no CL_*_SOURCE_DIR
      ;; and no ../cl-process-kit/ to find -- and asking the old question there
      ;; answered "no" and silently ran the core suite under a check whose name
      ;; promised the full one. Asking ASDF whether it can resolve the system
      ;; is the question that was always meant, and it is true on both paths.
      (setf shell-verification-p
            (and (find-package "SB-THREAD")
                 (funcall find-system "cl-boundary-kit" nil)
                 (funcall find-system "cl-log-kit" nil)
                 (funcall find-system "cl-codec-kit" nil)
                 (funcall find-system "cl-process-kit" nil)
                 t)))
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

;;; `cl-cli/test:run-tests` signals on any failing suite, so the handler is
;;; what turns that into an exit code instead of a backtrace whose meaning
;;; depends on which implementation's `--script` flag was used.
;;;
;;; Symbols are resolved at run time rather than read time for the same reason
;;; the form above does it: the CL-CLI/TEST package does not exist while this
;;; file is being read.
(eval-when (:load-toplevel :execute)
  (let* ((uiop-package (or (find-package :uiop)
                           (error "UIOP package is unavailable.")))
         (quit (or (find-symbol "QUIT" uiop-package)
                   (error "UIOP does not provide QUIT.")))
         (test-package (or (find-package "CL-CLI/TEST")
                           (error "Loading the test system did not define CL-CLI/TEST.")))
         (run-tests (or (find-symbol "RUN-TESTS" test-package)
                        (error "CL-CLI/TEST does not provide RUN-TESTS."))))
    (handler-case (funcall run-tests)
      (error (condition)
        (format *error-output* "~&; cl-cli tests: FAILED -- ~A~%" condition)
        (finish-output *error-output*)
        (finish-output *standard-output*)
        (funcall quit 1)))
    (finish-output *error-output*)
    (finish-output *standard-output*)
    (funcall quit 0)))
