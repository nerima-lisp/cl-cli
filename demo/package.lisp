;;;; demo/package.lisp
;;;;
;;;; cl-cli-demo: the executable cl-cli dogfoods itself with. Every construct
;;;; the README advertises -- global options, a nested subcommand group with an
;;;; alias and a default subcommand, the standard help/version/completion/docs
;;;; commands, and RUN-APP's exit code -- is exercised by a binary a user can
;;;; actually run, so a regression in dispatch or rendering shows up as a
;;;; broken command rather than only as a failing assertion.
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
