(in-package :cl-cli)

(defun %completion-zsh-write-command-labels (stream command)
  (let ((firstp t))
    (dolist (name (%completion-command-names command))
      (if firstp
          (setf firstp nil)
          (write-char #\| stream))
      (write-string name stream))))

(defun %completion-zsh-write-case-section (stream word body)
  (when (plusp (length body))
    (format stream "    case \"$~A\" in~%" word)
    (write-string body stream)
    (format stream "    esac~%")))

(defun %completion-zsh-render-value-cases (options stream)
  ;; %COMPLETION-ZSH-WRITE-OPTION-VALUE-CASE-BODY's emission condition never
  ;; depends on ATTACHED-P, so previous_word and current_word are always
  ;; either both empty or both non-empty for a given OPTIONS list; each still
  ;; gets its own small buffer (not one per option) purely so
  ;; %COMPLETION-ZSH-WRITE-CASE-SECTION can skip the `case ... esac` wrapper
  ;; entirely when there is nothing to complete.
  (dolist (section (list (cons "previous_word" nil) (cons "current_word" t)))
    (let ((body (with-output-to-string (buf)
                  (%completion-zsh-write-option-value-case-body
                   buf options :attached-p (cdr section)))))
      (%completion-zsh-write-case-section stream (car section) body))))

(defun %completion-zsh-write-subcommand-specs (stream subcommands)
  "Write the `subcommand_specs=(...)` assignment for SUBCOMMANDS directly to STREAM."
  (%completion-zsh-write-assignment
   stream "subcommand_specs"
   (let (specs)
     (dolist (command subcommands (nreverse specs))
       (push (format nil "~A:~A"
                     (%completion-zsh-describe-field (command-name command))
                     (%completion-zsh-describe-field (command-description command)))
             specs)
       (dolist (alias (command-aliases command))
         (push (format nil "~A:alias for ~A"
                       (%completion-zsh-describe-field alias)
                       (%completion-zsh-describe-field (command-name command)))
               specs))))))

(defun %completion-zsh-write-command-node (stream app command scope-options depth)
  "Write the `NAME) ... ;;' case clause for COMMAND at word index DEPTH directly to STREAM.

SCOPE-OPTIONS accumulates globals plus every ancestor command's options; a
command with subcommands dispatches the next word to them and offers their
names when the cursor is at DEPTH+1. `command_option_specs` is rebuilt per
clause, which is safe because only the single matched command chain executes.

Writes straight into the shared STREAM instead of building its own string for
a parent to copy again -- see %COMPLETION-BASH-WRITE-COMMAND-NODE for the
same fix applied to the bash renderer."
  (let* ((options (append scope-options (command-options command)))
         (subcommands (remove-if #'command-hidden-p (command-subcommands command)))
         (child-depth (1+ depth)))
    (format stream "    ")
    (%completion-zsh-write-command-labels stream command)
    (format stream ")~%")
    (%completion-zsh-write-option-specs stream options "command_option_specs" :app app)
    (%completion-zsh-render-value-cases options stream)
    (when subcommands
      (format stream "      case \"${words[~A]}\" in~%" child-depth)
      (dolist (subcommand subcommands)
        (%completion-zsh-write-command-node stream app subcommand options child-depth))
      (format stream "      esac~%"))
    (format stream "      if [[ \"$current_word\" == -* ]]; then~%")
    (format stream "        _describe 'options' command_option_specs~%")
    (format stream "        return 0~%")
    (format stream "      fi~%")
    (when subcommands
      (format stream "      if (( CURRENT == ~A )); then~%" child-depth)
      (%completion-zsh-write-subcommand-specs stream subcommands)
      (format stream "        _describe 'commands' subcommand_specs~%")
      (format stream "        return 0~%")
      (format stream "      fi~%"))
    (let ((positional-values (%completion-command-positional-values command)))
      (when positional-values
        (format stream "      compadd -- ")
        (%completion-write-space-joined-quoted stream positional-values)
        (format stream "~%")))
    (when (%completion-command-positional-hint-p command :file)
      (format stream "      _files~%"))
    (when (%completion-command-positional-hint-p command :dir)
      (format stream "      _files -/~%"))
    (format stream "      _describe 'options' command_option_specs~%")
    (format stream "      return 0~%")
    (format stream "      ;;~%")))

(defun %completion-zsh-write-command-case-source (stream app command)
  (%completion-zsh-write-command-node stream app command (app-global-options app) 2))

(defun %completion-zsh-write-positional-fallback (app stream indent)
  "Write INDENT-prefixed compadd/_files fallback lines for APP's own
positionals. Shared by RENDER-ZSH-COMPLETION's two tail branches -- the
`case \"$command_word\"` default arm (6-space INDENT) and the no-commands
top-level body (2-space INDENT) -- which offer the same positional
candidates/hints but at different nesting depths."
  (let ((positional-values (%completion-app-positional-values app)))
    (when positional-values
      (format stream "~Acompadd -- " indent)
      (%completion-write-space-joined-quoted stream positional-values)
      (format stream "~%")))
  (when (%completion-app-positional-hint-p app :file)
    (format stream "~A_files~%" indent))
  (when (%completion-app-positional-hint-p app :dir)
    (format stream "~A_files -/~%" indent)))

(defun render-zsh-completion (app &optional stream)
  "Render a zsh completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values."
  (unless stream
    (return-from render-zsh-completion
      (with-output-to-string (string-stream)
        (render-zsh-completion app string-stream))))
  (let ((function-name (%completion-function-name app))
        (app-name (%completion-control-safe-string (app-name app))))
    (format stream "#compdef ~A~%" app-name)
    (format stream "~A() {~%" function-name)
    (format stream "  local current_word previous_word command_word~%")
    (format stream "  local -a command_specs option_specs command_option_specs subcommand_specs value_candidates~%")
    (format stream "  current_word=${words[CURRENT]}~%")
    (format stream "  if (( CURRENT > 1 )); then~%")
    (format stream "    previous_word=${words[CURRENT-1]}~%")
    (format stream "  else~%")
    (format stream "    previous_word=~%")
    (format stream "  fi~%")
    (format stream "  if (( CURRENT > 2 )); then~%")
    (format stream "    command_word=${words[2]}~%")
    (format stream "  else~%")
    (format stream "    command_word=~%")
    (format stream "  fi~%")
    (%completion-zsh-write-command-specs stream app)
    (%completion-zsh-write-option-specs stream (app-global-options app) "option_specs" :app app)
    (%completion-zsh-render-value-cases (app-global-options app) stream)
    (if (%completion-visible-commands app)
        (progn
          (format stream "  case \"$command_word\" in~%")
          (dolist (command (%completion-visible-commands app))
            (%completion-zsh-write-command-case-source stream app command))
          (format stream "    *)~%")
          (format stream "      if [[ \"$current_word\" == -* ]]; then~%")
          (format stream "        _describe 'options' option_specs~%")
          (format stream "        return 0~%")
          (format stream "      fi~%")
          (%completion-zsh-write-positional-fallback app stream "      ")
          (format stream "      _describe 'commands' command_specs~%")
          (format stream "      return 0~%")
          (format stream "      ;;~%")
          (format stream "  esac~%"))
        (progn
          (format stream "  if [[ -z \"$current_word\" || \"$current_word\" == -* ]]; then~%")
          (format stream "    _describe 'options' option_specs~%")
          (format stream "    return 0~%")
          (format stream "  fi~%")
          (%completion-zsh-write-positional-fallback app stream "  ")))
    (format stream "}~%")
    (format stream "compdef ~A " function-name)
    (%completion-write-shell-quoted stream app-name)
    (format stream "~%")
    (values)))
