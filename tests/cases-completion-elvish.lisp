(in-package :cl-cli/tests)

;;;; Output assertions for the Elvish renderer.
;;;;
;;;; Elvish gets a single arg-completer that puts one flat candidate pool --
;;;; subcommand names, global option tokens, root positional values -- and lets
;;;; Elvish narrow by prefix. There is no per-command scope and no per-option
;;;; value completion, so nothing here asserts either.

(describe-sequential "completion elvish"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "elvish")
        "set edit:completion:arg-completer['demo'] = {|@words|"
        ;; A command and each alias are equally valid words.
        "var commands = ['compile' 'build']"
        ;; Asserting the whole list pins the pool exactly: the built-in
        ;; --help/--version join the declared globals, and nothing else does.
        "var options = ['--verbose' '-v' '-h' '--help' '-V' '--version']")))

  (it "hides version when app version is missing"
    ;; Completing --version for an app that does not accept it walks the user
    ;; straight into a parse error.
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :short #\v
                                                   :kind :flag)))))
      (assert-completion-searches (app "elvish")
        "var options = ['--verbose' '-v' '-h' '--help']")
      (assert-completion-not-searches (app "elvish") "--version" "'-V'")))

  (it "includes command and option aliases"
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :aliases '("chatty")
                                                   :kind :flag))
                :command-aliases '("build" "c"))))
      (assert-completion-searches (app "elvish")
        "var commands = ['compile' 'build' 'c']"
        "'--verbose' '--chatty'")))

  (it "includes negated boolean options"
    ;; A :boolean option accepts --no-NAME as well, so completing only the
    ;; positive form hides half the option. Elvish pools every option token, so
    ;; a command-scoped boolean lands in the same list as the globals.
    (let ((app (demo-app
                :global-options (list (make-option :name "threads"
                                                   :kind :boolean)))))
      (assert-completion-searches (app "elvish") "'--threads' '--no-threads'")))

  (it "hides hidden commands and options"
    (let ((app (completion-hidden-commands-and-options-fixture)))
      (assert-completion-searches (app "elvish") "'visible'" "'--visible-flag'")
      (assert-completion-not-searches (app "elvish") "secret")))

  (it "offers root positional choices"
    ;; :choices on a root positional are a closed value set and belong in the
    ;; candidate pool alongside subcommand names.
    (let ((app (demo-app
                :positionals (list (make-positional :key :env
                                                    :choices '("dev" "prod"))))))
      (assert-completion-searches (app "elvish")
        "var positionals = ['dev' 'prod']"
        "put $@positionals")))

  (it "lets completion candidates override choices"
    ;; :completion-candidates is the completion-time override of :choices;
    ;; offering both would suggest values the parser rejects.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :env
                                    :choices '("dev" "prod")
                                    :completion-candidates '("staging"))))))
      (assert-completion-searches (app "elvish") "var positionals = ['staging']")
      (assert-completion-not-searches (app "elvish") "'dev'" "'prod'")))

  (it "declares a candidate list only when it also puts it"
    ;; `put $@commands` without a matching `var commands` is an Elvish
    ;; *compilation* error ("variable $commands not found"), which kills the
    ;; whole completer -- so an empty category must drop both lines, not just
    ;; the assignment.
    (let ((app (demo-app
                :global-options (list (make-option :name "verbose" :kind :flag)))))
      (assert-completion-searches (app "elvish") "var options = " "put $@options")
      (assert-completion-not-searches (app "elvish")
        "put $@commands"
        "var commands = "
        "put $@positionals"
        "var positionals = ")))

  (it "escapes quotes in candidate values"
    ;; Elvish single-quoted literals escape an embedded quote by doubling it,
    ;; and treat " and \ as ordinary characters -- Elvish has no backslash
    ;; escapes inside single quotes at all. The POSIX close-escape-reopen form
    ;; would terminate the literal early and leave the script unparseable.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :target
                                    :completion-candidates
                                    (list "a'b" "c\"d" "e\\f"))))))
      (assert-completion-searches (app "elvish")
        "var positionals = ['a''b' 'c\"d' 'e\\f']")
      (assert-completion-not-searches (app "elvish")
        "'a'\"'\"'b'"
        "'a\\'b'"))))
