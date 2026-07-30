(in-package :cl-cli)

;;;; A PowerShell completion renderer.
;;;;
;;;; Emits a `Register-ArgumentCompleter -Native` script block that offers
;;;; subcommands and option tokens, narrowing to a subcommand's own options once
;;;; that subcommand appears on the line. Follows the same optional-stream
;;;; convention as the other completion renderers.

(defun %completion-powershell-quote (string)
  "Quote STRING as a PowerShell single-quoted literal.

PowerShell escapes an embedded single quote by doubling it, unlike the POSIX
shells (which close-escape-reopen); this must not reuse %COMPLETION-SHELL-QUOTE.

Strips control characters and doubles embedded single quotes in one pass,
rather than through %COMPLETION-CONTROL-SAFE-STRING (a second, separately-
allocated WITH-OUTPUT-TO-STRING pass) -- the same fix already applied to
%COMPLETION-SHELL-QUOTE and %COMPLETION-ZSH-ARGUMENTS-FIELD. A quote is
never itself a control code, so folding both into one COND is behavior-
preserving; %COMPLETION-CONTROL-SAFE-STRING's other call sites (including
this file's own top-level app-name binding) are untouched."
  (let ((value (if string (princ-to-string string) "")))
    (with-output-to-string (out)
      (write-char #\' out)
      (loop for char across value
            for code = (char-code char)
            do (cond
                 ((char= char #\')
                  (write-string "''" out))
                 ((or (char= char #\Newline)
                      (char= char #\Return)
                      (char= char #\Tab))
                  (write-char #\Space out))
                 ((%control-character-code-p code)
                  nil)
                 (t
                  (write-char char out))))
      (write-char #\' out))))

(defun %completion-powershell-array (tokens)
  "Render TOKENS as a PowerShell array literal `@('a', 'b')`."
  (format nil "@(~{~A~^, ~})"
          (mapcar #'%completion-powershell-quote tokens)))

(defun %completion-powershell-command-option-map (app stream)
  "Emit `$commandOptions` mapping each visible command (and its aliases) to its
own option array.

TOKENS' rendered array literal is built once per command and reused across
every alias, rather than being rebuilt (with its own internal per-token
quoting) once per alias as the original did."
  (format stream "    $commandOptions = @{~%")
  (dolist (command (%completion-visible-commands app))
    (let ((tokens (%completion-visible-option-tokens (command-options command))))
      (when tokens
        (let ((quoted-tokens (%completion-powershell-array tokens)))
          (dolist (name (%completion-command-names command))
            (format stream "        ~A = ~A~%"
                    (%completion-powershell-quote name)
                    quoted-tokens))))))
  (format stream "    }~%"))

(defun %completion-powershell-dynamic-block (app stream)
  "Emit a runtime-callback block for APP's dynamic options, or nothing.

When the word before the cursor is a `:complete` option, the block shells out to
`app __complete KEY <word>` and returns its lines as completion results
(tab-separated descriptions become the result tooltip), then returns early so
the static candidate pool is skipped. Emits nothing when APP has no dynamic
options."
  (let ((alist (%completion-dynamic-option-alist app)))
    (when alist
      (format stream "    $dynamicOptions = @{~%")
      (dolist (pair alist)
        (format stream "        ~A = ~A~%"
                (%completion-powershell-quote (car pair))
                (%completion-powershell-quote (cdr pair))))
      (format stream "    }~%")
      (format stream "    $prevToken = ''~%")
      (format stream "    $elements = $commandAst.CommandElements~%")
      (format stream "    if ($wordToComplete) {~%")
      (format stream "        if ($elements.Count -ge 2) ~
                      { $prevToken = $elements[$elements.Count - 2].ToString() }~%")
      (format stream "    } elseif ($elements.Count -ge 1) {~%")
      (format stream "        $prevToken = $elements[$elements.Count - 1].ToString()~%")
      (format stream "    }~%")
      (format stream "    if ($dynamicOptions.ContainsKey($prevToken)) {~%")
      (format stream "        & ~A '__complete' $dynamicOptions[$prevToken] ~
                      $wordToComplete | ForEach-Object {~%"
              (%completion-powershell-quote (app-name app)))
      (format stream "            $parts = $_ -split \"`t\", 2~%")
      (format stream "            $desc = if ($parts.Count -gt 1) ~
                      { $parts[1] } else { $parts[0] }~%")
      (format stream "            [System.Management.Automation.CompletionResult]~
                      ::new($parts[0], $parts[0], 'ParameterValue', $desc)~%")
      (format stream "        }~%")
      (format stream "        return~%")
      (format stream "    }~%"))))

(defun render-powershell-completion (app &optional stream)
  "Render a PowerShell completion script for APP.

With no STREAM, return the completion script as a string. With a STREAM, write
to it and return no values. The script registers a native argument completer
that suggests subcommands and global option tokens, and switches to a
subcommand's own options once that subcommand is present on the command line.
Hidden commands and options are omitted."
  (ensure-output-stream stream render-powershell-completion app)
  (let ((app-name (%completion-control-safe-string (app-name app))))
    (format stream "# PowerShell completion for ~A~%" app-name)
    (format stream "Register-ArgumentCompleter -Native -CommandName ~A -ScriptBlock {~%"
            (%completion-powershell-quote app-name))
    (format stream "    param($wordToComplete, $commandAst, $cursorPosition)~%")
    (%completion-powershell-dynamic-block app stream)
    (format stream "    $commands = ~A~%"
            (%completion-powershell-array (%completion-visible-command-tokens app)))
    (format stream "    $globalOptions = ~A~%"
            (%completion-powershell-array (%completion-command-option-tokens app nil)))
    (format stream "    $positionals = ~A~%"
            (%completion-powershell-array (%completion-app-positional-values app)))
    (%completion-powershell-command-option-map app stream)
    (format stream "    $selected = $null~%")
    (format stream "    foreach ($element in $commandAst.CommandElements) {~%")
    (format stream "        $value = $element.ToString()~%")
    (format stream "        if ($commandOptions.ContainsKey($value)) ~
                    { $selected = $value; break }~%")
    (format stream "    }~%")
    (format stream "    $candidates = $commands + $globalOptions + $positionals~%")
    (format stream "    if ($selected) ~
                    { $candidates = $globalOptions + $commandOptions[$selected] }~%")
    (format stream "    $candidates | Where-Object ~
                    { $_.StartsWith($wordToComplete, [System.StringComparison]::Ordinal) } ~
                    | Sort-Object -Unique | ForEach-Object {~%")
    (format stream "        [System.Management.Automation.CompletionResult]~
                    ::new($_, $_, 'ParameterValue', $_)~%")
    (format stream "    }~%")
    (format stream "}~%")
    (values)))
