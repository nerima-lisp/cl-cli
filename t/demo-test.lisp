(in-package :cl-cli/test)

;;;; The demo executable, end to end through RUN-APP -- the same entry point
;;;; `cl-cli/demo:main` calls, driven with string streams instead of the
;;;; process's own.
;;;;
;;;; This is the only place the library is exercised as a WHOLE CLI rather than
;;;; a unit: argv in, exit code and rendered text out. A dispatch regression
;;;; that every unit test still passes (an alias resolving to the wrong node, a
;;;; default subcommand stopping at its parent) surfaces here as wrong output.

(defun %demo-run (argv)
  "Run the demo app on ARGV, returning (values exit-code stdout stderr).

ARGV carries argv0 as its first element, the C shape RUN-APP wants and the
shape `cl-cli/demo:main' hands it via APPLICATION-ARGV."
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream)))
    (let ((code (run-app (demo-app) :argv argv :stdout stdout :stderr stderr)))
      (values code
              (get-output-stream-string stdout)
              (get-output-stream-string stderr)))))

(defun %demo-stdout (argv)
  (nth-value 1 (%demo-run argv)))

(describe-sequential "cl-cli-demo dispatch"
  (it "greets through the command's own name"
    (multiple-value-bind (code out) (%demo-run '("cl-cli-demo" "greet" "ada"))
      (expect (eql 0 code))
      (expect (string= "Hello, ada!" (string-right-trim '(#\Newline) out)))))

  (it "greets through the command's alias"
    (expect (string= (%demo-stdout '("cl-cli-demo" "greet" "ada"))
                     (%demo-stdout '("cl-cli-demo" "hi" "ada")))))

  (it "applies the command-scoped flag and typed option"
    (expect (string= (format nil "Hello, ADA!~%Hello, ADA!~%")
                     (%demo-stdout '("cl-cli-demo" "greet" "--upcase" "--repeat" "2" "ada")))))

  (it "falls back to the positional default"
    (expect (search "Hello, world!" (%demo-stdout '("cl-cli-demo" "greet")))))

  (it "rejects a --repeat outside the declared bounds"
    ;; :min 1 / :max 10 on a :type :integer option is parser-level validation,
    ;; so the failure has to arrive as a usage error, not as a handler crash.
    (expect (eql 64 (%demo-run '("cl-cli-demo" "greet" "--repeat" "99" "ada")))))

  (it "dispatches into a nested subcommand"
    (multiple-value-bind (code out)
        (%demo-run '("cl-cli-demo" "remote" "add" "origin" "https://example.invalid/r.git"))
      (expect (eql 0 code))
      (expect (search "remote add: origin -> https://example.invalid/r.git" out))))

  (it "resolves the group alias and the leaf alias together"
    (expect (string= (%demo-stdout '("cl-cli-demo" "remote" "remove" "origin"))
                     (%demo-stdout '("cl-cli-demo" "rmt" "rm" "origin")))))

  (it "dispatches the group's default subcommand when no subcommand token follows"
    (multiple-value-bind (code out) (%demo-run '("cl-cli-demo" "remote"))
      (expect (eql 0 code))
      (expect (search "remote list:" out))))

  (it "reports the dispatch path on stderr under --verbose"
    (multiple-value-bind (code out err)
        (%demo-run '("cl-cli-demo" "-v" "remote" "add" "o" "u"))
      (declare (ignore out))
      (expect (eql 0 code))
      (expect (search "dispatched: remote add" err))))

  (it "fails with EX_USAGE when no command is given"
    ;; :require-command t -- the root has no handler, so a bare invocation must
    ;; be a usage error rather than a silent success.
    (expect (eql 64 (%demo-run '("cl-cli-demo"))))))

(describe-sequential "cl-cli-demo help and version"
  (it "prints app help listing every top-level command"
    (multiple-value-bind (code out) (%demo-run '("cl-cli-demo" "--help"))
      (expect (eql 0 code))
      (expect (plusp (length (string-trim '(#\Space #\Newline) out))))
      (expect (search "Usage: cl-cli-demo" out))
      (expect (search "Commands:" out))
      (dolist (name '("greet" "remote" "help" "version" "completion" "docs"))
        (expect (search name out)))))

  (it "prints command help for a nested subcommand"
    (multiple-value-bind (code out) (%demo-run '("cl-cli-demo" "remote" "add" "--help"))
      (expect (eql 0 code))
      (expect (search "remote add" out))))

  (it "prints a version that matches the cl-cli/demo system's own :version"
    ;; The demo carries its version as a literal (see +DEMO-VERSION+); this is
    ;; the gate that keeps that literal equal to the .asd, which is what
    ;; flake.nix's `fromAsdSystem` reads.
    (multiple-value-bind (code out) (%demo-run '("cl-cli-demo" "--version"))
      (expect (eql 0 code))
      (expect (search "cl-cli-demo" out))
      (expect (search (asdf:component-version (asdf:find-system "cl-cli/demo")) out)))))

(describe-sequential "cl-cli-demo completion"
  (it "covers every shell cl-cli supports"
    ;; Pins the case list below to the library's own canonical set, so a
    ;; seventh renderer cannot be added without this suite noticing.
    (expect (equal '("bash" "zsh" "fish" "powershell" "nushell" "elvish")
                   (mapcar #'car cl-cli::+completion-shells+))))

  (it-each (("bash") ("zsh") ("fish") ("powershell") ("nushell") ("elvish"))
      "renders a non-empty ~A completion script"
      (shell)
    (let ((script (render-completion (demo-app) shell)))
      (expect (plusp (length (string-trim '(#\Space #\Newline) script))))
      (expect (search "cl-cli-demo" script))))

  (it-each (("bash") ("zsh") ("fish") ("powershell") ("nushell") ("elvish"))
      "prints the ~A completion script through the completion command"
      (shell)
    (multiple-value-bind (code out) (%demo-run (list "cl-cli-demo" "completion" shell))
      (expect (eql 0 code))
      (expect (plusp (length (string-trim '(#\Space #\Newline) out))))))

  (it "rejects an unsupported shell with EX_USAGE"
    (expect (eql 64 (%demo-run '("cl-cli-demo" "completion" "tcsh"))))))
