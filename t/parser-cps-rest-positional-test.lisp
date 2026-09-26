(in-package :cl-cli/test)

(defun %rest-search-app (&key (allow-negative-numbers nil) min-count max-count)
  (make-app
   :name "grep"
   :allow-negative-numbers allow-negative-numbers
   :global-options (list (flag-option "verbose" :short #\v))
   :commands
   (list (make-command
          :name "search"
          :options (list (value-option "output" :short #\o)
                         (flag-option "ignore-case" :short #\i))
          :positionals
          (list (make-positional :key :pattern :required-p t)
                (make-positional :key :paths :rest-p t
                                 :min-count min-count
                                 :max-count max-count))))))

(describe-sequential "rest positionals and interspersed options"
  (it "recognizes a separated long value option after a rest positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "--output" "count"))
      (expect (equal (positional-value inv :pattern) "foo"))
      (expect (equal (positional-value inv :paths) '("src")))
      (expect (equal (option-value inv :output) "count"))))

  (it "recognizes an attached long value option after a rest positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "--output=count"))
      (expect (equal (positional-value inv :paths) '("src")))
      (expect (equal (option-value inv :output) "count"))))

  (it "recognizes short options and flags after a rest positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "lib" "-i" "-o" "count"))
      (expect (equal (positional-value inv :paths) '("src" "lib")))
      (expect (eq (option-value inv :ignore-case) t))
      (expect (equal (option-value inv :output) "count"))))

  (it "recognizes a long flag and a short cluster value between rest items"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "a" "--ignore-case" "b" "-ocount" "c"))
      (expect (equal (positional-value inv :paths) '("a" "b" "c")))
      (expect (eq (option-value inv :ignore-case) t))
      (expect (equal (option-value inv :output) "count"))))

  (it "recognizes a global option after the subcommand's rest positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "--verbose" "lib" "-v"))
      (expect (equal (positional-value inv :paths) '("src" "lib")))
      (expect (eq (option-value inv :verbose) t))))

  (it "keeps option-looking tokens after a literal -- in the rest positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "--" "--output" "count" "-i" "--"))
      (expect (equal (positional-value inv :paths) '("src" "--output" "count" "-i" "--")))
      (expect (null (option-value inv :output)))
      (expect (null (option-value inv :ignore-case)))))

  (it "still parses options before a literal -- that follows rest items"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "-i" "--" "-v"))
      (expect (equal (positional-value inv :paths) '("src" "-v")))
      (expect (eq (option-value inv :ignore-case) t))
      (expect (null (option-value inv :verbose)))))

  (it "leaves a rest positional empty when only options follow the last required positional"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "--output" "count"))
      (expect (equal (positional-value inv :pattern) "foo"))
      (expect (null (positional-value inv :paths)))
      (expect (equal (option-value inv :output) "count"))))

  (it "enforces rest :min-count and :max-count over tokens split by options"
    (signals cli-missing-positional
      (parse-argv (%rest-search-app :min-count 1)
                  '("grep" "search" "foo" "--output" "count")))
    (signals cli-unexpected-argument
      (parse-argv (%rest-search-app :max-count 1)
                  '("grep" "search" "foo" "a" "--output" "count" "b")))
    (with-parsed-argv (inv (%rest-search-app :min-count 2 :max-count 2)
                           '("grep" "search" "foo" "a" "-i" "b"))
      (expect (equal (positional-value inv :paths) '("a" "b")))))

  (it "rejects an unknown option after a rest positional instead of collecting it"
    (signals cli-unknown-option
      (parse-argv (%rest-search-app)
                  '("grep" "search" "foo" "src" "--no-such-option"))))

  (it "honors --help after rest positional items"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "src" "--help"))
      (expect (eq (invocation-action inv) :help))))

  (it "applies the negative-number policy to tokens after a rest positional"
    (with-parsed-argv (inv (%rest-search-app :allow-negative-numbers t)
                           '("grep" "search" "foo" "-5" "src" "-1.5" "-i"))
      (expect (equal (positional-value inv :paths) '("-5" "src" "-1.5")))
      (expect (eq (option-value inv :ignore-case) t)))
    (signals cli-unknown-option
      (parse-argv (%rest-search-app)
                  '("grep" "search" "foo" "src" "-5"))))

  (it "keeps a bare - in the rest positional while parsing later options"
    (with-parsed-argv (inv (%rest-search-app)
                           '("grep" "search" "foo" "-" "--output" "count"))
      (expect (equal (positional-value inv :paths) '("-")))
      (expect (equal (option-value inv :output) "count"))))

  (it "passes option-looking script arguments through -- in the nshell example"
    (with-parsed-argv (inv (make-example-app "MAKE-NSHELL-APP")
                           '("nshell" "build.ns" "a" "--" "--json"))
      (expect (equal (positional-value inv :script) "build.ns"))
      (expect (equal (positional-value inv :script-argv) '("a" "--json"))))
    (signals cli-unknown-option
      (parse-argv (make-example-app "MAKE-NSHELL-APP")
                  '("nshell" "build.ns" "--json"))))

  (it "recognizes global options after a root rest positional"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :global-options (list (flag-option "verbose" :short #\v)
                                                           (value-option "output"))
                                     :positionals (list (make-positional :key :files
                                                                         :rest-p t)))
                           '("tool" "a" "--output" "x" "b" "-v"))
      (expect (equal (positional-value inv :files) '("a" "b")))
      (expect (equal (option-value inv :output) "x"))
      (expect (eq (option-value inv :verbose) t)))))
