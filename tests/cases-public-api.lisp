(in-package :cl-cli/tests)

;;;; The exported symbols of :CL-CLI are the SemVer contract (see
;;;; docs/src/compatibility.md). This file pins that set, in both directions.
;;;;
;;;; It exists because `:export` fails silently in the direction that matters:
;;;; a misspelled name interns a fresh, dead symbol rather than signaling, so
;;;; a typo ships an export nobody can use and removes the one that was meant.
;;;; Nothing else in the suite would notice -- every other test calls these
;;;; symbols from a package that :USEs CL-CLI, which resolves them whether
;;;; they are external or not.
;;;;
;;;; Adding to +PUBLIC-API+ is a deliberate act, and should be: post-1.0 an
;;;; addition is a minor release and a removal is a major one. If this test
;;;; fails, the question is never "how do I update the list" but "did I mean
;;;; to change the contract".

(defparameter +public-api+
  '(
   :+json-schema-version+
   :app-allow-abbreviated-options
   :app-allow-negative-numbers
   :app-authors
   :app-auto-help
   :app-commands
   :app-default-command
   :app-description
   :app-examples
   :app-expand-response-files
   :app-global-options
   :app-handler
   :app-help-footer
   :app-manual-date
   :app-name
   :app-positionals
   :app-require-command
   :app-see-also
   :app-summary
   :app-version
   :application-argv
   :built-in-option-specs
   :cli-conflicting-options
   :cli-conflicting-options-left-option
   :cli-conflicting-options-right-option
   :cli-error
   :cli-error-app
   :cli-error-command
   :cli-error-message
   :cli-invalid-option-value
   :cli-invalid-option-value-cause
   :cli-invalid-option-value-name
   :cli-invalid-option-value-value
   :cli-invalid-positional-value
   :cli-invalid-positional-value-cause
   :cli-invalid-positional-value-name
   :cli-invalid-positional-value-value
   :cli-invalid-specification
   :cli-missing-any-of-options
   :cli-missing-any-of-options-alternatives
   :cli-missing-any-of-options-name
   :cli-missing-dependent-option
   :cli-missing-dependent-option-dependency
   :cli-missing-dependent-option-name
   :cli-missing-option-value
   :cli-missing-option-value-name
   :cli-missing-positional
   :cli-missing-positional-name
   :cli-missing-required-option
   :cli-response-file-error
   :cli-response-file-error-path
   :cli-unexpected-argument
   :cli-unexpected-argument-name
   :cli-unknown-command
   :cli-unknown-command-name
   :cli-unknown-option
   :cli-unknown-option-name
   :cli-usage-error
   :cli-usage-error-app
   :cli-usage-error-command
   :command-aliases
   :command-by-name
   :command-default-command
   :command-deprecated
   :command-description
   :command-examples
   :command-group
   :command-handler
   :command-help-footer
   :command-hidden-p
   :command-name
   :command-options
   :command-positionals
   :command-subcommands
   :current-process-argv
   :default-runtime-markers
   :define-app
   :define-command
   :exclusive-group
   :extract-application-argv
   :inclusive-group
   :invocation-action
   :invocation-app
   :invocation-argv0
   :invocation-command
   :invocation-command-options
   :invocation-command-path
   :invocation-global-options
   :invocation-option-sources
   :invocation-positionals
   :invocation-raw-argv
   :invocation-stderr
   :invocation-stdout
   :make-app
   :make-command
   :make-complete-command
   :make-completion-command
   :make-docs-command
   :make-help-command
   :make-option
   :make-positional
   :make-standard-commands
   :make-version-command
   :option-choices
   :option-complete
   :option-completion-candidates
   :option-conflicts-with
   :option-consume-optional-value-p
   :option-default
   :option-deprecated
   :option-description
   :option-env-vars
   :option-group
   :option-group-members
   :option-group-mode
   :option-group-required-p
   :option-help-group
   :option-hidden-p
   :option-key
   :option-kind
   :option-multiple-p
   :option-names
   :option-negated-names
   :option-parser
   :option-required-if
   :option-required-p
   :option-required-unless
   :option-requires
   :option-requires-any-of
   :option-stop-parsing-p
   :option-value
   :option-value-count
   :option-value-delimiter
   :option-value-hint
   :option-value-max
   :option-value-min
   :option-value-name
   :option-value-source
   :option-value-type
   :parse-argv
   :positional-choices
   :positional-complete
   :positional-completion-candidates
   :positional-default
   :positional-default-present-p
   :positional-description
   :positional-key
   :positional-max-count
   :positional-min-count
   :positional-parser
   :positional-required-p
   :positional-rest-p
   :positional-value
   :positional-value-hint
   :positional-value-max
   :positional-value-min
   :positional-value-type
   :print-app-help
   :print-command-help
   :render-bash-completion
   :render-complete-reply
   :render-completion
   :render-docs
   :render-elvish-completion
   :render-fish-completion
   :render-json
   :render-manpage
   :render-markdown
   :render-nushell-completion
   :render-powershell-completion
   :render-zsh-completion
   :required-exclusive-group
   :run-app
   :strip-argv-separators
    )
  "Every symbol :CL-CLI exports, as of v1.0.0.")

