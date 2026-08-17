(in-package :cl-cli/test)

(defun find-related-option-spec (specs target)
  (or (and (symbolp target)
           (find target specs :key #'option-key :test #'eq))
      (and (stringp target)
           (find-if (lambda (spec)
                      (member target (option-names spec) :test #'string=))
                    specs))))

(defun assert-prolog-fact (rulebase fact)
  (query-prolog rulebase (list 'assertz fact))
  rulebase)

(defun make-option-relations-rulebase (options)
  (let ((rulebase (make-rulebase)))
    (dolist (spec options)
      (assert-prolog-fact rulebase `(option ,(option-key spec)))
      (when (option-hidden-p spec)
        (assert-prolog-fact rulebase `(hidden ,(option-key spec))))
      (dolist (target (option-requires spec))
        (let ((resolved (find-related-option-spec options target)))
          (when resolved
            (assert-prolog-fact rulebase
                                `(requires ,(option-key spec)
                                           ,(option-key resolved))))))
      (dolist (target (option-conflicts-with spec))
        (let ((resolved (find-related-option-spec options target)))
          (when resolved
            (assert-prolog-fact rulebase
                                `(conflicts ,(option-key spec)
                                            ,(option-key resolved)))))))
    rulebase))

(defparameter *prolog-atom-package* (find-package :cl-cli/test)
  "Fixed package for interning Prolog atoms.

Predicate and atom identity in cl-prolog-kit is symbol identity, so facts must be
interned into the same package the query literals in the test files are read
into (CL-CLI/TESTS). Interning into the volatile *PACKAGE* makes rulebases
non-reproducible: under the CL-USER runtime the suite uses, derived predicates
would land in the wrong package and the engine would raise EXISTENCE_ERROR.")

(defun prolog-atom (value)
  (etypecase value
    (keyword (intern (symbol-name value) *prolog-atom-package*))
    (symbol (intern (string-upcase (symbol-name value)) *prolog-atom-package*))
    (string (intern (string-upcase value) *prolog-atom-package*))
    (integer value)))

(defun prolog-fact (&rest term)
  (cl-prolog-kit:make-clause term))

(defun option-atom (option)
  (prolog-atom (option-key option)))

(defun positional-atom (positional)
  (prolog-atom (positional-key positional)))

(defun option-clauses (scope-name app-name option &optional command-name)
  (let ((option-name (option-atom option))
        (kind (prolog-atom (option-kind option)))
        (clauses '()))
    (labels ((fact (&rest term)
               (push (apply #'prolog-fact term) clauses)))
      (if command-name
          (fact scope-name app-name command-name option-name)
          (fact scope-name app-name option-name))
      (if command-name
          (fact (prolog-atom (format nil "~A-KIND" scope-name))
                app-name command-name option-name kind)
          (fact (prolog-atom (format nil "~A-KIND" scope-name))
                app-name option-name kind))
      (when (option-required-p option)
        (if command-name
            (fact (prolog-atom (format nil "~A-REQUIRED" scope-name))
                  app-name command-name option-name)
            (fact (prolog-atom (format nil "~A-REQUIRED" scope-name))
                  app-name option-name)))
      (when (option-stop-parsing-p option)
        (if command-name
            (fact (prolog-atom (format nil "~A-STOP-PARSING" scope-name))
                  app-name command-name option-name)
            (fact (prolog-atom (format nil "~A-STOP-PARSING" scope-name))
                  app-name option-name)))
      (dolist (env-var (option-env-vars option))
        (if command-name
            (fact (prolog-atom (format nil "~A-ENV-VAR" scope-name))
                  app-name command-name option-name (prolog-atom env-var))
            (fact (prolog-atom (format nil "~A-ENV-VAR" scope-name))
                  app-name option-name (prolog-atom env-var))))
      (dolist (choice (option-choices option))
        (if command-name
            (fact (prolog-atom (format nil "~A-CHOICE" scope-name))
                  app-name command-name option-name (prolog-atom choice))
            (fact (prolog-atom (format nil "~A-CHOICE" scope-name))
                  app-name option-name (prolog-atom choice))))
      (dolist (dependency (option-requires option))
        (if command-name
            (fact (prolog-atom (format nil "~A-REQUIRES" scope-name))
                  app-name command-name option-name (prolog-atom dependency))
            (fact (prolog-atom (format nil "~A-REQUIRES" scope-name))
                  app-name option-name (prolog-atom dependency)))))
    (nreverse clauses)))

(defun positional-clauses (scope-name app-name positional &optional command-name)
  (let ((positional-name (positional-atom positional))
        (clauses '()))
    (labels ((fact (&rest term)
               (push (apply #'prolog-fact term) clauses)))
      (if command-name
          (fact scope-name app-name command-name positional-name)
          (fact scope-name app-name positional-name))
      (when (positional-required-p positional)
        (if command-name
            (fact (prolog-atom (format nil "~A-REQUIRED" scope-name))
                  app-name command-name positional-name)
            (fact (prolog-atom (format nil "~A-REQUIRED" scope-name))
                  app-name positional-name)))
      (when (positional-rest-p positional)
        (if command-name
            (fact (prolog-atom (format nil "~A-REST" scope-name))
                  app-name command-name positional-name)
            (fact (prolog-atom (format nil "~A-REST" scope-name))
                  app-name positional-name))))
    (nreverse clauses)))

(defun app->prolog-clauses (app)
  (let ((app-name (prolog-atom (app-name app)))
        (clauses '()))
    (labels ((collect (new-clauses)
               (setf clauses (nconc clauses new-clauses)))
             (fact (&rest term)
               (push (apply #'prolog-fact term) clauses)))
      (fact 'app app-name)
      (when (app-default-command app)
        (fact 'default-command
              app-name
              (prolog-atom (app-default-command app))))
      (dolist (option (app-global-options app))
        (collect (option-clauses 'global-option app-name option)))
      (dolist (positional (app-positionals app))
        (collect (positional-clauses 'app-positional app-name positional)))
      (dolist (command (app-commands app))
        (let ((command-name (prolog-atom (command-name command))))
          (fact 'command app-name command-name)
          (dolist (alias (command-aliases command))
            (fact 'command-alias app-name command-name (prolog-atom alias)))
          (dolist (option (command-options command))
            (collect (option-clauses 'command-option app-name option command-name)))
          (dolist (positional (command-positionals command))
            (collect (positional-clauses
                      'command-positional
                      app-name
                      positional
                      command-name))))))
    clauses))

(defparameter *consumer-migration-contract-predicates*
  '((app 1)
    (default-command 2)
    (command 2)
    (command-alias 3)
    (global-option 2)
    (global-option-kind 3)
    (global-option-required 2)
    (global-option-stop-parsing 2)
    (global-option-env-var 3)
    (global-option-choice 3)
    (global-option-requires 3)
    (app-positional 2)
    (app-positional-required 2)
    (app-positional-rest 2)
    (command-option 3)
    (command-option-kind 4)
    (command-option-required 3)
    (command-option-stop-parsing 3)
    (command-option-env-var 4)
    (command-option-choice 4)
    (command-option-requires 4)
    (command-positional 3)
    (command-positional-required 3)
    (command-positional-rest 3))
  "The full (predicate . arity) vocabulary the consumer-migration contracts query.

Kept as an explicit list so the contract surface is documented in one place and
so absent facts fail cleanly instead of raising cl-prolog-kit's existence_error.")

(defun consumer-migration-schema-clauses ()
  "Declare every contract predicate with a never-succeeding guard clause.

cl-prolog-kit raises the ISO existence_error(procedure, Name/Arity) for a query
whose predicate has no clauses at all. A :fails contract such as
\"nshell script stays optional\" (app-positional-required has zero facts when no
positional is required) would therefore error instead of failing. Seeding a
`Head :- fail.' guard per predicate makes each one known-but-empty, which
mirrors how src/option-relations.lisp declares :requires/:conflicts. The guard
adds no solutions, so :succeeds and :set contracts are unaffected."
  (loop for (name arity) in *consumer-migration-contract-predicates*
        collect (cl-prolog-kit:make-clause
                 (cons (prolog-atom (symbol-name name))
                       (loop for index below arity
                             collect (intern (format nil "?G~D" index)
                                             *prolog-atom-package*)))
                 (list (list 'cl-prolog-kit:fail)))))

(defun consumer-migration-rulebase ()
  (cl-prolog-kit:make-rulebase
   :clauses
   (append (consumer-migration-schema-clauses)
           (mapcan #'app->prolog-clauses
                   (list (cl-cli/examples:make-cl-cc-app)
                         (cl-cli/examples:make-cl-tmux-app)
                         (cl-cli/examples:make-private-trade-fx-app)
                         (cl-cli/examples:make-nshell-app))))))
