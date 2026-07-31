;;;; This form comes FIRST, before anything else. ASDF binds *package* to
;;;; ASDF-USER only for a file it loads itself; read any other way — a REPL
;;;; `load`, an editor evaluating the buffer, flake.nix parsing :version — the
;;;; file is read in whatever package happens to be current, and the
;;;; unqualified forms below would land in the wrong package.

(in-package #:asdf-user)

(defparameter +cl-cli-repository-url+
  "https://github.com/nerima-lisp/cl-cli")

(defparameter +cl-cli-issues-url+
  "https://github.com/nerima-lisp/cl-cli/issues")

(defparameter +cl-cli-readme+
  (when *load-pathname*
    (uiop:read-file-string (merge-pathnames #P"README.md" *load-pathname*))))

(asdf:defsystem "cl-cli"
  :description "Composable Common Lisp CLI parsing and dispatch primitives."
  :long-description +cl-cli-readme+
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.1.0"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :depends-on ("uiop")
  :serial t
  ;; Component names carry their own directory rather than using :pathname,
  ;; because the test system below has to reach one file in examples/ that a
  ;; system-wide :pathname "t" would put out of reach.
  :components ((:file "src/package")
               (:file "src/conditions")
               (:file "src/core")
               (:file "src/model-helpers")
               (:file "src/model-value-typing")
               (:file "src/model-structs")
               (:file "src/model-lookup")
               (:file "src/option-relations")
               (:file "src/model-option")
               (:file "src/model-positional")
               (:file "src/model-command")
               (:file "src/model-validation")
               (:file "src/model-app")
               (:file "src/model-dsl")
               (:file "src/util")
               (:file "src/terminal")
               (:file "src/parser-lookup")
               (:file "src/parser-relation-validation")
               (:file "src/parser-option-consumption")
               (:file "src/parser-consumption")
               (:file "src/parser-values")
               (:file "src/parser-value-storage")
               (:file "src/parser-core")
               (:file "src/parser-dispatch")
               (:file "src/help-style")
               (:file "src/help-metadata")
               (:file "src/help-renderers")
               (:file "src/help-printers")
               (:file "src/help-commands")
               (:file "src/runtime")
               (:file "src/completion-helpers")
               (:file "src/completion-renderer-helpers")
               (:file "src/completion-renderers-bash")
               (:file "src/completion-renderers-zsh")
               (:file "src/completion-renderers-fish")
               (:file "src/completion-renderers-powershell")
               (:file "src/completion-renderers-nushell")
               (:file "src/completion-renderers-elvish")
               (:file "src/doc-helpers")
               (:file "src/doc-renderers-manpage")
               (:file "src/doc-renderers-markdown")
               (:file "src/doc-renderers-json")
               (:file "src/doc-commands")
               (:file "src/completion-dynamic")
               (:file "src/completion-commands"))
  :in-order-to ((asdf:test-op (asdf:test-op "cl-cli/test"))))

;;; The test suite is split in two so that the portable half stays loadable on
;;; every implementation. `cl-cli/test' is the core suite; its dependencies
;;; are all portable Common Lisp. `cl-cli/test/shell-verification' adds the
;;; checks that shell out to bash/zsh/fish/mandoc, and only that half needs
;;; `cl-process-kit' (whose transitive `cl-log-kit' dependency is SBCL-only --
;;; https://github.com/nerima-lisp/cl-log-kit/issues/1). Keeping the split at
;;; the system boundary means a non-SBCL implementation runs the core suite for
;;; real instead of failing to compile the whole thing.
(asdf:defsystem "cl-cli/test"
  :description "Core test system for cl-cli."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.1.0"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :depends-on ("cl-cli" "cl-weave" "cl-prolog/weave" "cl-json-kit")
  :serial t
  :components ((:file "t/package")
               (:file "t/helpers-fixtures")
               (:file "examples/consumer-migrations")
               (:file "t/helpers-support")
               (:file "t/package-test")
               (:file "t/parser-dispatch-test")
               (:file "t/parser-dispatch-property-test")
               (:file "t/model-helpers-mutation-test")
               (:file "t/parser-dispatch-fuzz-test")
               (:file "t/parser-dispatch-benchmark-test")
               (:file "t/model-dsl-test")
               (:file "t/parser-option-consumption-test")
               (:file "t/model-value-typing-test")
               (:file "t/parser-value-storage-count-test")
               (:file "t/parser-value-storage-delimited-test")
               (:file "t/parser-values-config-test")
               (:file "t/parser-values-source-test")
               (:file "t/model-helpers-deprecated-test")
               (:file "t/parser-values-positional-choices-test")
               (:file "t/parser-lookup-abbreviation-test")
               (:file "t/parser-dispatch-subcommands-test")
               (:file "t/help-printers-option-groups-test")
               (:file "t/util-response-files-test")
               (:file "t/parser-core-positional-arity-test")
               (:file "t/parser-core-default-command-test")
               (:file "t/help-style-color-test")
               (:file "t/terminal-test")
               (:file "t/help-style-wrap-test")
               (:file "t/util-auto-help-test")
               (:file "t/core-negative-numbers-test")
               (:file "t/parser-value-storage-key-value-test")
               (:file "t/parser-option-consumption-multi-value-test")
               (:file "t/parser-option-consumption-variadic-test")
               (:file "t/parser-relation-validation-inclusive-group-test")
               (:file "t/core-suggestions-test")
               (:file "t/parser-dispatch-require-command-test")
               (:file "t/parser-relation-validation-conditional-test")
               (:file "t/model-validation-test")
               (:file "t/parser-values-validation-test")
               (:file "t/parser-value-storage-boolean-test")
               (:file "t/option-relations-test")
               (:file "t/help-printers-test")
               (:file "t/help-printers-command-footer-test")
               (:file "t/help-renderers-usage-synopsis-test")
               (:file "t/runtime-exit-codes-test")
               (:file "t/completion-renderers-bash-test")
               (:file "t/completion-renderers-zsh-test")
               (:file "t/completion-renderers-fish-test")
               (:file "t/completion-renderers-powershell-test")
               (:file "t/completion-renderers-nushell-test")
               (:file "t/completion-renderers-elvish-test")
               (:file "t/completion-commands-test")
               (:file "t/completion-helpers-positional-test")
               (:file "t/completion-helpers-value-hints-test")
               (:file "t/completion-dynamic-test")
               (:file "t/completion-dynamic-flat-shells-test")
               (:file "t/completion-commands-builtin-args-test")
               (:file "t/doc-renderers-manpage-test")
               (:file "t/doc-renderers-manpage-metadata-test")
               (:file "t/doc-renderers-markdown-test")
               (:file "t/doc-renderers-json-test")
               (:file "t/doc-commands-test")
               (:file "t/consumer-migrations-test"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/test :run-tests)))

(asdf:defsystem "cl-cli/test/shell-verification"
  :description
  "Tests that run cl-cli's generated scripts through the real shells and mandoc."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.1.0"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :depends-on ("cl-cli/test" "cl-process-kit")
  :serial t
  :components ((:file "t/completion-commands-shell-verification-test"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/test :run-tests)))
