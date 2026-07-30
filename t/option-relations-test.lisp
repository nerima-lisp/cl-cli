(in-package :cl-cli/test)

(deftest-queries normalized-requires-relations
    ((make-option-relations-rulebase
      (list (make-option :name "profile"
                         :aliases '("p")
                         :kind :value)
            (make-option :name "config"
                         :kind :value
                         :requires '("p")))))
  ("resolves alias dependencies to canonical keys"
   (requires :config ?dependency)
   :ordered
   (((?dependency . :profile))))
   ("does not attach dependencies to unrelated options"
    (requires :profile ?dependency)
    :fails))

(deftest-queries normalized-requires-relations-character-target
    ((make-option-relations-rulebase
      (list (make-option :name "profile"
                         :aliases '("p")
                         :kind :value)
            (make-option :name "config"
                         :kind :value
                         ;; A short-option alias may also be given as a raw
                         ;; character (#\p), not just a string ("p") --
                         ;; NORMALIZE-OPTION-RELATION-TARGET's ETYPECASE
                         ;; declares CHARACTER as its own branch, distinct
                         ;; from STRING.
                         :requires (list #\p)))))
  ("resolves a character-designated alias dependency to its canonical key"
   (requires :config ?dependency)
   :ordered
   (((?dependency . :profile)))))

(deftest-queries normalized-conflict-relations
    ((make-option-relations-rulebase
      (list (make-option :name "internal-token"
                         :kind :value
                         :hidden-p t)
            (make-option :name "config"
                         :kind :value
                         :conflicts-with '(:internal-token)))))
  ("retains conflicts against hidden targets"
   (conflicts :config ?target)
   :ordered
   (((?target . :internal-token))))
  ("tracks which options are hidden"
   (hidden :internal-token)
   :succeeds))

(describe-sequential "validation relations"
  (it "requires dependent options"
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (demo-app
               :global-options (list (make-option :name "profile"
                                                  :kind :value)
                                     (make-option :name "config"
                                                  :kind :value
                                                  :requires '(:profile))))
              '("demo" "--config" "dev.toml")))
      (:eq cli-missing-dependent-option-name :config)
      (:eq cli-missing-dependent-option-dependency :profile)
      (:searches cli-error-message "Option --config requires --profile.")))

  (it "requires the full transitive closure, not just a direct dependency"
    ;; --deploy requires --build, which itself requires --profile. Supplying
    ;; --deploy and --build but omitting --profile must still fail, naming
    ;; the transitively (not just directly) missing option -- this is what
    ;; OPTION-RELATION-GRAPH's precomputed TRANSITIVE-REQUIRES closure exists
    ;; for; every other requires test in this file is a single hop deep.
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (demo-app
               :global-options (list (make-option :name "profile" :kind :value)
                                     (make-option :name "build" :kind :flag
                                                 :requires '(:profile))
                                     (make-option :name "deploy" :kind :flag
                                                 :requires '(:build))))
              '("demo" "--deploy" "--build")))
      (:eq cli-missing-dependent-option-name :deploy)
      (:eq cli-missing-dependent-option-dependency :profile)
      (:searches cli-error-message "Option --deploy requires --profile.")))

  (it "accepts a fully-satisfied transitive requires chain"
    (with-parsed-argv (inv (demo-app
                            :global-options (list (make-option :name "profile" :kind :value)
                                                  (make-option :name "build" :kind :flag
                                                              :requires '(:profile))
                                                  (make-option :name "deploy" :kind :flag
                                                              :requires '(:build))))
                            '("demo" "--deploy" "--build" "--profile" "prod"))
      (expect (option-value inv :deploy))
      (expect (option-value inv :build))
      (expect (string= (option-value inv :profile) "prod"))))

  (it "requires respect environment defaults"
    (with-parsed-argv-with-environment-variable-reader
        (inv (demo-app
              :global-options (list (make-option :name "profile"
                                                 :kind :value
                                                 :env-var "APP_PROFILE")
                                    (make-option :name "config"
                                                 :kind :value
                                                 :requires '("profile"))))
             '("demo" "--config" "dev.toml")
             (lambda (name)
               (if (string= name "APP_PROFILE")
                   "dev"
                   nil)))
      (expect (string= (option-value inv :profile) "dev"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "requires accepts a --long-flag-spelled relation target"
    (with-parsed-argv (inv (demo-app
                            :global-options (list (make-option :name "profile" :kind :value)
                                                  (make-option :name "config"
                                                              :kind :value
                                                              :requires '("--profile"))))
                          '("demo" "--profile" "prod" "--config" "dev.toml"))
      (expect (string= (option-value inv :profile) "prod"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "requires accepts a -short-flag-spelled relation target"
    (with-parsed-argv (inv (demo-app
                            :global-options (list (make-option :name "profile" :short #\p :kind :value)
                                                  (make-option :name "config"
                                                              :kind :value
                                                              :requires '("-p"))))
                          '("demo" "-p" "prod" "--config" "dev.toml"))
      (expect (string= (option-value inv :profile) "prod"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "requires at least one of the declared requires-any-of alternatives"
    (let ((app (demo-app
                :global-options (list (make-option :name "token" :kind :value)
                                      (make-option :name "username" :kind :value)
                                      (make-option :name "password" :kind :value)
                                      (make-option :name "login" :kind :flag
                                                  :requires-any-of '(:token :username))))))
      (with-parsed-argv (inv app '("demo" "--login" "--token" "abc"))
        (expect (option-value inv :login)))
      (with-parsed-argv (inv app '("demo" "--login" "--username" "bob" "--password" "x"))
        (expect (option-value inv :login)))
      (with-parsed-argv (inv app '("demo"))
        (expect (null (option-value inv :login))))))

  (it "signals when none of the requires-any-of alternatives are present"
    (with-caught-signal-from-argv
        ((cli-missing-any-of-options condition)
         (app (demo-app
               :global-options (list (make-option :name "token" :kind :value)
                                     (make-option :name "username" :kind :value)
                                     (make-option :name "login" :kind :flag
                                                 :requires-any-of '(:token :username))))
              '("demo" "--login")))
      (:eq cli-missing-any-of-options-name :login)
      (:equal cli-missing-any-of-options-alternatives '(:token :username))
      (:searches cli-error-message "Option --login requires one of: --token, --username.")))

  (it "requires-any-of hidden targets without leaking their names"
    (with-caught-signal-from-argv
        ((cli-missing-any-of-options condition)
         (app (demo-app
               :global-options (list (make-option :name "internal-token"
                                                  :kind :value
                                                  :hidden-p t)
                                     (make-option :name "login" :kind :flag
                                                 :requires-any-of '(:internal-token))))
              '("demo" "--login")))
      (:searches cli-error-message "Option --login requires one of: a hidden option.")
      (:not-searches cli-error-message "--internal-token")))

  (it "requires-any-of names a hidden option generically when IT is the one missing an alternative"
    ;; The two tests above hide the TARGET; this hides the erroring option
    ;; itself -- VALIDATE-REQUIRES-ANY-OF's own (if (option-hidden-p spec) ...)
    ;; branch, distinct from the target-hiding one.
    (with-caught-signal-from-argv
        ((cli-missing-any-of-options condition)
         (app (demo-app
               :global-options (list (make-option :name "token" :kind :value)
                                     (make-option :name "username" :kind :value)
                                     (make-option :name "internal-login" :kind :flag
                                                 :hidden-p t
                                                 :requires-any-of '(:token :username))))
              '("demo" "--internal-login")))
      (:searches cli-error-message "A hidden option requires one of: --token, --username.")
      (:not-searches cli-error-message "--internal-login")))

  (it "rejects unknown requires-any-of targets"
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "login" :kind :flag
                                          :requires-any-of '(:token))))))

  (it "rejects requires-any-of self references"
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "login" :kind :flag
                                          :requires-any-of '(:login))))))

  (it "rejects requires-any-of alternatives that all conflict with the option"
    ;; If every alternative conflicts with the option itself, the option can
    ;; never be validly supplied: alone it fails the any-of requirement, and
    ;; together with an alternative it fails the conflict check.
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "b" :kind :flag)
                             (make-option :name "a" :kind :flag
                                         :requires-any-of '(:b)
                                         :conflicts-with '(:b)))))
    (signals-invalid-specification
      (demo-app
       :global-options (exclusive-group
                        (make-option :name "a" :kind :flag
                                    :requires-any-of '(:b))
                        (make-option :name "b" :kind :flag)))))

  (it "requires hidden target without leaking its name"
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (demo-app
               :global-options (list (make-option :name "internal-token"
                                                  :kind :value
                                                  :hidden-p t)
                                     (make-option :name "config"
                                                  :kind :value
                                                  :requires '(:internal-token))))
              '("demo" "--config" "dev.toml")))
      (:eq cli-missing-dependent-option-name :config)
      (:eq cli-missing-dependent-option-dependency :internal-token)
      (:searches cli-error-message "Option --config requires a hidden option.")
      (:not-searches cli-error-message "--internal-token")))

  (it "names a hidden option generically when IT is the one missing a dependency"
    ;; The test above hides the DEPENDENCY; this hides the erroring option
    ;; itself -- VALIDATE-REQUIRES' own (if (option-hidden-p spec) ...) branch,
    ;; distinct from the dependency-hiding one.
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (demo-app
               :global-options (list (make-option :name "profile" :kind :value)
                                     (make-option :name "internal-token"
                                                  :kind :value
                                                  :hidden-p t
                                                  :requires '(:profile))))
              '("demo" "--internal-token" "secret")))
      (:searches cli-error-message "A hidden option requires --profile.")
      (:not-searches cli-error-message "--internal-token")))

  (it "detects conflicting options"
    (with-caught-signal-from-argv
        ((cli-conflicting-options condition)
         (app (demo-app
               :global-options (list (make-option :name "token"
                                                  :kind :value)
                                     (make-option :name "password"
                                                  :kind :value
                                                  :conflicts-with '(:token))))
              '("demo" "--token" "abc" "--password" "secret")))
      (:eq cli-conflicting-options-left-option :password)
      (:eq cli-conflicting-options-right-option :token)
      (:searches cli-error-message "Option --password conflicts with --token.")))

  (it "detects conflicts with hidden target without leaking its name"
    (with-caught-signal-from-argv
        ((cli-conflicting-options condition)
         (app (demo-app
               :global-options (list (make-option :name "internal-token"
                                                  :kind :value
                                                  :hidden-p t)
                                     (make-option :name "config"
                                                  :kind :value
                                                  :conflicts-with '(:internal-token))))
              '("demo" "--config" "dev.toml" "--internal-token" "secret")))
      (:eq cli-conflicting-options-left-option :config)
      (:eq cli-conflicting-options-right-option :internal-token)
      (:searches cli-error-message "Option --config conflicts with a hidden option.")
      (:not-searches cli-error-message "--internal-token")))

  (it "names a hidden option generically when IT is the one flagged in a conflict"
    ;; The test above hides the OTHER side of the conflict; this hides the
    ;; erroring option itself -- VALIDATE-CONFLICTS' own
    ;; (if (option-hidden-p spec) ...) branch, distinct from the other-hiding one.
    (with-caught-signal-from-argv
        ((cli-conflicting-options condition)
         (app (demo-app
               :global-options (list (make-option :name "token" :kind :value)
                                     (make-option :name "internal-quiet"
                                                  :kind :flag
                                                  :hidden-p t
                                                  :conflicts-with '(:token))))
              '("demo" "--token" "abc" "--internal-quiet")))
      (:searches cli-error-message "A hidden option conflicts with --token.")
      (:not-searches cli-error-message "--internal-quiet")))

  (it "rejects unknown relation targets"
    (let* ((config (make-option :name "config"
                                :kind :value
                                :requires '(:profile))))
      (signals-invalid-specification
        (demo-app
         :global-options (list config)))))

  (it "rejects self references"
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "config"
                                          :kind :value
                                          :requires '(:config)))))
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "token"
                                          :kind :value
                                          :conflicts-with '("token"))))))

  (it "rejects a requires closure that contains two conflicting options"
    ;; :a requires both :b and :c, so :a's requires-closure is {:a :b :c}.
    ;; :b and :c conflict with each other -- :a could never be validly
    ;; supplied, since satisfying its own requirements would always also
    ;; satisfy one of :b/:c's mutual conflict.
    (signals-invalid-specification
      (demo-app
       :global-options (list (make-option :name "a" :kind :flag
                                          :requires '(:b :c))
                             (make-option :name "b" :kind :flag
                                         :conflicts-with '(:c))
                             (make-option :name "c" :kind :flag)))))

  (it "keeps each app's cached relation rulebase independent when a command is reused across apps"
    ;; COMMAND-SPEC is documented as a reusable, composable object -- the same
    ;; instance can be spliced into :COMMANDS for more than one MAKE-APP call.
    ;; A relation rulebase cached ON the shared command struct would let a
    ;; later MAKE-APP call silently overwrite the rulebase an earlier,
    ;; already-in-use app depends on.
    (let* ((shared-command (make-command
                            :name "login"
                            :options (list (make-option :name "go" :kind :flag
                                                        :requires '(:token)))))
           (app1 (make-app :name "app1"
                           :global-options (list (make-option :name "token" :kind :value))
                           :commands (list shared-command))))
      (with-parsed-argv (inv app1 '("app1" "login" "--go" "--token" "abc"))
        (expect (option-value inv :go)))
      (make-app :name "app2"
               :global-options (list (make-option :name "token" :kind :value
                                                  :requires '(:extra))
                                     (make-option :name "extra" :kind :value))
               :commands (list shared-command))
      ;; Re-parsing the same, previously-successful app1 invocation must still
      ;; work -- app2's build must not have corrupted app1's cached rulebase.
      (with-parsed-argv (inv app1 '("app1" "login" "--go" "--token" "abc"))
        (expect (option-value inv :go)))))

  (it "resolves alias targets"
    (with-parsed-argv (inv (demo-app
                            :global-options (list (make-option :name "profile"
                                                               :aliases '("p")
                                                               :kind :value)
                                                  (make-option :name "config"
                                                               :kind :value
                                                               :requires '("p"))))
                           '("demo" "--config" "dev.toml" "--p" "dev"))
      (expect (string= (option-value inv :profile) "dev"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "enforces at most one option from an exclusive group"
    (let ((app (make-app :name "fmt"
                         :global-options (exclusive-group
                                          (make-option :name "json" :kind :flag)
                                          (make-option :name "yaml" :kind :flag)
                                          (make-option :name "table" :kind :flag)))))
      (with-parsed-argv (inv app '("fmt" "--json"))
        (expect (option-value inv :json)))
      (with-parsed-argv (inv app '("fmt"))
        (expect (null (option-value inv :json))))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--json" "--yaml")))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--table" "--json")))))

  (it "keeps conflicts declared outside an exclusive group"
    (let ((app (demo-app
                :global-options
                (cons (make-option :name "quiet" :kind :flag
                                   :conflicts-with '(:verbose))
                      (exclusive-group
                       (make-option :name "verbose" :kind :flag)
                       (make-option :name "silent" :kind :flag))))))
      (signals cli-conflicting-options
        (parse-argv app '("demo" "--verbose" "--silent")))
      (signals cli-conflicting-options
        (parse-argv app '("demo" "--quiet" "--verbose")))))

  (it "requires exactly one option from a required exclusive group"
    (let ((app (make-app :name "fmt"
                         :global-options (required-exclusive-group
                                          (make-option :name "json" :kind :flag)
                                          (make-option :name "yaml" :kind :flag)
                                          (make-option :name "table" :kind :flag)))))
      (with-parsed-argv (inv app '("fmt" "--yaml"))
        (expect (option-value inv :yaml)))
      (caught-signal= (cli-missing-option-value condition)
          (parse-argv app '("fmt"))
        (:searches cli-error-message
                   "Exactly one of --json, --yaml, --table is required."))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--json" "--table")))))

  (it "applies exclusive groups declared on command options"
    (let ((app (make-app :name "tool"
                         :commands (list (make-command
                                          :name "export"
                                          :options (required-exclusive-group
                                                    (make-option :name "json" :kind :flag)
                                                    (make-option :name "yaml" :kind :flag)))))))
      (with-parsed-argv (inv app '("tool" "export" "--json"))
        (expect (option-value inv :json)))
      (signals cli-missing-option-value
        (parse-argv app '("tool" "export")))
      (signals cli-conflicting-options
        (parse-argv app '("tool" "export" "--json" "--yaml")))))

  (it "dedups a transitive requires dependency reached via two paths"
    ;; :a requires both :b and :c, and :b/:c both require :d -- :d's
    ;; transitive-requires closure is built once at MAKE-APP time by walking
    ;; every root's dependency tree, and reaching an already-seen dependency
    ;; through a second path (here :d via :c, after already being collected
    ;; via :b) must skip it instead of recollecting or looping.
    (with-parsed-argv (inv (demo-app
                            :global-options
                            (list (make-option :name "d" :kind :flag)
                                 (make-option :name "b" :kind :flag :requires '(:d))
                                 (make-option :name "c" :kind :flag :requires '(:d))
                                 (make-option :name "a" :kind :flag :requires '(:b :c))))
                           '("demo" "--a" "--b" "--c" "--d"))
      (expect (option-value inv :a))
      (expect (option-value inv :b))
      (expect (option-value inv :c))
      (expect (option-value inv :d))))

  (it "rejects a requires cycle"
    ;; OPTION-REQUIREMENT-CYCLE-P / VALIDATE-OPTION-RELATION-GRAPH's cycle
    ;; check had no test anywhere in the suite -- every other :requires test
    ;; in this file is acyclic.
    (caught-signal= (cli-invalid-specification condition)
        (demo-app
         :global-options (list (make-option :name "a" :kind :flag :requires '(:b))
                               (make-option :name "b" :kind :flag :requires '(:a))))
      (:searches cli-error-message "Option requirements must not contain a cycle."))))
