(in-package :cl-cli/tests)

(describe-sequential "completion zsh"
  (it "completes nested subcommands with accumulated option scope"
    (let* ((app (demo-app
                 :global-options (list (make-option :name "verbose" :kind :flag))
                 :commands (list (make-command
                                  :name "remote"
                                  :options (list (make-option :name "porcelain" :kind :flag))
                                  :subcommands (list (make-command :name "add")
                                                     (make-command :name "remove"))))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       "case \"${words[3]}\" in"
                       "_describe 'commands' subcommand_specs"
                       ;; the add clause carries the accumulated option scope
                       "--verbose"
                       "--porcelain")))

  (it "omits the :: optional-argument marker in zsh when consume-optional-value-p is false"
    (let* ((app (demo-app
                 :global-options (list (optional-value-option "coverage"))))
           (text (render-completion app "zsh")))
      (expect (search "--coverage[" text))
      (expect (not (search "::value:" text)))))

  (it "adds the :: optional-argument marker in zsh when consume-optional-value-p is true"
    (let* ((app (demo-app
                 :global-options (list (optional-value-option "coverage"
                                                               :consume-optional-value-p t))))
           (text (render-completion app "zsh")))
      (expect (search "--coverage[" text))
      (expect (search "]::value:" text))))

  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "zsh")
        "#compdef demo"
        "_demo_completion() {"
        "_describe 'commands' command_specs"
        "option_specs=("
        "command_option_specs=("
        "--verbose"
        "-v"
        "--output"
        "-o"
        "'compile:Compile sources.'"
        "'build:alias for compile'")))

  (it "includes choice values"
    (let ((app (completion-choice-values-fixture)))
      (assert-completion-searches (app "zsh")
        "case \"$previous_word\" in"
        "case \"$current_word\" in"
        "'--profile')"
        "'--profile=*')"
        "compadd -Q -S '' -- 'dev' 'prod'")))

  (it "excludes a hidden option's own value case from the zsh value cases"
    (let* ((app (demo-app
                 :global-options (list (make-option :name "profile" :kind :value
                                                    :choices '("dev" "prod"))
                                       (make-option :name "internal-token" :kind :value
                                                    :hidden-p t
                                                    :choices '("a" "b")))))
           (text (render-completion app "zsh")))
      (assert-searches text "'--profile')" "'dev'" "'prod'")
      (assert-not-searches text "'--internal-token')" "'a'" "'b'")))

  (it "renders candidate descriptions"
    (let ((app (completion-candidate-descriptions-fixture)))
      (assert-completion-searches (app "zsh")
        "_describe 'values' value_candidates"
        "'dev:Local development'"
        "'prod:Production release'")))

  (it "escapes a colon inside a candidate value so _describe cannot truncate it"
    ;; _describe splits each entry at the first unescaped colon. The value half
    ;; is the text inserted on the user's command line, so unlike the
    ;; description half it cannot be sanitised by mapping the colon to a space
    ;; -- it has to survive intact. Unescaped, `host:8080' completed as `host'
    ;; with `8080:...' folded into the description: a silently wrong insertion,
    ;; and host:port is exactly the shape a candidate list carries.
    (let ((app (demo-app
                :global-options (list (make-option :name "host" :kind :value
                                                   :completion-candidates
                                                   '(("plain" . "a plain host")
                                                     ("host:8080" . "with a port")))))))
      (assert-searches (render-completion app "zsh")
        "'host\\:8080:with a port'"
        "'plain:a plain host'")))

  (it "escapes a backslash inside a candidate value before the colon it protects"
    ;; A value ending in a backslash would otherwise consume the escape added
    ;; for the separator, putting the split back where it started.
    (let ((app (demo-app
                :global-options (list (make-option :name "path" :kind :value
                                                   :completion-candidates
                                                   '(("a\\" . "trailing backslash")
                                                     ("c\\:d" . "backslash then colon")))))))
      (assert-searches (render-completion app "zsh")
        "'a\\\\:trailing backslash'"
        "'c\\\\\\:d:backslash then colon'")))

  (it "quotes shell-sensitive descriptions and candidates"
    (let ((app (make-completion-fixture
                :command-description "Don't $(run)"
                :command-options (list (make-option :name "profile"
                                                    :kind :value
                                                    :completion-candidates
                                                    '(("dev's" . "Bob's $(danger)")))))))
      (assert-completion-searches (app "zsh")
        (cl-cli::%completion-shell-quote "compile:Don't $(run)")
        (cl-cli::%completion-shell-quote "dev's:Bob's $(danger)"))
      (assert-completion-not-searches (app "zsh")
        "compile:Don't $(run)"
        "dev's:Bob's $(danger)")))

  (it "normalizes zsh candidate descriptions"
    (let* ((escape (string #\Escape))
           (description (format nil "Bob:close]run~A[31m" escape))
           (app (make-completion-fixture
                 :command-options (list (make-option :name "profile"
                                                     :kind :value
                                                     :completion-candidates
                                                     `(("dev" . ,description)))))))
      (assert-completion-searches (app "zsh")
        (cl-cli::%completion-shell-quote
         (format nil "dev:~A"
                 (cl-cli::%completion-zsh-describe-field description))))
      (assert-completion-not-searches (app "zsh")
        "dev:Bob:close]run"
        escape)))

  (it "normalizes zsh command description records"
    (let* ((escape (string #\Escape))
           (app (make-app
                 :name "demo"
                 :commands (list (make-command
                                  :name "compile"
                                  :aliases '("build")
                                  :description (format nil "group:one~A[31m" escape)))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       (cl-cli::%completion-shell-quote "compile:group one[31m")
                       (cl-cli::%completion-shell-quote "build:alias for compile"))
      (assert-not-searches text
                           "compile:group:one"
                           escape)))

  (it "normalizes zsh option spec fields"
    (let* ((escape (string #\Escape))
           (description (format nil "close]group:one~A[31m" escape))
           (placeholder "VAL:UE]NAME")
           (app (make-app
                 :name "demo"
                 :global-options (list (make-option :name "profile"
                                                     :kind :value
                                                     :description description
                                                     :value-name placeholder))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       (cl-cli::%completion-shell-quote
                        (format nil "--profile[~A]:~A:"
                                (cl-cli::%completion-zsh-arguments-field
                                 description)
                                (cl-cli::%completion-zsh-arguments-field
                                 placeholder))))
      (assert-not-searches text
                           "close]group:one"
                           "VAL:UE]NAME"
                           escape)))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "zsh")
        "--threads"
        "--no-threads"))))
