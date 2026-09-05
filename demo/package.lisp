;;;; demo/package.lisp
;;;;
;;;; The executable demo exercises the public parsing, dispatch, rendering,
;;;; and exit-code paths end to end.
;;;;
;;;; `:use #:cl` and nothing else; the library's own symbols arrive through
;;;; :IMPORT-FROM, per CODING_STANDARD.md.
(defpackage #:cl-cli/demo
  (:use #:cl)
  (:import-from #:cl-cli
                #:make-app
                #:make-command
                #:make-option
                #:make-positional
                #:make-standard-commands
                #:run-app
                #:application-argv
                #:option-value
                #:option-value-source
                #:positional-value
                #:command-name
                #:invocation-command-path
                #:invocation-stdout
                #:invocation-stderr)
  (:export #:demo-app
           #:main))
