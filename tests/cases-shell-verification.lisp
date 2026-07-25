(in-package :cl-cli/tests)

;;;; Verify generated scripts with the REAL tools that consume them (bash, zsh,
;;;; fish, nushell, powershell, elvish, mandoc) -- catching structural errors
;;;; substring assertions cannot. Each check is skipped when its tool is absent.
;;;;
;;;; Every subprocess launch here goes through CL-PROCESS-KIT with an explicit
;;;; :TIMEOUT: a hung syntax-checker (a broken local install prompting on
;;;; stdin, for example) escalates SIGTERM/SIGKILL and returns rather than
;;;; blocking the test run indefinitely. PROCESS-KIT also puts each child in
;;;; its own process group, so a timeout cannot leave an orphaned grandchild
;;;; behind the way a bare terminate-process could.

(defparameter +shell-tool-timeout-seconds+ 10
  "Deadline for every real-shell verification subprocess in this file.")

(defparameter +elvish-edit-namespace-stub+
  (format nil "var edit: = (ns [&completion:=(ns [&arg-completer=[&]])])~%")
  "Prelude that makes elvish's interactive-only `edit:' namespace resolvable.

`elvish -compileonly' is the only non-interactive way to compile a script, but
it runs elvish in non-interactive mode, where the `edit:' module does not
exist -- so any real completion script fails on `edit:completion:arg-completer'
before its own contents are ever checked. Binding `edit:' to a plain namespace
value stubs out exactly that one interactive surface and nothing else: parse
errors and unresolved variables anywhere in the generated script still fail the
compile, which the negative-control case below pins down.")

(defun %tool-available-p (name)
  (ignore-errors
    (let ((result (process-kit:run "sh" (list "-c" (format nil "command -v ~A" name))
                                   :search t
                                   :timeout +shell-tool-timeout-seconds+
                                   :on-timeout :return)))
      (and (not (process-kit:process-result-timed-out-p result))
           (zerop (process-kit:process-result-exit-code result))))))

(defun %check-tool (program args script &key (timeout +shell-tool-timeout-seconds+))
  "Run PROGRAM ARGS against SCRIPT (written to a temp file), returning
(values stdout stderr exit-code) -- a timed-out run reports exit code 124,
the conventional shell timeout(1) exit status."
  (uiop:with-temporary-file (:pathname path :stream stream :direction :output)
    (write-string script stream)
    (finish-output stream)
    (let ((result (process-kit:run program (append args (list (namestring path)))
                                   :search t
                                   :timeout timeout
                                   :on-timeout :return)))
      (values (process-kit:process-result-stdout result)
              (process-kit:process-result-stderr result)
              (if (process-kit:process-result-timed-out-p result)
                  124
                  (process-kit:process-result-exit-code result))))))

(defun verification-app ()
  (make-app
   :name "vtool" :version "1.0" :summary "Verification app."
   :manual-date "2026-07-20" :authors '("Ada" "Alan") :see-also '("git(1)")
   :global-options (list (make-option :name "verbose" :short #\v :kind :count)
                         (make-option :name "mode" :kind :value :choices '("dev" "prod"))
                         (make-option :name "config" :kind :value :value-hint :file
                                      :env-var "VTOOL_CONFIG" :description "Config file.")
                         (make-option :name "outdir" :kind :value :value-hint :dir)
                         (make-option :name "define" :short #\D :kind :key-value)
                         (make-option :name "branch" :kind :value
                                      :complete (lambda (p) (declare (ignore p)) '("main"))))
   :positionals (list (make-positional :key :env :choices '("a" "b")))
   :commands (append (make-standard-commands :include-completion-p t :include-docs-p t
                                             :include-dynamic-p t)
                     (list (make-command
                            :name "remote"
                            :options (list (make-option :name "porcelain" :kind :flag))
                            :subcommands (list (make-command :name "add")
                                               (make-command :name "remove")))))))

(describe-sequential "generated script verification"
  (it-run-if (%tool-available-p "bash")
      "the generated bash completion passes bash -n"
    (multiple-value-bind (out err code)
        (%check-tool "bash" '("-n") (render-completion (verification-app) "bash"))
      (declare (ignore out))
      (expect (zerop code))
      (expect (zerop (length err)))))

  (it-run-if (%tool-available-p "zsh")
      "the generated zsh completion passes zsh -n"
    (multiple-value-bind (out err code)
        (%check-tool "zsh" '("-n") (render-completion (verification-app) "zsh"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "fish")
      "the generated fish completion passes fish --no-execute"
    (multiple-value-bind (out err code)
        (%check-tool "fish" '("--no-execute") (render-completion (verification-app) "fish"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "mandoc")
      "the generated man page passes mandoc -T lint with no warnings"
    (multiple-value-bind (out err code)
        (%check-tool "mandoc" '("-T" "lint") (render-manpage (verification-app)))
      (declare (ignore code))
      (expect (zerop (length (string-trim '(#\Space #\Newline #\Return) out))))
      (expect (zerop (length (string-trim '(#\Space #\Newline #\Return) err))))))

  (it-run-if (%tool-available-p "nu")
      "the generated nushell completion loads in nushell"
    (multiple-value-bind (out err code)
        (%check-tool "nu" '() (render-completion (verification-app) "nushell"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "pwsh")
      "the generated powershell completion loads in pwsh"
    (multiple-value-bind (out err code)
        (%check-tool "pwsh" '("-NoProfile" "-File")
                     (render-completion (verification-app) "powershell"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "elvish")
      "the generated elvish completion passes elvish -compileonly"
    (multiple-value-bind (out err code)
        (%check-tool "elvish" '("-compileonly")
                     (concatenate 'string +elvish-edit-namespace-stub+
                                  (render-completion (verification-app) "elvish")))
      (declare (ignore out))
      (expect (zerop code))
      (expect (zerop (length err)))))

  (it-run-if (%tool-available-p "elvish")
      "elvish -compileonly rejects a broken completer body, so the check above has teeth"
    ;; Negative control. Without this, a stub that accidentally made every
    ;; script compile would leave the check above passing vacuously forever.
    (multiple-value-bind (out err code)
        (%check-tool "elvish" '("-compileonly")
                     (concatenate 'string +elvish-edit-namespace-stub+
                                  "set edit:completion:arg-completer['x'] = "
                                  "{|@words| put $no-such-variable }"))
      (declare (ignore out err))
      (expect (not (zerop code)))))

  (it-run-if (%tool-available-p "sh")
      "%check-tool's timeout actually terminates a hung child instead of trusting it unverified"
    (let ((started (get-internal-real-time)))
      (multiple-value-bind (out err code)
          (%check-tool "sh" '() (format nil "sleep 5~%") :timeout 1)
        (declare (ignore out err))
        (expect (= code 124))
        (expect (< (/ (- (get-internal-real-time) started)
                     internal-time-units-per-second)
                  4))))))
