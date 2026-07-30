(in-package :cl-cli/test)

(describe-sequential "help"
  (it "includes option metadata"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "profile"
                                   :kind :value
                                   :description "Runtime profile."
                                   :multiple-p t
                                   :default "dev"
                                   :env-var "APP_PROFILE"
                                   :choices '("dev" "prod")
                                   :required-p t)))))
      (with-app-help-text (text app)
        (assert-searches text "Runtime profile. (repeatable; required; default: dev; env: APP_PROFILE; choices: dev | prod)"))))

  (it "includes option relationship metadata"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "profile"
                                   :kind :value)
                      (make-option :name "config"
                                   :kind :value
                                   :description "Config file."
                                   :requires '(:profile)
                                   :conflicts-with '("token"))
                      (make-option :name "token"
                                   :kind :value)))))
      (with-app-help-text (text app)
        (assert-searches text "Config file. (requires: --profile; conflicts: --token)"))))

  (it "includes requires-any-of metadata"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "token" :kind :value)
                      (make-option :name "username" :kind :value)
                      (make-option :name "login" :kind :flag
                                  :description "Sign in."
                                  :requires-any-of '(:token :username))))))
      (with-app-help-text (text app)
        (assert-searches text "Sign in. (requires one of: --token, --username)"))))

  (it "hides hidden option relationship targets"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "profile"
                                   :kind :value)
                      (make-option :name "internal-token"
                                   :kind :value
                                   :hidden-p t)
                      (make-option :name "internal-secret"
                                   :kind :value
                                   :hidden-p t)
                      (make-option :name "config"
                                   :kind :value
                                   :description "Config file."
                                   :requires '(:profile :internal-token)
                                   :conflicts-with '("internal-secret"))))))
      (with-app-help-text (text app)
        (assert-searches text "Config file. (requires: --profile)")
        (assert-not-searches text "internal-token" "conflicts:"))))

  (it "renders negated boolean option names"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "threads"
                                   :kind :boolean)))))
      (with-app-help-text (text app)
        (assert-searches text "--threads, --no-threads"))))

  (it "surfaces command aliases and option aliases"
    (let* ((command (make-command :name "compile"
                                  :aliases '("build" "c")
                                  :description "Compile sources."))
           (app (make-app
                 :name "demo"
                 :global-options
                 (list (make-option :name "verbose"
                                    :aliases '("chatty")
                                    :kind :flag))
                 :commands (list command))))
      (with-app-help-text (text app)
        (assert-searches text "compile (build, c)" "--verbose, --chatty"))))

  (it "help command respects run-app stdout"
    (let* ((help-command (make-help-command))
           (app (demo-app
                 :summary "Demo app."
                 :commands (list help-command)))
           (exit-code nil)
           (text (with-string-output (stdout)
                   (setf exit-code (run-app app :argv '("demo" "help") :stdout stdout)))))
      (expect (zerop exit-code))
      (assert-searches text "Usage: demo <command> [args]")))

  (it "command usage errors preserve command context"
    (let* ((command (make-command
                     :name "run"
                     :options (list (make-option :name "config"
                                                 :kind :value
                                                 :required-p t))))
           (app (demo-app
                 :commands (list command))))
      (caught-signal= (cli-missing-option-value condition)
          (parse-argv app '("demo" "run"))
        (:eq cli-usage-error-app app)
        (:eq cli-usage-error-command command))))

  (it "run-app prints command help for command usage errors"
    (let* ((command (make-command
                     :name "run"
                     :options (list (make-option :name "config"
                                                 :kind :value
                                                 :required-p t))))
           (app (demo-app :commands (list command)))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app
                                            :argv '("demo" "run")
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (= exit-code 64))
      (assert-searches text "Missing required option" "Usage: demo run [options]")))

  (it "run-app parses aliases without warnings"
    (let* ((app (make-app
                 :name "demo"
                 :global-options
                 (list (make-option :name "verbose"
                                    :aliases '("chatty")
                                    :kind :flag))))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app
                                            :argv '("demo" "--chatty")
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (zerop exit-code))
      (expect (string= text ""))))

  (it "run-app returns 70 for unhandled handler errors"
    (let* ((app (demo-app
                 :handler (lambda (invocation)
                            (declare (ignore invocation))
                            (error "boom"))))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app
                                            :argv '("demo")
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (= exit-code 70))
      (assert-searches text "Internal error: boom")))

  (it "run-app strips terminal controls from usage errors"
    (let* ((arg (format nil "~C[31mboom" #\Escape))
           (app (demo-app))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app
                                            :argv (list "demo" arg)
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (= exit-code 64))
      (assert-searches text "[31mboom")
      (expect (null (position #\Escape text)))))

  (it "app help strips terminal controls from root usage names"
    (let* ((escape (string #\Escape))
           (app (cl-cli::%make-app-spec :name (format nil "demo~A[2J" escape)
                                        :summary "Demo app."))
           (text (with-string-output (stream)
                   (print-app-help app stream))))
      (assert-searches text "Usage: demo[2J")
      (expect (null (position #\Escape text)))))

  (it "run-app strips terminal controls from internal error diagnostics"
    (let* ((app (demo-app
                 :handler (lambda (invocation)
                            (declare (ignore invocation))
                            (error (format nil "bad~C[31mred~C[0m~%next"
                                           #\Escape #\Escape)))))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app
                                            :argv '("demo")
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (= exit-code 70))
      (assert-searches text "Internal error: bad[31mred[0m next")
      (expect (null (position #\Escape text)))))

  (it "run-app strips terminal controls from version output"
    (let* ((version (format nil "1.0~C[31mred~%next" #\Escape))
           (app (demo-app :version version))
           (stderr (make-string-output-stream))
           (exit-code nil)
           (stdout
             (with-output-to-string (stream)
               (setf exit-code
                     (run-app app
                              :argv '("demo" "--version")
                              :stdout stream
                              :stderr stderr)))))
      (expect (= exit-code 0))
      (expect (string= stdout (format nil "demo 1.0[31mred next~%")))
      (expect (string= (get-output-stream-string stderr) ""))
      (expect (null (position #\Escape stdout)))))

  (it "app help hides version when app version is missing"
    (let ((app (demo-app)))
      (with-app-help-text (text app)
        (assert-searches text "Global Options:" "-h, --help")
        (assert-not-searches text "-V, --version"))))

  (it "app help hides version for whitespace version string"
    (let ((app (demo-app :version "   ")))
      (with-app-help-text (text app)
        (assert-not-searches text "-V, --version"))))

  (it "app help shows command aliases"
    (let* ((command (make-command :name "compile"
                                  :aliases '("build" "c")
                                  :description "Compile sources."))
           (app (demo-app
                 :version "1.0.0"
                 :commands (list command))))
      (with-app-help-text (text app)
        (assert-searches text "compile (build, c)" "-V, --version"))))

  (it "app help groups commands by category"
    (let* ((compile (make-command :name "compile"
                                  :group "Build"
                                  :description "Compile sources."))
           (test (make-command :name "test"
                               :group "Build"
                               :description "Run tests."))
           (doctor (make-command :name "doctor"
                                 :group "Diagnostics"
                                 :aliases '("diag")
                                 :description "Inspect the environment."))
           (help (make-command :name "help"
                               :description "Show help."))
           (app (demo-app
                 :commands (list compile test doctor help))))
      (with-app-help-text (text app)
        (assert-searches text "Commands:" "Build:" "Diagnostics:" "compile" "doctor (diag)")
        (assert-search-order text "  help" "Build:" "Diagnostics:"))))

  (it "app help renders examples section"
    (let ((app (demo-app
                :examples '("demo compile src/main.lisp"
                            "demo test --filter smoke"))))
      (with-app-help-text (text app)
        (assert-searches text "Examples:" "  demo compile src/main.lisp" "  demo test --filter smoke"))))

  (it "command help renders examples section"
    (let* ((command (make-command
                     :name "run"
                     :examples '("demo run target.lisp"
                                 "demo run target.lisp --verbose")))
           (app (demo-app
                 :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Examples:" "  demo run target.lisp" "  demo run target.lisp --verbose"))))

  (it "accepts app help keyword options without an explicit stream"
    (let* ((app (demo-app :summary "Summary."))
           (stream (make-string-output-stream)))
      (let ((*standard-output* stream))
        (print-app-help app :width 40))
      (let ((text (get-output-stream-string stream)))
        (assert-searches text
                         "Usage: demo"
                         "Summary."))))

  (it "accepts command help keyword options without an explicit stream"
    (let* ((command (make-command :name "run" :description "Run target."))
           (app (demo-app :commands (list command)))
           (stream (make-string-output-stream)))
      (let ((*standard-output* stream))
        (print-command-help app command :width 40))
      (let ((text (get-output-stream-string stream)))
        (assert-searches text
                         "Usage: demo run"
                         "Run target."))))

  (it "strips terminal control characters from free-form help text"
    (let* ((escape (string #\Escape))
           (app (demo-app
                 :summary (format nil "safe~A[2Jtext" escape)
                 :global-options (list (make-option
                                        :name "message"
                                        :description (format nil "hello~A[Hworld" escape)))
                 :examples (list (format nil "demo run~A[31m" escape))))
           (text (with-string-output (stream)
                   (print-app-help app stream))))
      (assert-searches text
                       "safe[2Jtext"
                       "hello[Hworld"
                       "demo run[31m")
      (expect (null (position #\Escape text)))))

  (it "command help usage includes options token"
    (let* ((command (make-command
                     :name "run"
                     :options (list (make-option :name "config"
                                                 :kind :value))
                     :positionals (list (make-positional :key :target :required-p t))))
           (app (demo-app
                 :global-options (list (make-option :name "verbose" :short #\v))
                 :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Usage: demo run [options] TARGET"))))

  (it "help command construction"
    (let* ((help-command (make-help-command))
           (app (demo-app :commands (list help-command)))
           (inv (parse-argv app '("demo" "help"))))
      (expect (string= (command-name (invocation-command inv)) "help"))))

  (it "help <command> prints that command's own help"
    (let* ((help-command (make-help-command))
           (run-command (make-command :name "run" :description "Run target."))
           (app (demo-app :commands (list help-command run-command)))
           (exit-code nil)
           (text (with-string-output (stdout)
                   (setf exit-code (run-app app :argv '("demo" "help" "run")
                                            :stdout stdout)))))
      (expect (zerop exit-code))
      (assert-searches text "Run target.")))

  (it "help <unknown-command> reports an unknown-command usage error"
    (let* ((help-command (make-help-command))
           (app (demo-app :commands (list help-command)))
           (exit-code nil)
           (text (with-string-output (stderr)
                   (setf exit-code (run-app app :argv '("demo" "help" "nope")
                                            :stderr stderr
                                            :stdout (make-string-output-stream))))))
      (expect (= exit-code 64))
      (assert-searches text "Unknown command: nope")))

  (it "command-by-name resolves primary names and aliases"
    (let* ((build (make-command :name "build"
                                :aliases '("compile" "C")))
           (doctor (make-command :name "doctor"
                                 :hidden-p t))
           (app (demo-app
                 :commands (list build doctor))))
      (expect (eq (command-by-name app "build") build))
      (expect (eq (command-by-name app "COMPILE") build))
      (expect (eq (command-by-name app "c") build))
      (expect (eq (command-by-name app "doctor") doctor))
      (expect (null (command-by-name app "release")))))

  (it "renders exclusive groups as a choice instead of pairwise conflicts"
    (let ((app (make-app
                :name "fmt"
                :global-options (required-exclusive-group
                                 (make-option :name "json" :kind :flag)
                                 (make-option :name "yaml" :kind :flag)
                                 (make-option :name "table" :kind :flag)))))
      (with-app-help-text (text app)
        (assert-searches text "exactly one of: --json | --yaml | --table")
        (assert-not-searches text "conflicts:"))))

  (it "renders a non-required exclusive group with an at-most-one choice"
    (let ((app (make-app
                :name "fmt"
                :global-options (exclusive-group
                                 (make-option :name "json" :kind :flag)
                                 (make-option :name "yaml" :kind :flag)))))
      (with-app-help-text (text app)
        (assert-searches text "at most one of: --json | --yaml")
        (assert-not-searches text "conflicts:"))))

  (it "renders the app-level description and help footer"
    (let ((app (make-app
                :name "demo"
                :description "A longer description of demo."
                :help-footer "Report bugs at the tracker.")))
      (with-app-help-text (text app)
        (assert-searches text "A longer description of demo.")
        (assert-searches text "Report bugs at the tracker."))))

  (it "renders a fixed multi-value option's value placeholders"
    (let ((app (make-app
                :name "demo"
                :global-options
                (list (make-option :name "tag"
                                   :kind :value
                                   :value-count 2
                                   :description "Two tags.")))))
      (with-app-help-text (text app)
        (assert-searches text "--tag <TAG> <TAG>"))))
  (it "renders a typed positional's type metadata"
    (let ((app (make-app
                :name "demo"
                :positionals
                (list (make-positional :key :port
                                       :type :integer
                                       :description "Port to bind.")))))
      (with-app-help-text (text app)
        (assert-searches text "type: integer")))))