(describe-sequential "public API surface"
  (it "exports exactly the documented set, and nothing more"
    (let ((actual (let (names)
                    (do-external-symbols (symbol :cl-cli)
                      (push (intern (symbol-name symbol) :keyword) names))
                    names))
          (expected +public-api+))
      ;; Reported as two directed differences rather than one set comparison,
      ;; so a failure says which way the contract moved: a missing symbol is a
      ;; breaking removal, an unexpected one is a surface addition that should
      ;; have been a conscious decision.
      (expect (null (set-difference expected actual)))
      (expect (null (set-difference actual expected)))))

  (it "backs every exported symbol with an actual definition"
    ;; The silent-typo case: (:export :postional-key) interns POSTIONAL-KEY,
    ;; which is external, bound to nothing, and indistinguishable from a real
    ;; export until a user calls it.
    (dolist (name +public-api+)
      (let ((symbol (find-symbol (symbol-name name) :cl-cli)))
        (expect (not (null symbol)))
        (expect (or (fboundp symbol)
                    (boundp symbol)
                    (find-class symbol nil)
                    (not (null (macro-function symbol))))))))

  (it "keeps every condition class reachable from CLI-ERROR"
    ;; A condition a user cannot catch with one blanket handler is a condition
    ;; they will miss. CLI-INVALID-SPECIFICATION is deliberately NOT under
    ;; CLI-USAGE-ERROR -- a spec bug must not be answered with a usage message
    ;; -- so CLI-ERROR is the root that has to cover everything.
    (dolist (name +public-api+)
      (let ((symbol (find-symbol (symbol-name name) :cl-cli)))
        (when (and symbol
                   (find-class symbol nil)
                   (subtypep symbol 'condition))
          (expect (subtypep symbol 'cli-error))))))

  (it "keeps specification errors out of the usage-error branch"
    ;; Pins the split itself, not just its reachability: the idiomatic handler
    ;; catches CLI-USAGE-ERROR and prints usage, and a programmer's malformed
    ;; spec must not be swallowed by it.
    (expect (subtypep 'cli-invalid-specification 'cli-error))
    (expect (not (subtypep 'cli-invalid-specification 'cli-usage-error)))
    (expect (subtypep 'cli-usage-error 'cli-error))
    ;; The narrowing subtypes stay catchable by their parents, so a handler
    ;; that does not care about the distinction is unaffected.
    (expect (subtypep 'cli-missing-required-option 'cli-missing-option-value))
    (expect (subtypep 'cli-response-file-error 'cli-usage-error))))
