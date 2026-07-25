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
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :license "MIT"
  :version "1.0.1"
  :depends-on ("uiop")
  :in-order-to ((asdf:test-op (asdf:test-op "cl-cli/test")))
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
               (:file "src/completion-commands")))

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
  :version "1.0.1"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :depends-on ("cl-cli" "cl-weave" "cl-prolog/weave" "cl-json-kit")
  :serial t
  :components ((:file "t/package")
               (:file "t/test-fixtures")
               (:file "examples/consumer-migrations")
               (:file "t/test-support")
               (:file "t/cases-public-api")
               (:file "t/cases-parse")
               (:file "t/cases-property-parse")
               (:file "t/cases-mutation-testing")
               (:file "t/cases-parser-fuzz")
               (:file "t/cases-parser-benchmark")
               (:file "t/cases-define-dsl")
               (:file "t/cases-options")
               (:file "t/cases-typed-values")
               (:file "t/cases-count")
               (:file "t/cases-delimited-values")
               (:file "t/cases-config")
               (:file "t/cases-value-source")
               (:file "t/cases-deprecated")
               (:file "t/cases-positional-choices")
               (:file "t/cases-abbreviated-options")
               (:file "t/cases-nested-subcommands")
               (:file "t/cases-option-groups")
               (:file "t/cases-response-files")
               (:file "t/cases-positional-arity")
               (:file "t/cases-nested-default")
               (:file "t/cases-colored-help")
               (:file "t/cases-terminal-detection")
               (:file "t/cases-help-wrap")
               (:file "t/cases-auto-help")
               (:file "t/cases-negative-numbers")
               (:file "t/cases-key-value")
               (:file "t/cases-multi-value")
               (:file "t/cases-variadic-options")
               (:file "t/cases-inclusive-group")
               (:file "t/cases-choice-suggestions")
               (:file "t/cases-require-command")
               (:file "t/cases-conditional-requirements")
               (:file "t/cases-validation-specification")
               (:file "t/cases-validation-values")
               (:file "t/cases-validation-boolean")
               (:file "t/cases-validation-relations")
               (:file "t/cases-help")
               (:file "t/cases-usage-synopsis")
               (:file "t/cases-exit-codes")
               (:file "t/cases-completion-bash")
               (:file "t/cases-completion-zsh")
               (:file "t/cases-completion-fish")
               (:file "t/cases-completion-powershell")
               (:file "t/cases-completion-nushell")
               (:file "t/cases-completion-elvish")
               (:file "t/cases-completion-commands")
               (:file "t/cases-positional-completion")
               (:file "t/cases-value-hints")
               (:file "t/cases-dynamic-completion")
               (:file "t/cases-flat-dynamic-completion")
               (:file "t/cases-builtin-arg-completion")
               (:file "t/cases-doc-manpage")
               (:file "t/cases-manpage-metadata")
               (:file "t/cases-doc-markdown")
               (:file "t/cases-doc-json")
               (:file "t/cases-doc-commands")
               (:file "t/cases-consumer-migrations"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/test :run-tests)))

(asdf:defsystem "cl-cli/test/shell-verification"
  :description
  "Tests that run cl-cli's generated scripts through the real shells and mandoc."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :depends-on ("cl-cli/test" "cl-process-kit")
  :serial t
  :components ((:file "t/cases-shell-verification"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/test :run-tests)))
