(in-package :cl-cli)

(defun %completion-visible-commands (app)
  (remove-if #'command-hidden-p (app-commands app)))

(defun %completion-function-name (app)
  ;; The result is emitted as a raw shell function name (e.g. `_demo_completion()`
  ;; and `complete -F ...`), which cannot be quoted. App names are already
  ;; validated to a safe identifier set, but map every non-word character to `_`
  ;; anyway so this never produces a name that could break the function header.
  (format nil "_~A_completion"
          (map 'string
               (lambda (char)
                 (if (or (alphanumericp char) (char= char #\_))
                     char
                     #\_))
               (app-name app))))

(defun %completion-option-items-for-specs (options names-fn item-fn)
  (collecting
    (dolist (option options)
      (dolist (name (funcall names-fn option))
        (collect (funcall item-fn option name))))))

(defun %completion-option-tokens-for-specs (options)
  (%completion-option-items-for-specs
   options
   #'%completion-all-option-names
   (lambda (option name)
     (declare (ignore option))
     (option-token-display-name name))))

(defun %completion-option-items-for-options (options names-fn item-fn)
  (%completion-option-items-for-specs
   (remove-if #'option-hidden-p options)
   names-fn
   item-fn))

(defun %completion-visible-option-tokens (options)
  (%completion-option-items-for-options
   options
   #'%completion-all-option-names
   (lambda (option name)
     (declare (ignore option))
     (option-token-display-name name))))

(defun %completion-command-names (command)
  (cons (command-name command)
        (command-aliases command)))

(defun %completion-all-option-names (option)
  (append (option-names option)
          (option-negated-names option)))

(defun %completion-recognized-option-names (option)
  (remove-duplicates
   (%completion-all-option-names option)
   :test #'equal))

(defun %completion-visible-command-tokens (app)
  (collecting
    (dolist (command (%completion-visible-commands app))
      (collect (command-name command))
      (dolist (alias (command-aliases command))
        (collect alias)))))

(defun %completion-write-control-safe (stream value &optional extra-blank)
  "Write VALUE to STREAM with control characters dropped and whitespace
controls mapped to a space; any character found in EXTRA-BLANK is also
mapped to a space.

Shared by %COMPLETION-CONTROL-SAFE-STRING (no EXTRA-BLANK) and
%COMPLETION-ZSH-ARGUMENTS-FIELD (EXTRA-BLANK `[]:\\`, zsh `_arguments`
field delimiters) -- the latter's own delimiter set is disjoint from both
the control-code range and the whitespace-control set, so adding it as one
more COND clause ahead of them is behavior-preserving for both callers."
  (let ((string (if value (princ-to-string value) "")))
    (loop for char across string
          for code = (char-code char)
          do (cond
               ((and extra-blank (find char extra-blank))
                (write-char #\Space stream))
               ((or (char= char #\Newline)
                    (char= char #\Return)
                    (char= char #\Tab))
                (write-char #\Space stream))
               ((%control-character-code-p code)
                nil)
               (t
                (write-char char stream))))))

(defun %completion-control-safe-string (value)
  "Return VALUE as a single printable completion protocol field."
  (with-output-to-string (out)
    (%completion-write-control-safe out value)))

(defun %completion-zsh-describe-field (value)
  "Return VALUE as one safe `_describe` NAME or DESCRIPTION field."
  (with-output-to-string (out)
    (loop for char across (%completion-control-safe-string value)
          do (write-char (if (char= char #\:) #\Space char) out))))

(defun %completion-zsh-describe-value (value)
  "Return VALUE as one `_describe` NAME field, with the separator escaped.

`_describe` splits each entry at the first unescaped colon, so a candidate
whose *value* contains one -- `host:8080', a `key:value' pair -- is otherwise
truncated to the part before it while the remainder is silently folded into
the description, and the user tab-completes `host'. The description half can
afford to map a colon to a space (%COMPLETION-ZSH-DESCRIBE-FIELD); the value
half cannot, because it is the text inserted on the command line, so the colon
is backslash-escaped and `_describe' hands the original back. Backslashes get
the same treatment in the same pass, or a value containing one would consume
the escape we just added."
  (with-output-to-string (out)
    (loop for char across (%completion-control-safe-string value)
          do (when (or (char= char #\:) (char= char #\\))
               (write-char #\\ out))
             (write-char char out))))

(defun %completion-write-single-quoted (stream string quote-escape)
  "Write STRING single-quoted to STREAM, writing QUOTE-ESCAPE for an embedded quote.

Shared skeleton for the two single-quoting dialects this codebase supports --
POSIX shells close-escape-reopen (`'\"'\"'`), Elvish/PowerShell double the
quote (`''`) -- which otherwise differ only in that one substring. Strips
control characters in the same pass rather than through
%COMPLETION-CONTROL-SAFE-STRING (a second, separately-allocated
WITH-OUTPUT-TO-STRING pass): quote-escaping and control-stripping act on
disjoint character sets (a quote is never itself a control code), so folding
both into one COND is behavior-preserving and, on an app with many options,
avoids render-completion's hottest single allocation -- every option/command
name and description is shell-quoted at least once.

Writing straight to a caller-supplied STREAM (instead of always returning a
freshly-consed string) lets hot callers that already hold an open stream --
e.g. the bash renderer's array-literal/case-label builders -- skip an
intermediate string allocation per quoted value entirely."
  (let ((value (if string (princ-to-string string) "")))
    (write-char #\' stream)
    (loop for char across value
          for code = (char-code char)
          do (cond
               ((char= char #\')
                (write-string quote-escape stream))
               ((or (char= char #\Newline)
                    (char= char #\Return)
                    (char= char #\Tab))
                (write-char #\Space stream))
               ((%control-character-code-p code)
                nil)
               (t
                (write-char char stream))))
    (write-char #\' stream)))

(defun %completion-write-shell-quoted (stream string)
  "Write STRING single-quoted for a POSIX shell (bash/zsh/fish) directly to STREAM.
See %COMPLETION-WRITE-SINGLE-QUOTED."
  (%completion-write-single-quoted stream string "'\"'\"'"))

(defun %completion-shell-quote (string)
  "Single-quote STRING for a POSIX shell (bash/zsh/fish); see %COMPLETION-WRITE-SHELL-QUOTED."
  (with-output-to-string (out)
    (%completion-write-shell-quoted out string)))

(defun %completion-write-quote-doubled (stream string)
  "Write STRING single-quoted to STREAM, doubling an embedded quote to escape it.

Shared by Elvish and PowerShell, whose single-quoted-string syntax escapes an
embedded quote identically -- unlike the POSIX shells, which close-escape-
reopen. See %COMPLETION-WRITE-SINGLE-QUOTED."
  (%completion-write-single-quoted stream string "''"))

(defun %completion-space-joined (strings)
  ;; :TEST #'EQUAL (not #'STRING=) is semantically identical for strings --
  ;; EQUAL compares strings with STRING= itself -- but lets SBCL dispatch to
  ;; its hash-table-based dedup instead of an O(n^2) pairwise scan; matters
  ;; once an app has a large option/command count.
  (format nil "~{~A~^ ~}"
          (remove-duplicates strings :test #'equal)))

(defun %completion-write-case-labels (stream strings)
  "Write STRINGS as `|`-separated, shell-quoted case labels directly to STREAM.

Shared by the bash and zsh renderers' `case \"$word\" in ...` sections --
quotes each label straight into STREAM instead of quoting it into its own
string, joining those into a second string via %COMPLETION-CASE-LABELS, and
copying that into the caller's buffer a third time."
  (let ((firstp t))
    (dolist (string strings)
      (if firstp
          (setf firstp nil)
          (write-char #\| stream))
      (%completion-write-shell-quoted stream string))))

(defun %completion-write-space-joined-quoted (stream strings)
  "Write STRINGS shell-quoted and space-separated directly to STREAM.

Shared by the bash/zsh renderers' `compadd`/array-literal builders for the
same reason as %COMPLETION-WRITE-CASE-LABELS: one quote pass straight into
STREAM instead of quoting each value into its own string and then joining
those strings a second time."
  (let ((firstp t))
    (dolist (string strings)
      (if firstp
          (setf firstp nil)
          (write-char #\Space stream))
      (%completion-write-shell-quoted stream string))))

(defun %completion-option-candidates (option)
  (or (option-completion-candidates option)
      (mapcar (lambda (choice)
                (cons choice nil))
              (option-choices option))))

(defun %completion-option-candidate-values (option)
  (mapcar #'car (%completion-option-candidates option)))

(defun %completion-positional-candidates (positional)
  (or (positional-completion-candidates positional)
      (mapcar (lambda (choice) (cons choice nil))
              (positional-choices positional))))

(defun %completion-positional-candidate-values (positional)
  (mapcar #'car (%completion-positional-candidates positional)))

(defun %completion-app-positional-values (app)
  (collecting
    (dolist (positional (app-positionals app))
      (dolist (value (%completion-positional-candidate-values positional))
        (collect value)))))

(defun %completion-command-positional-values (command)
  (collecting
    (dolist (positional (command-positionals command))
      (dolist (value (%completion-positional-candidate-values positional))
        (collect value)))))

(defun %completion-positionals-hint-p (positionals hint)
  "True when any positional in POSITIONALS declares :value-hint HINT."
  (some (lambda (positional) (eq (positional-value-hint positional) hint))
        positionals))

(defun %completion-app-positional-hint-p (app hint)
  (%completion-positionals-hint-p (app-positionals app) hint))

(defun %completion-command-positional-hint-p (command hint)
  (%completion-positionals-hint-p (command-positionals command) hint))

(defun %completion-option-value-source (option)
  (%completion-option-candidate-values option))

(defun %completion-option-token-patterns (option &key command-name attached-p)
  "Case-label patterns matching OPTION's tokens (optionally command-scoped)."
  (loop for name in (%completion-recognized-option-names option)
        for token = (option-token-display-name name)
        collect (if command-name
                    (format nil "~A:~A~A"
                            command-name
                            token
                            (if attached-p "=*" ""))
                    (format nil "~A~A"
                            token
                            (if attached-p "=*" "")))))

(defun %completion-option-value-patterns (option &key command-name attached-p)
  (when (%completion-option-candidates option)
    (%completion-option-token-patterns option
                                       :command-name command-name
                                       :attached-p attached-p)))

;;; %COMPLETION-OPTION-SCAN-RULES now lives in completion-renderers-bash.lisp
;;; (it writes directly into that renderer's shared stream instead of
;;; returning its own string).
