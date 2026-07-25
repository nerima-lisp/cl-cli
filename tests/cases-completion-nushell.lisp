(in-package :cl-cli/tests)

;;;; Output assertions for the Nushell renderer.
;;;;
;;;; Nushell gets an `export extern` signature (global flags only) plus one
;;;; `nu-complete <app> command` def for the leading token. It does not narrow
;;;; to a subcommand's options, so nothing here asserts a per-command scope.

(describe-sequential "completion nushell"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "nushell")
        "def \"nu-complete demo command\" []"
        ;; A command and each alias are equally valid leading tokens.
        "[\"compile\", \"build\"]"
        "export extern \"demo\" ["
        "  --verbose(-v)"
        "  --version(-V)")))

  (it "hides version when app version is missing"
    ;; An extern that advertises --version for an app without one completes the
    ;; user into a parse error.
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :short #\v
                                                   :kind :flag)))))
      (assert-completion-searches (app "nushell") "  --help(-h)")
      (assert-completion-not-searches (app "nushell") "--version")))

  (it "includes command aliases in the leading-token completer"
    (let ((app (make-completion-fixture :command-aliases '("build" "c"))))
      (assert-completion-searches (app "nushell")
        "[\"compile\", \"build\", \"c\"]")))

  (it "hides hidden commands and options"
    (let ((app (completion-hidden-commands-and-options-fixture)))
      (assert-completion-searches (app "nushell") "\"visible\"" "--visible-flag")
      (assert-completion-not-searches (app "nushell") "secret")))

  (it "types value-bearing flags and leaves valueless flags untyped"
    ;; Nushell uses the `: string` annotation to decide whether a flag consumes
    ;; the following token. Typing a plain flag would make it swallow the next
    ;; argument; leaving a value flag untyped would strand its value.
    (let ((app (demo-app
                :global-options (list (make-option :name "verbose" :kind :flag)
                                      (make-option :name "mode" :kind :value)
                                      (optional-value-option "coverage")))))
      (assert-completion-searches (app "nushell")
        "  --mode: string"
        "  --coverage: string")
      (assert-completion-not-searches (app "nushell") "--verbose: string")))

  (it "renders descriptions as trailing comments"
    ;; The description is emitted as a `#` comment, so quotes and backslashes
    ;; need no escaping there -- only a line break could break the extern out
    ;; of its comment, and control characters are already folded to spaces.
    (let ((app (demo-app
                :global-options (list (make-option :name "path"
                                                   :kind :value
                                                   :description "Bob's \"C:\\tmp\"")))))
      (assert-completion-searches (app "nushell")
        "  --path: string  # Bob's \"C:\\tmp\"")))

  (it "offers root positional choices alongside subcommands"
    ;; Nushell has one completer for the leading token, so a root positional's
    ;; closed value set shares the pool with subcommand names.
    (let ((app (demo-app
                :commands (list (make-command :name "compile"))
                :positionals (list (make-positional :key :env
                                                    :choices '("dev" "prod"))))))
      (assert-completion-searches (app "nushell")
        "[\"compile\", \"dev\", \"prod\"]")))

  (it "lets completion candidates override choices"
    ;; :completion-candidates is the completion-time override of :choices;
    ;; offering both would suggest values the parser rejects.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :env
                                    :choices '("dev" "prod")
                                    :completion-candidates '("staging"))))))
      (assert-completion-searches (app "nushell") "[\"staging\"]")
      (assert-completion-not-searches (app "nushell") "\"dev\"" "\"prod\"")))

  (it "escapes quotes and backslashes in candidate values"
    ;; Nushell double-quoted literals backslash-escape " and \. An unescaped
    ;; quote ends the string and breaks the module; an unescaped backslash is
    ;; worse than a syntax error -- "e\f" silently reads back as a form feed.
    ;; A single quote needs no escape inside a double-quoted literal.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :target
                                    :completion-candidates
                                    (list "a'b" "c\"d" "e\\f"))))))
      (assert-completion-searches (app "nushell")
        "[\"a'b\", \"c\\\"d\", \"e\\\\f\"]")
      (assert-completion-not-searches (app "nushell")
        "\"c\"d\""
        "\"e\\f\"")))

  (it "references the leading-token completer only when it is defined"
    ;; `command?: string@"nu-complete demo command"` is a parse error when the
    ;; named def is absent, and it takes the whole module down with it -- so the
    ;; reference and the definition must appear together or not at all.
    (let ((with-commands (make-completion-fixture))
          (without-commands (demo-app)))
      (assert-completion-searches (with-commands "nushell")
        "def \"nu-complete demo command\" []"
        "  command?: string@\"nu-complete demo command\"")
      (assert-completion-not-searches (without-commands "nushell")
        "nu-complete demo command"))))
