(in-package :cl-cli/tests)

;;;; Output assertions for the PowerShell renderer.
;;;;
;;;; PowerShell is the most capable of the three flat completers: it keeps a
;;;; per-command option map and narrows to it once a top-level subcommand is on
;;;; the line. It does not do per-option value completion, so the only place a
;;;; user-supplied value reaches a quoted literal is the root positional pool --
;;;; which is where the escaping case below aims.

(defun completion-powershell-hidden-command-options-fixture ()
  "An app whose hidden command carries options of its own."
  (make-completion-fixture
   :commands (list (make-command :name "visible"
                                 :options (list (make-option :name "shown"
                                                             :kind :flag)))
                   (make-command :name "secret"
                                 :hidden-p t
                                 :options (list (make-option :name "secret-flag"
                                                             :kind :flag))))))

(describe-sequential "completion powershell"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "powershell")
        "Register-ArgumentCompleter -Native -CommandName 'demo'"
        ;; A command and each of its aliases are equally valid first words, so
        ;; both are first-word candidates.
        "$commands = @('compile', 'build')"
        ;; Asserting the whole array pins the pool exactly: the built-in
        ;; --help/--version join the declared globals, and nothing else does.
        "$globalOptions = @('--verbose', '-v', '-h', '--help', '-V', '--version')"
        ;; A command's own options are kept out of the global pool and offered
        ;; only once that command is selected.
        "'compile' = @('--output', '-o')")))

  (it "hides version when app version is missing"
    ;; Offering --version for an app that does not accept it completes the user
    ;; straight into a parse error.
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :short #\v
                                                   :kind :flag)))))
      (assert-completion-searches (app "powershell")
        "$globalOptions = @('--verbose', '-v', '-h', '--help')")
      (assert-completion-not-searches (app "powershell")
        "--version" "'-V'")))

  (it "includes command and option aliases"
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :aliases '("chatty")
                                                   :kind :flag))
                :command-aliases '("build" "c")
                :command-options (list (make-option :name "output"
                                                    :short #\o
                                                    :aliases '("out")
                                                    :kind :value)))))
      (assert-completion-searches (app "powershell")
        "$commands = @('compile', 'build', 'c')"
        "'--verbose', '--chatty'"
        ;; Every alias keys the same option array, so narrowing by an alias
        ;; offers exactly what narrowing by the canonical name offers.
        "'compile' = @('--output', '-o', '--out')"
        "'build' = @('--output', '-o', '--out')"
        "'c' = @('--output', '-o', '--out')")))

  (it "includes negated boolean options"
    ;; A :boolean option accepts --no-NAME as well, so completing only the
    ;; positive form hides half the option.
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "powershell")
        "'compile' = @('--threads', '--no-threads')")))

  (it "hides hidden commands and options"
    (let ((app (completion-hidden-commands-and-options-fixture)))
      (assert-completion-searches (app "powershell") "'visible'" "'--visible-flag'")
      (assert-completion-not-searches (app "powershell") "secret")))

  (it "keeps a hidden command's options out of the command option map"
    ;; Hiding a command must hide its whole option scope: a --secret-flag entry
    ;; would otherwise name the hidden command as its map key.
    (let ((app (completion-powershell-hidden-command-options-fixture)))
      (assert-completion-searches (app "powershell") "'visible' = @('--shown')")
      (assert-completion-not-searches (app "powershell") "secret")))

  (it "keeps global options available after a subcommand narrows the pool"
    ;; Global options stay legal after a subcommand is chosen, so the narrowed
    ;; branch must union them back in rather than replace the pool outright.
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "powershell")
        "if ($selected) { $candidates = $globalOptions + $commandOptions[$selected] }")))

  (it "offers root positional choices"
    ;; :choices on a root positional are a closed value set, so they belong in
    ;; the first-word candidate pool alongside subcommand names.
    (let ((app (demo-app
                :positionals (list (make-positional :key :env
                                                    :choices '("dev" "prod"))))))
      (assert-completion-searches (app "powershell")
        "$positionals = @('dev', 'prod')")))

  (it "lets completion candidates override choices"
    ;; :completion-candidates is the explicit completion-time override of
    ;; :choices; offering both would suggest values the parser rejects.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :env
                                    :choices '("dev" "prod")
                                    :completion-candidates '("staging"))))))
      (assert-completion-searches (app "powershell") "$positionals = @('staging')")
      (assert-completion-not-searches (app "powershell") "'dev'" "'prod'")))

  (it "escapes quotes and backslashes in candidate values"
    ;; PowerShell single-quoted literals escape an embedded quote by doubling
    ;; it, and treat " and \ as ordinary characters. Anything else -- notably
    ;; the POSIX close-escape-reopen form -- would terminate the string early
    ;; and leave the sourced script syntactically broken.
    (let ((app (demo-app
                :positionals (list (make-positional
                                    :key :target
                                    :completion-candidates
                                    (list "a'b" "c\"d" "e\\f"))))))
      (assert-completion-searches (app "powershell")
        "$positionals = @('a''b', 'c\"d', 'e\\f')")
      (assert-completion-not-searches (app "powershell")
        ;; The POSIX escape would close the literal after `a`.
        "'a'\"'\"'b'"
        ;; A backslash escape is not a PowerShell mechanism; emitting one would
        ;; put a literal backslash in front of the quote and still break out.
        "'a\\'b'"))))
