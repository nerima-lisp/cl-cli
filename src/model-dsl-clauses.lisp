(in-package :cl-cli)

(defun %option-clause-form (clause)
  (destructuring-bind (name &rest args) clause
    `(make-option :name ,name ,@args)))

(defun %positional-clause-form (clause)
  (destructuring-bind (key &rest args) clause
    `(make-positional :key ,key ,@args)))

(defun %command-clause-form (clause)
  (destructuring-bind (name (&rest args) &body nested-clauses) clause
    (multiple-value-bind (option-forms positional-forms command-source-forms)
        (%command-clause-forms nested-clauses)
      `(list (make-command :name ,name ,@args
                           :options (list ,@option-forms)
                           :positionals (list ,@positional-forms)
                           :subcommands (append ,@command-source-forms))))))

(defun %classify-command-clause (clause)
  (unless (and (consp clause) (keywordp (first clause)))
    (error "DEFINE-APP/DEFINE-COMMAND clause must be a list headed by ~
               :OPTION, :POSITIONAL, :COMMAND, or :COMMANDS-FROM, got ~S."
           clause))
  (destructuring-bind (head &rest rest) clause
    (ecase head
      (:option (values :option (%option-clause-form rest)))
      (:positional (values :positional (%positional-clause-form rest)))
      (:command (values :command-source (%command-clause-form rest)))
      (:commands-from
       (unless (= (length rest) 1)
         (error ":COMMANDS-FROM requires exactly one list-valued form, got ~S."
                clause))
       (values :command-source (first rest))))))

(defun %command-clause-forms (clauses)
  "Partition CLAUSES into option, positional, and command-source forms."
  (let (options positionals command-sources)
    (dolist (clause clauses)
      (multiple-value-bind (bucket form)
          (%classify-command-clause clause)
        (ecase bucket
          (:option (push form options))
          (:positional (push form positionals))
          (:command-source (push form command-sources)))))
    (values (nreverse options) (nreverse positionals) (nreverse command-sources))))

(defun %validate-dsl-extra-args (constructor extra-args reserved-keys)
  (unless (evenp (length extra-args))
    (error "~S arguments must be keyword/value pairs, got ~S."
           constructor extra-args))
  (loop for tail on extra-args by #'cddr
        for key = (first tail)
        do (unless (keywordp key)
             (error "~S arguments must use keyword keys, got ~S."
                    constructor key))
           (when (member key reserved-keys)
             (error "~S supplies ~S itself; do not repeat it in the DSL arguments."
                    constructor key))))

(defun %clause-spec-form (constructor extra-args clauses options-key
                          positionals-key commands-key)
  (%validate-dsl-extra-args constructor extra-args
                            (list options-key positionals-key commands-key))
  (multiple-value-bind (option-forms positional-forms command-source-forms)
      (%command-clause-forms clauses)
    `(,constructor ,@extra-args
                   ,options-key (list ,@option-forms)
                   ,positionals-key (list ,@positional-forms)
                   ,commands-key (append ,@command-source-forms))))
