;;;; demo/main.lisp
(in-package #:cl-cli/demo)

;;; The demo is deliberately stateless: every handler reports what the parser
;;; decided rather than mutating anything. A CLI-parsing library's executable
;;; demonstration is the PARSE, so an in-memory store that dies with the
;;; process would only obscure the thing being shown.

(defun %command-path-string (invocation)
  "The dispatched command path as a space-separated string (\"remote add\")."
  (format nil "~{~A~^ ~}"
          (mapcar #'command-name (invocation-command-path invocation))))

(defun %report-invocation (invocation)
  "Print the dispatch path and where each global option's value came from.

Only runs under `--verbose`, and writes to stderr so that piping the demo's
stdout into a test or another program stays unaffected by it."
  (when (plusp (option-value invocation :verbose))
    (let ((stderr (invocation-stderr invocation)))
      (format stderr "~&; dispatched: ~A~%" (%command-path-string invocation))
      (dolist (key '(:format :config))
        (let ((source (option-value-source invocation key)))
          (when source
            (format stderr "; --~(~A~) = ~A (from ~(~A~))~%"
                    key (option-value invocation key) source)))))))

(defun %greet (invocation)
  (%report-invocation invocation)
  (let* ((who (positional-value invocation :name))
         (text (if (option-value invocation :upcase) (string-upcase who) who)))
    (dotimes (i (option-value invocation :repeat))
      (declare (ignore i))
      (format (invocation-stdout invocation) "Hello, ~A!~%" text)))
  0)

(defun %remote-add (invocation)
  (%report-invocation invocation)
  (format (invocation-stdout invocation) "remote add: ~A -> ~A~%"
          (positional-value invocation :name)
          (positional-value invocation :url))
  0)

(defun %remote-remove (invocation)
  (%report-invocation invocation)
  (format (invocation-stdout invocation) "remote remove: ~A~%"
          (positional-value invocation :name))
  0)

(defun %remote-list (invocation)
  (%report-invocation invocation)
  (format (invocation-stdout invocation) "remote list: no remotes configured~%")
  0)

(defun %remote-command ()
  "A nested subcommand group, the `git remote add` shape MAKE-COMMAND documents.

Carries an alias (`rmt`), a default subcommand (`list`, dispatched when no
subcommand token follows), and an aliased leaf (`remove` / `rm`) -- the three
dispatch behaviours that are easy to break and invisible in a unit test that
only ever calls PARSE-ARGV on a flat argv."
  (make-command
   :name "remote"
   :aliases '("rmt")
   :description "Manage remotes; dispatches like a mini-app."
   :options (list (make-option :name "porcelain" :kind :flag
                               :description "Machine-readable output."))
   :default-command "list"
   :subcommands
   (list (make-command :name "add"
                       :description "Add a remote."
                       :positionals (list (make-positional :key :name :required-p t)
                                          (make-positional :key :url :required-p t))
                       :handler #'%remote-add)
         (make-command :name "remove"
                       :aliases '("rm")
                       :description "Remove a remote."
                       :positionals (list (make-positional :key :name :required-p t))
                       :handler #'%remote-remove)
         (make-command :name "list"
                       :description "List remotes."
                       :handler #'%remote-list))))

(defparameter +demo-version+ "1.1.0"
  "The version `cl-cli-demo --version` prints.

A literal, not `(asdf:component-version (asdf:find-system \"cl-cli/demo\"))`:
reading it back at load time makes this file unloadable outside a session where
ASDF has already registered the system, which is a real cost for the sake of a
number that is checked anyway. t/demo-test.lisp asserts this string equals the
`cl-cli/demo` system's own `:version`, so the drift a literal invites fails a
test instead of shipping.")

(defun demo-app ()
  "The application specification the demo executable dispatches on.

A function rather than a load-time DEFPARAMETER so the test suite builds a
fresh spec per case, matching the `make-*-app` builders in
examples/consumer-migrations.lisp."
  (make-app
   :name "cl-cli-demo"
   :version +demo-version+
   :summary "Runnable demonstration of cl-cli's parsing, dispatch, and rendering."
   :description "Every construct cl-cli advertises, wired into a binary: global
options with choices and an environment fallback, a nested subcommand group with
an alias and a default subcommand, and the standard help, version, completion and
docs commands."
   ;; REQUIRE-COMMAND: the root does nothing on its own, so a bare invocation
   ;; is a usage error listing the commands rather than a silent success.
   :require-command t
   :authors '("takeokunn <bararararatty@gmail.com>")
   :see-also '("cl-cli(3)")
   :global-options
   (list (make-option :name "verbose" :short #\v :kind :count
                      :description "Report the dispatch path and option sources on stderr.")
         (make-option :name "format" :kind :value :choices '("text" "json")
                      :default "text"
                      :description "Output format.")
         (make-option :name "config" :kind :value :value-hint :file
                      :env-var "CL_CLI_DEMO_CONFIG"
                      :description "Configuration file to read."))
   :commands
   (append (make-standard-commands :include-completion-p t
                                   :include-docs-p t
                                   :include-dynamic-p t)
           (list (make-command
                  :name "greet"
                  :aliases '("hi")
                  :description "Print a greeting."
                  :options (list (make-option :name "upcase" :kind :flag
                                              :description "Shout the greeting.")
                                 (make-option :name "repeat" :kind :value :type :integer
                                              :min 1 :max 10 :default 1
                                              :description "Repeat the greeting N times."))
                  :positionals (list (make-positional :key :name :default "world"
                                                      :description "Who to greet."))
                  :handler #'%greet)
                 (%remote-command)))
   :examples '("cl-cli-demo greet --upcase ada"
               "cl-cli-demo remote add origin https://example.invalid/repo.git"
               "cl-cli-demo completion zsh")))

(defun main ()
  "cl-cli.asd's :ENTRY-POINT for the `cl-cli/demo` system's executable.

APPLICATION-ARGV is cl-cli's own launcher-aware argv reader, and it keeps
argv0 as the first element -- the C argv shape RUN-APP expects, unlike
UIOP:COMMAND-LINE-ARGUMENTS, which has already dropped it. :COLOR and :WIDTH
are :AUTO so the binary honours NO_COLOR and $COLUMNS the way a real CLI does.

The exit is reader-conditionalised the same way src/ is: HOST-KIT is SBCL-only
and cl-cli.asd names it under `#+sbcl`, so a non-SBCL image loading this system
(the ECL portability gate does) must never see the symbol."
  (let ((code (run-app (demo-app)
                       :argv (application-argv)
                       :color :auto
                       :width :auto)))
    #+sbcl (host-kit:quit code)
    #-sbcl (uiop:quit code)))
