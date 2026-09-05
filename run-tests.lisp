;;; Universal test entry point:
;;;   sbcl --script run-tests.lisp
;;;   ecl --shell run-tests.lisp
;;;
(eval-when (:load-toplevel :execute)
  (require :asdf))

(eval-when (:load-toplevel :execute)
  (let* ((asdf-package (or (find-package :asdf)
                           (error "ASDF package is unavailable.")))
         (uiop-package (or (find-package :uiop)
                           (error "UIOP package is unavailable.")))
         (clear-source-registry
           (or (find-symbol "CLEAR-SOURCE-REGISTRY" asdf-package)
               (error "ASDF does not provide CLEAR-SOURCE-REGISTRY.")))
         (initialize-source-registry
           (or (find-symbol "INITIALIZE-SOURCE-REGISTRY" asdf-package)
               (error "ASDF does not provide INITIALIZE-SOURCE-REGISTRY.")))
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
         (dependency-parent
           (if (search "/.worktrees/" (namestring project-root))
               (merge-pathnames #P"../../../" project-root)
               (merge-pathnames #P"../" project-root)))
         (dependency-specs
           (list (list :env "CL_WEAVE_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-weave/" dependency-parent)
                       :asd #P"cl-weave.asd")
                 (list :env "CL_HOST_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-host-kit/" dependency-parent)
                       :asd #P"cl-host-kit.asd")
                 (list :env "CL_PROLOG_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-prolog-kit/" dependency-parent)
                       :asd #P"cl-prolog-kit.asd")
                 (list :env "CL_JSON_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-json-kit/" dependency-parent)
                       :asd #P"cl-json-kit.asd")
                 ;; Keep shell-verification dependencies in load order:
                 ;; cl-process-kit depends on cl-boundary-kit/cl-log-kit/
                 ;; cl-codec-kit, and cl-log-kit depends on cl-date-kit and
                 ;; cl-concurrent-kit.
                 (list :env "CL_BOUNDARY_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-boundary-kit/" dependency-parent)
                       :asd #P"cl-boundary-kit.asd"
                       :shell-system "cl-boundary-kit")
                 (list :env "CL_DATE_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-date-kit/" dependency-parent)
                       :asd #P"cl-date-kit.asd"
                       :shell-system "cl-date-kit")
                 (list :env "CL_CONCURRENT_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-concurrent-kit/" dependency-parent)
                       :asd #P"cl-concurrent-kit.asd"
                       :shell-system "cl-concurrent-kit")
                 (list :env "CL_LOG_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-log-kit/" dependency-parent)
                       :asd #P"cl-log-kit.asd"
                       :shell-system "cl-log-kit")
                 (list :env "CL_CODEC_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-codec-kit/" dependency-parent)
                       :asd #P"cl-codec-kit.asd"
                       :shell-system "cl-codec-kit")
                 (list :env "CL_PROCESS_KIT_SOURCE_DIR"
                       :local (merge-pathnames #P"cl-process-kit/" dependency-parent)
                       :asd #P"cl-process-kit.asd"
                       :shell-system "cl-process-kit")))
         (shell-verification-p nil)
         (shell-verification-reason nil))
    (flet ((registered-source (spec)
             (let ((env-source (funcall getenv (getf spec :env)))
                   (local-source (getf spec :local)))
               (or (and env-source
                   (plusp (length env-source))
                   (probe-file env-source))
                   (probe-file local-source))))
           (load-local-asd (source asd-name)
             (when source
               (funcall load-asd (merge-pathnames asd-name (truename source)))
               t))
           (shell-system-available-p (spec)
             (let ((system-name (getf spec :shell-system)))
               (or (null system-name)
                   (funcall find-system system-name nil))))
           (missing-shell-systems ()
             (loop for spec in dependency-specs
                   for system-name = (getf spec :shell-system)
                   unless (or (null system-name)
                              (funcall find-system system-name nil))
                     collect system-name into missing
                   finally (return missing))))
      ;; Prefer the current checkout unconditionally, then keep inherited
      ;; registry entries so Nix-provided dependencies remain visible.
      (funcall clear-source-registry)
      (funcall initialize-source-registry
               `(:source-registry
                 (:tree ,project-root)
                 :inherit-configuration))
      (dolist (spec dependency-specs)
        (load-local-asd (registered-source spec)
                        (getf spec :asd)))
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
      ;; and no ../cl-process-kit/ to find. Asking ASDF whether it can resolve
      ;; the system is the right question on both paths.
      (let ((sb-thread-package (find-package "SB-THREAD"))
            (missing-systems (missing-shell-systems)))
        (setf shell-verification-p
              (and sb-thread-package
                   (null missing-systems)
                   t)
              shell-verification-reason
              (cond
                ((null sb-thread-package)
                 (format nil "SB-THREAD unavailable on ~A"
                         (lisp-implementation-type)))
                (missing-systems
                 (format nil "missing ASDF systems: ~{~A~^, ~}"
                         missing-systems))
                (t
                 nil)))))
    (load (merge-pathnames #P"cl-cli.asd" project-root))
    ;; Say which half is running, every time. A suite that quietly shrinks
    ;; when a dependency goes missing reads exactly like a suite that passed.
    (format *error-output*
            "~&; cl-cli tests: running the ~:[core suite only (shell-~
             verification cases excluded: ~A)~;~
             full suite including shell verification~].~%"
            shell-verification-p shell-verification-reason)
    (funcall load-system (if shell-verification-p
                             "cl-cli/test/shell-verification"
                             "cl-cli/test"))))

;;; Resolve the test package after loading the system, then map failures to a
;;; portable exit code.
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
