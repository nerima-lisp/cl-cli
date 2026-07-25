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
  :author "takeokunn"
  :maintainer "takeokunn"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :license "MIT"
  :version "1.0.0"
  :depends-on ("uiop")
  :in-order-to ((asdf:test-op (asdf:test-op "cl-cli/tests")))
  :serial t
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
;;; every implementation. `cl-cli/tests' is the core suite; its dependencies
;;; are all portable Common Lisp. `cl-cli/tests/shell-verification' adds the
;;; checks that shell out to bash/zsh/fish/mandoc, and only that half needs
;;; `cl-process-kit' (whose transitive `cl-log-kit' dependency is SBCL-only --
;;; https://github.com/nerima-lisp/cl-log-kit/issues/1). Keeping the split at
;;; the system boundary means a non-SBCL implementation runs the core suite for
;;; real instead of failing to compile the whole thing.
(asdf:defsystem "cl-cli/tests"
  :description "Core test system for cl-cli."
  :author "takeokunn"
  :license "MIT"
  :version "1.0.0"
  :depends-on ("cl-cli" "cl-weave" "cl-prolog/weave" "cl-json-kit")
  :serial t
  :components ((:file "tests/package")
               (:file "tests/test-fixtures")
               (:file "examples/consumer-migrations")
               (:file "tests/test-support")
               (:file "tests/cases-public-api")
               (:file "tests/cases-parse")
               (:file "tests/cases-property-parse")
               (:file "tests/cases-mutation-testing")
               (:file "tests/cases-parser-fuzz")
               (:file "tests/cases-parser-benchmark")
               (:file "tests/cases-define-dsl")
               (:file "tests/cases-options")
               (:file "tests/cases-typed-values")
               (:file "tests/cases-count")
               (:file "tests/cases-delimited-values")
               (:file "tests/cases-config")
               (:file "tests/cases-value-source")
               (:file "tests/cases-deprecated")
               (:file "tests/cases-positional-choices")
               (:file "tests/cases-abbreviated-options")
               (:file "tests/cases-nested-subcommands")
               (:file "tests/cases-option-groups")
               (:file "tests/cases-response-files")
               (:file "tests/cases-positional-arity")
               (:file "tests/cases-nested-default")
               (:file "tests/cases-colored-help")
               (:file "tests/cases-terminal-detection")
               (:file "tests/cases-help-wrap")
               (:file "tests/cases-auto-help")
               (:file "tests/cases-negative-numbers")
               (:file "tests/cases-key-value")
               (:file "tests/cases-multi-value")
               (:file "tests/cases-variadic-options")
               (:file "tests/cases-inclusive-group")
               (:file "tests/cases-choice-suggestions")
               (:file "tests/cases-require-command")
               (:file "tests/cases-conditional-requirements")
               (:file "tests/cases-validation-specification")
               (:file "tests/cases-validation-values")
               (:file "tests/cases-validation-boolean")
               (:file "tests/cases-validation-relations")
               (:file "tests/cases-help")
               (:file "tests/cases-usage-synopsis")
               (:file "tests/cases-exit-codes")
               (:file "tests/cases-completion-bash")
               (:file "tests/cases-completion-zsh")
               (:file "tests/cases-completion-fish")
               (:file "tests/cases-completion-powershell")
               (:file "tests/cases-completion-nushell")
               (:file "tests/cases-completion-elvish")
               (:file "tests/cases-completion-commands")
               (:file "tests/cases-positional-completion")
               (:file "tests/cases-value-hints")
               (:file "tests/cases-dynamic-completion")
               (:file "tests/cases-flat-dynamic-completion")
               (:file "tests/cases-builtin-arg-completion")
               (:file "tests/cases-doc-manpage")
               (:file "tests/cases-manpage-metadata")
               (:file "tests/cases-doc-markdown")
               (:file "tests/cases-doc-json")
               (:file "tests/cases-doc-commands")
               (:file "tests/cases-consumer-migrations"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/tests :run-tests)))

(asdf:defsystem "cl-cli/tests/shell-verification"
  :description
  "Tests that run cl-cli's generated scripts through the real shells and mandoc."
  :author "takeokunn"
  :license "MIT"
  :version "1.0.0"
  :depends-on ("cl-cli/tests" "cl-process-kit")
  :serial t
  :components ((:file "tests/cases-shell-verification"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/tests :run-tests)))
