(in-package :cl-cli)

(defun option-table-from-specs (specs)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (spec specs table)
      (dolist (entry (%option-table-entries spec))
        (destructuring-bind (name negated-p) entry
          (let ((key (canonical-option-name name)))
            (%register-table-entry table
                                   key
                                    (list :spec spec
                                          :name key
                                          :negated-p negated-p)
                                    "option name"
                                    (option-token-display-name key))))))))

(defun command-table-from-specs (commands)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (command commands table)
      (%register-table-entry table
                             (command-name command)
                             (list :command command
                                   :name (command-name command))
                             "command name"
                             (command-name command))
      (dolist (alias (command-aliases command))
        (%register-table-entry table
                               alias
                               (list :command command
                                     :name alias)
                               "command name"
                               alias)))))

(defun public-option-candidate-p (spec)
  (or (not (option-hidden-p spec))
      (built-in-option-p spec)))

(defun public-command-candidate-p (command)
  (not (command-hidden-p command)))

(defun option-candidate-names (specs &key short-only-p long-only-p)
  (let ((candidates nil))
    (dolist (spec specs (nreverse candidates))
      (when (public-option-candidate-p spec)
        (dolist (name (option-names spec))
          (when (or (and short-only-p (= (length name) 1))
                    (and long-only-p (> (length name) 1))
                    (and (not short-only-p) (not long-only-p)))
            (push (option-token-display-name name)
                  candidates)))))))

(defun command-candidate-names (app)
  (let ((candidates nil))
    (dolist (command (app-commands app) (nreverse candidates))
      (when (public-command-candidate-p command)
        (push (command-name command) candidates)
        (dolist (alias (command-aliases command))
          (push alias candidates))))))

(defun unknown-option-message (raw-name candidates)
  (format nil "Unknown option: ~A~A"
          raw-name
          (format-suggestion-suffix raw-name candidates)))

(defun unknown-command-message (app command-name)
  (format nil "Unknown command: ~A~A"
          command-name
          (format-suggestion-suffix command-name
                                    (command-candidate-names app))))

(defvar *allow-abbreviated-options* nil
  "When true, RESOLVE-LONG-OPTION-ENTRY accepts a unique long-option prefix.

Bound by PARSE-ARGV from the app's :allow-abbreviated-options flag so the parser
stays strict by default; see MAKE-APP.")

(defvar *abbreviated-option-entry-cache* nil
  "Per-parse cache for abbreviated long option resolution, keyed by option table.")

(defun resolve-option-entry (table name)
  (gethash (canonical-option-name name) table))

(defun option-entry-spec (entry)
  (getf entry :spec))

(defun option-entry-negated-p (entry)
  (getf entry :negated-p))

(defun %same-option-entry-resolution-p (left right)
  (and (eq (option-key (option-entry-spec left))
           (option-key (option-entry-spec right)))
       (eq (option-entry-negated-p left)
           (option-entry-negated-p right))))

(defun %resolve-abbreviated-long-option-entry-uncached (canonical-name table)
  "Resolve NAME as a unique long-option prefix in TABLE, or signal / return NIL.

Collects every long (multi-character) table key that has NAME as a prefix,
collapsing entries that denote the same option and negation sense. A single
distinct result is returned; several distinct results signal an ambiguity;
no match returns NIL so the caller can report an unknown option."
  (let ((results '()))
    (maphash
     (lambda (key entry)
       (when (and (> (length key) 1)
                  (<= (length canonical-name) (length key))
                  (string= canonical-name key :end2 (length canonical-name)))
         (pushnew entry results :test #'%same-option-entry-resolution-p)))
     table)
    (cond
      ((null results) nil)
      ((null (rest results)) (first results))
      (t
       (signal-cli-error
        'cli-unknown-option
        (format nil "Ambiguous option --~A matches: ~{--~A~^, ~}"
                canonical-name
                (sort (mapcar (lambda (entry) (getf entry :name)) results)
                      #'string<))
        :option canonical-name)))))

(defun %abbreviated-option-cache-for-table (table)
  (when *abbreviated-option-entry-cache*
    (or (gethash table *abbreviated-option-entry-cache*)
        (setf (gethash table *abbreviated-option-entry-cache*)
              (make-hash-table :test #'equal)))))

(defun %abbreviated-long-option-entry (name table)
  (let* ((canonical-name (canonical-option-name name))
         (cache (%abbreviated-option-cache-for-table table)))
    (if cache
        (multiple-value-bind (entry present-p)
            (gethash canonical-name cache)
          (if present-p
              entry
              (setf (gethash canonical-name cache)
                    (%resolve-abbreviated-long-option-entry-uncached canonical-name
                                                                      table))))
        (%resolve-abbreviated-long-option-entry-uncached canonical-name table))))

(defun resolve-long-option-entry (name table specs)
  (or (resolve-option-entry table name)
      (and *allow-abbreviated-options*
           (%abbreviated-long-option-entry name table))
      (signal-cli-error 'cli-unknown-option
                        (unknown-option-message (format nil "--~A" name)
                                                (option-candidate-names specs
                                                                        :long-only-p t))
                        :option name)))

(defun resolve-command-spec (table name)
  (gethash (canonical-name name) table))

(defun short-option-candidates (specs)
  (option-candidate-names specs :short-only-p t))

(defun signal-unknown-short-option (name specs)
  (signal-cli-error 'cli-unknown-option
                    (unknown-option-message (format nil "-~A" name)
                                            (short-option-candidates specs))
                    :option name))
