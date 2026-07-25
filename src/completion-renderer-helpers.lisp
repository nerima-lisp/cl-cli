(in-package :cl-cli)

(defun %completion-dynamic-option-alist (app)
  "Alist of (option-token . key-name) for every visible dynamic option in APP.

Covers global options and the options of every command (including nested
subcommands), so a flat completer -- powershell, nushell, elvish -- can shell
out to `app __complete KEY` when the word before the cursor is a dynamic option.
A token that appears on two options resolves to whichever comes first, the same
single-pool ambiguity the flat completers already accept for their candidate
lists. KEY-NAME is the downcased option key, matching RENDER-COMPLETE-REPLY."
  (let ((specs (collecting
                 (dolist (option (app-global-options app))
                   (collect option))
                 (labels ((walk (commands)
                            (dolist (command commands)
                              (dolist (option (command-options command))
                                (collect option))
                              (walk (command-subcommands command)))))
                   (walk (app-commands app))))))
    (collecting
      (dolist (option specs)
        (when (and (option-complete option)
                   (not (option-hidden-p option)))
          (let ((key (string-downcase (symbol-name (option-key option)))))
            (dolist (name (%completion-recognized-option-names option))
              (collect (cons (option-token-display-name name) key)))))))))

(defun %completion-zsh-write-option-value-case-body (stream options &key attached-p)
  "Write the `case \"$word\" in ...` body for OPTIONS' value candidates directly to STREAM.

Each option's case label and candidate body used to be built as their own
separately-allocated strings and then copied into this function's own
WITH-OUTPUT-TO-STRING buffer; now every value is quoted straight into
whatever buffer the caller passes, matching the bash renderer's
%COMPLETION-BASH-WRITE-VALUE-CASE-BODY."
  (dolist (option options)
    (unless (option-hidden-p option)
      (let ((candidates (%completion-option-candidates option))
            (hint (option-value-hint option))
            (dynamic-p (and (option-complete option) t)))
        (when (or candidates (member hint '(:file :dir)) dynamic-p)
          (format stream "      ")
          (%completion-write-case-labels
           stream (%completion-option-token-patterns option :attached-p attached-p))
          (format stream ")~%")
          (cond
            (candidates
             (%completion-zsh-write-option-candidate-body stream candidates))
            (dynamic-p
             (format stream "        local comp_value~%")
             (format stream "        while IFS=$'\\t' read -r comp_value _; do~%")
             (format stream "          [[ -n \"$comp_value\" && \"$comp_value\" == \"$current_word\"* ]] && compadd -- \"$comp_value\"~%")
             (format stream "        done < <(\"${words[1]}\" __complete ~A \"$current_word\" 2>/dev/null)~%"
                     (string-downcase (symbol-name (option-key option)))))
            ((eq hint :dir)
             (format stream "        _files -/~%"))
            ((eq hint :file)
             (format stream "        _files~%")))
          (format stream "        return 0~%")
          (format stream "        ;;~%"))))))

(defun %completion-command-option-tokens (app command)
  (append (%completion-visible-option-tokens (app-global-options app))
          (when command
            (%completion-visible-option-tokens (command-options command)))
          (%completion-option-tokens-for-specs (built-in-option-specs app))))

(defun %completion-zsh-command-specs (app)
  (collecting
    (dolist (command (%completion-visible-commands app))
      (collect (format nil "~A:~A"
                       (%completion-zsh-describe-field (command-name command))
                       (%completion-zsh-describe-field (command-description command))))
      (dolist (alias (command-aliases command))
        (collect (format nil "~A:alias for ~A"
                         (%completion-zsh-describe-field alias)
                         (%completion-zsh-describe-field (command-name command))))))))

(defun %completion-zsh-write-command-specs (stream app)
  (%completion-zsh-write-assignment stream "command_specs"
                                    (%completion-zsh-command-specs app)))

(defun %completion-zsh-write-assignment (stream variable-name values)
  "Write `  VARIABLE-NAME=(quoted quoted ...)~%` directly to STREAM.

VALUES are already-composed descriptor strings (e.g. \"name:description\");
this only handles the shell-quote-and-join step, straight into STREAM
instead of quoting each value into its own string, joining those into a
second string, and copying that into the caller's buffer a third time."
  (format stream "  ~A=(" variable-name)
  (%completion-write-space-joined-quoted stream values)
  (format stream ")~%"))

(defun %completion-zsh-option-placeholder (option)
  (or (option-value-name option)
      "value"))

(defun %completion-zsh-arguments-field (value)
  "Return VALUE safe for zsh `_arguments` bracket/placeholder fields.

Strips control characters and blanks out `[`/`]`/`:`/`\\` (zsh `_arguments`
field delimiters) in one pass over VALUE, rather than through
%COMPLETION-CONTROL-SAFE-STRING (a second, separately-allocated
WITH-OUTPUT-TO-STRING pass) -- the same fix already applied to
%COMPLETION-SHELL-QUOTE. The two character sets are disjoint (none of
`[]:\\` is a control code), so folding both into one COND is behavior-
preserving; %COMPLETION-CONTROL-SAFE-STRING's other call sites are
untouched."
  (let ((string (if value (princ-to-string value) "")))
    (with-output-to-string (out)
      (loop for char across string
            for code = (char-code char)
            do (cond
                 ((find char "[]:\\")
                  (write-char #\Space out))
                 ((or (char= char #\Newline)
                      (char= char #\Return)
                      (char= char #\Tab))
                  (write-char #\Space out))
                 ((or (< code 32)
                      (= code 127)
                      (and (>= code 128) (< code 160)))
                  nil)
                 (t
                  (write-char char out)))))))

(defun %completion-zsh-option-spec (option name)
  (let* ((token (option-token-display-name name))
         (kind (option-kind option)))
    (format nil "~A[~A]~A"
            token
            (%completion-zsh-arguments-field
             (or (option-description option)
                 token))
            (case kind
              ((:value :key-value)
               (format nil ":~A:"
                       (%completion-zsh-arguments-field
                        (%completion-zsh-option-placeholder option))))
              (:optional-value
               (if (option-consume-optional-value-p option)
                   (format nil "::~A:"
                           (%completion-zsh-arguments-field
                            (%completion-zsh-option-placeholder option)))
                   ""))
              (otherwise "")))))

(defun %completion-zsh-option-specs-for-options (options)
  (%completion-option-items-for-options
   options
   #'%completion-recognized-option-names
   #'%completion-zsh-option-spec))

(defun %completion-zsh-option-specs-for-specs (options)
  (%completion-option-items-for-specs
   options
   #'%completion-recognized-option-names
   #'%completion-zsh-option-spec))

(defun %completion-zsh-built-in-option-specs (app)
  (%completion-zsh-option-specs-for-specs (built-in-option-specs app)))

(defun %completion-zsh-write-option-specs (stream options variable-name &key app)
  (%completion-zsh-write-assignment
   stream variable-name
   (append (%completion-zsh-option-specs-for-options options)
           (when app
             (%completion-zsh-built-in-option-specs app)))))

(defun %completion-zsh-write-option-candidate-body (stream candidates)
  (if (some #'cdr candidates)
      (progn
        (format stream "        local -a value_candidates~%")
        (format stream "        value_candidates=(~%")
        (dolist (candidate candidates)
          (format stream "          ")
          (%completion-write-shell-quoted
           stream
           (format nil "~A:~A"
                   (car candidate)
                   (%completion-zsh-describe-field (or (cdr candidate) ""))))
          (format stream "~%"))
        (format stream "        )~%")
        (format stream "        _describe 'values' value_candidates~%"))
      (progn
        (format stream "        compadd -Q -S '' -- ")
        (%completion-write-space-joined-quoted stream (mapcar #'car candidates))
        (format stream "~%"))))

(defun %completion-fish-option-arguments (option &key condition)
  (with-output-to-string (out)
    (dolist (name (option-names option))
      (if (= (length name) 1)
          (format out " -s ~A" name)
          (format out " -l ~A" name)))
    (dolist (name (option-negated-names option))
      (format out " -l ~A" name))
    (when condition
      (format out " -n ~A"
              (%completion-shell-quote condition)))
    (let ((kind (option-kind option)))
      (when (member kind '(:value :optional-value :key-value))
        (format out " -r")
        ;; An option with an explicit candidate set completes only those values;
        ;; add -f so fish does not also fall back to file completion (a file path
        ;; is not one of the allowed values).
        (when (%completion-option-candidates option)
          (format out " -f")))
      (when (%valueless-option-kind-p kind)
        (format out " -f")))
    (when (option-description option)
      (format out " -d ~A"
              (%completion-shell-quote (option-description option))))))

(defun %completion-fish-dynamic-command (app option)
  (format nil "(command ~A __complete ~A (commandline -ct))"
          (%completion-shell-quote (app-name app))
          (string-downcase (symbol-name (option-key option)))))

(defun %completion-fish-option-candidate-lines (quoted-app-name app option arguments stream)
  "Emit OPTION's `complete -c ...` lines to STREAM.

QUOTED-APP-NAME is (%COMPLETION-SHELL-QUOTE (APP-NAME APP)), computed once by
the caller and reused across every line here (and across every option, via
%RENDER-FISH-OPTION-LINES) instead of being re-quoted per candidate as the
original did -- for an option with many candidates this was the dominant
redundant allocation in this renderer. APP itself is still needed for
%COMPLETION-FISH-DYNAMIC-COMMAND, which composes a *different*, unquoted
embedded expression rather than a plain `-c` argument."
  (let ((candidates (%completion-option-candidates option)))
    (if (some #'cdr candidates)
        (dolist (candidate candidates)
          (format stream "complete -c ~A~A -a ~A~@[ -d ~A~]~%"
                  quoted-app-name
                  arguments
                  (%completion-shell-quote (car candidate))
                  (and (cdr candidate)
                       (%completion-shell-quote (cdr candidate)))))
        (cond
          (candidates
           (format stream "complete -c ~A~A -a ~A~%"
                   quoted-app-name
                   arguments
                   (%completion-shell-quote
                    (%completion-space-joined
                     (%completion-option-candidate-values option)))))
          ;; A :complete function is queried at runtime: fish passes the current
          ;; token to `app __complete KEY ...` and offers the lines it prints.
          ((option-complete option)
           (format stream "complete -c ~A~A -f -a ~A~%"
                   quoted-app-name
                   arguments
                   (%completion-shell-quote
                    (%completion-fish-dynamic-command app option))))
          ;; A :dir hint completes directories only (-f suppresses fish's default
          ;; file fallback); a :file hint / plain value option keeps that default.
          ((eq (option-value-hint option) :dir)
           (format stream "complete -c ~A~A -f -a '(__fish_complete_directories)'~%"
                   quoted-app-name
                   arguments))
          (t
           (format stream "complete -c ~A~A~%"
                   quoted-app-name
                   arguments))))))

(defun %render-fish-option-lines (quoted-app-name app options condition stream)
  (dolist (option options)
    (unless (option-hidden-p option)
      (let ((arguments (%completion-fish-option-arguments option
                                                           :condition condition)))
        (%completion-fish-option-candidate-lines quoted-app-name app option arguments stream)))))
