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
               (lambda (ch)
                 (if (or (alphanumericp ch) (char= ch #\_))
                     ch
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

(defun %completion-space-joined (strings)
  ;; :TEST #'EQUAL (not #'STRING=) is semantically identical for strings --
  ;; EQUAL compares strings with STRING= itself -- but lets SBCL dispatch to
  ;; its hash-table-based dedup instead of an O(n^2) pairwise scan; matters
  ;; once an app has a large option/command count.
  (format nil "~{~A~^ ~}"
          (remove-duplicates strings :test #'equal)))

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
