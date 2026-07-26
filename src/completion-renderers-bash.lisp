(in-package :cl-cli)

(defun %completion-bash-write-array-literal (stream strings)
  "Write STRINGS as a bash array literal `(...)` directly to STREAM.

Equivalent to writing (%COMPLETION-BASH-ARRAY-LITERAL STRINGS), but skips
that function's own MAPCAR-of-freshly-quoted-strings + FORMAT NIL join --
each element is quoted straight into STREAM instead of into its own
short-lived string that then gets copied again into a joined string and
copied a third time into the caller's buffer. This function alone was ~65%
of cumulative sampled time rendering a 330-option benchmark app (mostly
WITH-OUTPUT-TO-STRING setup/copy overhead), so cutting two of those three
copies per value is the highest-leverage single change in this renderer."
  (write-char #\( stream)
  (let ((firstp t))
    (dolist (string (remove-duplicates strings :test #'equal))
      (if firstp
          (setf firstp nil)
          (write-char #\Space stream))
      (%completion-write-shell-quoted stream string)))
  (write-char #\) stream))

(defun %completion-bash-write-static-compreply-source (stream values indent &key replace-p)
  (when replace-p
    (format stream "~ACOMPREPLY=()~%" indent))
  (format stream "~Acomp_values=" indent)
  (%completion-bash-write-array-literal stream values)
  (format stream "~%")
  (format stream "~Afor comp_value in \"${comp_values[@]}\"; do~%" indent)
  (format stream "~A  [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] ~
                  && COMPREPLY+=(\"$comp_value\")~%" indent)
  (format stream "~Adone~%" indent))

(defun %completion-bash-write-value-case-body (stream options &key command-name)
  (dolist (option options)
    (unless (option-hidden-p option)
      (let* ((labels (%completion-option-value-patterns option
                                                         :command-name command-name
                                                         :attached-p t))
             (value-source (%completion-option-value-source option)))
        (when (and labels value-source)
          (format stream "    ")
          (%completion-write-case-labels stream labels)
          (format stream ")~%")
          (%completion-bash-write-static-compreply-source stream value-source "      "
                                                           :replace-p t)
          (format stream "      return 0~%")
          (format stream "      ;;~%"))))))

(defun %completion-option-scan-rules (stream options &key command-name)
  (dolist (option options)
    (unless (option-hidden-p option)
      (let ((kind (option-kind option)))
        (when (or (eq kind :value)
                  (and (eq kind :optional-value)
                       (option-consume-optional-value-p option)))
          (let* ((value-source (%completion-option-value-source option))
                 (dir-hint-p (eq (option-value-hint option) :dir))
                 (dynamic-p (and (option-complete option) t))
                 ;; Emit a case for candidates, a :dir hint (explicit compgen
                 ;; -d), or a :complete function (runtime callback). A :file
                 ;; hint / plain value option instead falls through to `complete
                 ;; -o default` filename completion. An empty case label (`)`)
                 ;; is a bash syntax error, so nothing is emitted otherwise.
                 (emit-p (or value-source dir-hint-p dynamic-p))
                 (expect (if (eq kind :value)
                             "expect_value=1"
                             "expect_optional_value=1")))
            (when emit-p
              (format stream "      ")
              (%completion-write-case-labels
               stream
               (%completion-option-token-patterns option :command-name command-name))
              (format stream ") ")
              (cond
                (dynamic-p
                 (format stream "~A comp_dynamic=" expect)
                 (%completion-write-shell-quoted
                  stream (string-downcase (symbol-name (option-key option)))))
                (value-source
                 (format stream "~A value_source=" expect)
                 (%completion-bash-write-array-literal stream value-source))
                (dir-hint-p (format stream "~A comp_dir=1" expect)))
              (format stream " ;;~%"))))))))

(defun %completion-bash-write-expect-value-source (stream indent)
  "Emit the block that turns a pending expect_value into COMPREPLY.

The `case \"$prev\"` scan sets expect_value / expect_optional_value and
value_source when the previous word is a value option; this consumes them so a
separated value (`--option <TAB>`) actually completes its candidates."
  (format stream "~Aif [[ -n \"$expect_value\" || -n \"$expect_optional_value\" ]]; then~%" indent)
  (format stream "~A  COMPREPLY=()~%" indent)
  (format stream "~A  if [[ -n \"$comp_dynamic\" ]]; then~%" indent)
  ;; Query the program itself for runtime candidates (${words[0]} is the exact
  ;; command the user invoked); requires a __complete command in the app.
  ;; Read the tab-separated protocol directly so spaces in candidate values
  ;; stay within the same completion record.
  (format stream "~A    while IFS=$'\\t' read -r comp_value _; do~%" indent)
  (format stream "~A      [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] ~
                  && COMPREPLY+=(\"$comp_value\")~%" indent)
  (format stream "~A    done < <(\"${words[0]}\" __complete \"$comp_dynamic\" \"$cur\" ~
                  2>/dev/null)~%" indent)
  (format stream "~A  elif [[ -n \"$comp_dir\" ]]; then~%" indent)
  (format stream "~A    COMPREPLY=( $(compgen -d -- \"$cur\") )~%" indent)
  (format stream "~A  else~%" indent)
  (format stream "~A    for comp_value in \"${value_source[@]}\"; do~%" indent)
  (format stream "~A      [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] ~
                  && COMPREPLY+=(\"$comp_value\")~%" indent)
  (format stream "~A    done~%" indent)
  (format stream "~A  fi~%" indent)
  (format stream "~A  return 0~%" indent)
  (format stream "~Afi~%" indent))

(defun %completion-bash-write-cur-case-source (stream app)
  (let ((global-options (app-global-options app)))
    (format stream "  case \"$cur\" in~%")
    (%completion-bash-write-value-case-body stream global-options)
    (format stream "  esac~%")
    (format stream "  case \"$prev\" in~%")
    (%completion-option-scan-rules stream global-options)
    (format stream "  esac~%")
    (%completion-bash-write-expect-value-source stream "  ")
    (when (%completion-visible-commands app)
      ;; Complete command names at the first word -- but not when the user is
      ;; typing an option there (`app -<TAB>`), which must fall through to the
      ;; global-option completion below.
      (format stream "  if (( cword == 1 )) && [[ \"$cur\" != -* ]]; then~%")
      (%completion-bash-write-static-compreply-source
       stream (%completion-visible-command-tokens app) "    " :replace-p t)
      (format stream "    return 0~%")
      (format stream "  fi~%"))
    (format stream "  if [[ \"$cur\" == -* ]]; then~%")
    (if (%completion-visible-commands app)
        ;; Offer global options only before a subcommand is on the line; once a
        ;; command is present its own case completes options with the full
        ;; option scope (globals + the command's own). Without this guard the
        ;; root fallback returns global options for every `-*` and shadows all
        ;; subcommand option completion.
        (progn
          (format stream "    case \"${words[1]}\" in~%")
          (format stream "      ")
          (%completion-write-case-labels stream (%completion-visible-command-tokens app))
          (format stream ") ;;~%")
          (format stream "      *)~%")
          (%completion-bash-write-static-compreply-source
           stream (%completion-command-option-tokens app nil) "        " :replace-p t)
          (format stream "        return 0~%")
          (format stream "        ;;~%")
          (format stream "    esac~%"))
        (progn
          (%completion-bash-write-static-compreply-source
           stream (%completion-command-option-tokens app nil) "    " :replace-p t)
          (format stream "    return 0~%")))
    (format stream "  fi~%")
    (let ((positional-values (%completion-app-positional-values app)))
      (when positional-values
        (%completion-bash-write-static-compreply-source stream positional-values "  ")))
    (when (%completion-app-positional-hint-p app :file)
      (format stream "  COMPREPLY+=( $(compgen -f -- \"$cur\") )~%"))
    (when (%completion-app-positional-hint-p app :dir)
      (format stream "  COMPREPLY+=( $(compgen -d -- \"$cur\") )~%"))))

(defun %completion-bash-scope-option-tokens (scope-options app)
  "Visible option tokens for SCOPE-OPTIONS plus APP's built-in tokens."
  (append (%completion-visible-option-tokens scope-options)
          (%completion-option-tokens-for-specs (built-in-option-specs app))))

(defun %completion-bash-write-command-node (stream app command scope-options depth prefix)
  "Recursively write the bash case block for COMMAND at word index DEPTH into STREAM.

SCOPE-OPTIONS accumulates the options in scope (globals + every ancestor
command's options + COMMAND's own); PREFIX is a per-node label prefix (the
command path) that keeps the value/option `case` labels distinct across the
tree. A command with subcommands offers their names at DEPTH+1 and recurses.

Every node writes straight into the shared STREAM instead of building its own
string for a parent to copy again -- the previous version nested a
WITH-OUTPUT-TO-STRING per node, so a deep subcommand's text was re-copied once
per ancestor on the way back up the tree."
  (let* ((options (append scope-options (command-options command)))
         (subcommands (remove-if #'command-hidden-p (command-subcommands command)))
         (child-depth (1+ depth)))
    (format stream "  case \"${words[~A]}\" in~%" depth)
    (format stream "    ")
    (%completion-write-case-labels stream (%completion-command-names command))
    (format stream ")~%")
    (format stream "      case \"~A:$cur\" in~%" prefix)
    (%completion-bash-write-value-case-body stream options :command-name prefix)
    (format stream "      esac~%")
    (format stream "      case \"~A:$prev\" in~%" prefix)
    (%completion-option-scan-rules stream options :command-name prefix)
    (format stream "      esac~%")
    (%completion-bash-write-expect-value-source stream "      ")
    (when subcommands
      (format stream "      if (( cword == ~A )); then~%" child-depth)
      (%completion-bash-write-static-compreply-source
       stream
       (collecting
         (dolist (sub subcommands)
           (dolist (name (%completion-command-names sub))
             (collect name))))
       "        ")
      (format stream "      fi~%")
      (dolist (sub subcommands)
        (%completion-bash-write-command-node
         stream app sub options child-depth
         (format nil "~A/~A" prefix (command-name sub)))))
    (format stream "      if [[ \"$cur\" == -* ]]; then~%")
    (%completion-bash-write-static-compreply-source
     stream (%completion-bash-scope-option-tokens options app) "        " :replace-p t)
    (format stream "      fi~%")
    (let ((positional-values (%completion-command-positional-values command)))
      (when positional-values
        (%completion-bash-write-static-compreply-source stream positional-values "      ")))
    (when (%completion-command-positional-hint-p command :file)
      (format stream "      COMPREPLY+=( $(compgen -f -- \"$cur\") )~%"))
    (when (%completion-command-positional-hint-p command :dir)
      (format stream "      COMPREPLY+=( $(compgen -d -- \"$cur\") )~%"))
    (format stream "      return 0~%")
    (format stream "      ;;~%")
    (format stream "  esac~%")))

(defun %completion-bash-write-command-case-source (stream app command)
  (%completion-bash-write-command-node stream app command (app-global-options app) 1
                                       (command-name command)))

(defun render-bash-completion (app &optional stream)
  "Render a bash completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values."
  (ensure-output-stream stream render-bash-completion app)
  (let ((function-name (%completion-function-name app))
        (app-name (%completion-control-safe-string (app-name app))))
      (format stream "#!/usr/bin/env bash~%")
      (format stream "# bash completion for ~A~%" app-name)
      (format stream "~A() {~%" function-name)
      (format stream "  local cur prev words cword expect_value expect_optional_value ~
                      comp_dir comp_dynamic comp_value~%")
      (format stream "  local -a value_source comp_values~%")
      ;; -s makes _init_completion split `--opt=value` so an attached value
      ;; completes through the same prev-word path as a separated one.
      (format stream "  _init_completion -s || return~%")
      (%completion-bash-write-cur-case-source stream app)
      (dolist (command (%completion-visible-commands app))
        (%completion-bash-write-command-case-source stream app command))
      (format stream "}~%")
      ;; -o default lets a value slot with no explicit candidates (a plain
      ;; :value option, or one with a :file hint) fall back to readline filename
      ;; completion instead of completing nothing.
      (format stream "complete -o default -F ~A " function-name)
      (%completion-write-shell-quoted stream app-name)
      (format stream "~%")
    (values)))
