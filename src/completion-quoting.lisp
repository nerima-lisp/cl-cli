(in-package :cl-cli)

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

Shared by POSIX shells, Elvish, and PowerShell; QUOTE-ESCAPE selects the
dialect. Control stripping and quoting happen in one pass while writing
directly to STREAM, avoiding an intermediate string."
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

(defun %completion-write-quoted-joined (stream strings separator)
  "Write STRINGS shell-quoted and SEPARATOR-joined directly to STREAM.

Direct emission avoids an intermediate string for each value and for the
joined result."
  (let ((firstp t))
    (dolist (string strings)
      (if firstp
          (setf firstp nil)
          (write-char separator stream))
      (%completion-write-shell-quoted stream string))))

(defun %completion-write-case-labels (stream strings)
  "Write STRINGS as `|`-separated, shell-quoted case labels directly to STREAM.
See %COMPLETION-WRITE-QUOTED-JOINED."
  (%completion-write-quoted-joined stream strings #\|))

(defun %completion-write-space-joined-quoted (stream strings)
  "Write STRINGS shell-quoted and space-separated directly to STREAM.
See %COMPLETION-WRITE-QUOTED-JOINED."
  (%completion-write-quoted-joined stream strings #\Space))
