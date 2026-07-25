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

(defun %command-clause-forms (clauses)
  "Partition CLAUSES into (values option-forms positional-forms
command-source-forms), each a list of constructor-call forms in original
order.

Each clause is headed by :OPTION, :POSITIONAL, :COMMAND, or :COMMANDS-FROM.
OPTION-FORMS and POSITIONAL-FORMS each evaluate to one spec. COMMAND-SOURCE-
FORMS each evaluate to a LIST of command specs -- a :COMMAND clause wraps its
MAKE-COMMAND call in a one-element list, and :COMMANDS-FROM splices in an
arbitrary already-list-valued form (MAKE-STANDARD-COMMANDS, a shared command
list, etc.) -- so every source combines uniformly via APPEND."
  (let (options positionals command-sources)
    (dolist (clause clauses)
      (unless (and (consp clause) (keywordp (first clause)))
        (error "DEFINE-APP/DEFINE-COMMAND clause must be a list headed by ~
               :OPTION, :POSITIONAL, :COMMAND, or :COMMANDS-FROM, got ~S."
               clause))
      (destructuring-bind (head &rest rest) clause
        (ecase head
          (:option (push (%option-clause-form rest) options))
          (:positional (push (%positional-clause-form rest) positionals))
          (:command (push (%command-clause-form rest) command-sources))
          (:commands-from (push (first rest) command-sources)))))
    (values (nreverse options) (nreverse positionals) (nreverse command-sources))))

(defun %clause-spec-form (constructor extra-args clauses options-key
                          positionals-key commands-key)
  (multiple-value-bind (option-forms positional-forms command-source-forms)
      (%command-clause-forms clauses)
    `(,constructor ,@extra-args
                   ,options-key (list ,@option-forms)
                   ,positionals-key (list ,@positional-forms)
                   ,commands-key (append ,@command-source-forms))))

(defmacro define-app (name (&rest app-args) &body clauses)
  "Declaratively bind NAME to an APP-SPEC built via MAKE-APP.

Each entry in CLAUSES is a list headed by :OPTION, :POSITIONAL, :COMMAND, or
:COMMANDS-FROM (see %COMMAND-CLAUSE-FORMS); a :COMMAND clause has the shape
`(:command NAME-FORM (COMMAND-ARGS...) CLAUSE...)` and recursively accepts
the same clause vocabulary for that command's own options, positionals, and
subcommands. APP-ARGS are passed through verbatim to MAKE-APP (:NAME,
:SUMMARY, :DEFAULT-COMMAND, :HANDLER, etc.) -- this macro supplies the
:GLOBAL-OPTIONS/:POSITIONALS/:COMMANDS keys itself, so APP-ARGS must not
repeat them.

Purely additive sugar over the existing functional API: MAKE-APP,
MAKE-COMMAND, MAKE-OPTION, and MAKE-POSITIONAL are unchanged and remain
independently usable without this macro.

Example:

  (define-app *cl-cc*
      (:name \"cl-cc\" :summary \"Compiler-oriented CLI.\")
    (:option \"verbose\" :short #\\v :kind :flag)
    (:positional :script-argv :rest-p t)
    (:commands-from (make-standard-commands :include-completion-p t))
    (:command \"compile\" (:aliases '(\"build\"))
      (:option \"output\" :short #\\o :kind :value)
      (:positional :input :required-p t)))"
  `(defparameter ,name
     ,(%clause-spec-form 'make-app app-args clauses
                         :global-options :positionals :commands)))

(defmacro define-command (name (&rest command-args) &body clauses)
  "Declaratively bind NAME to a COMMAND-SPEC built via MAKE-COMMAND.

Same clause vocabulary as DEFINE-APP (see %COMMAND-CLAUSE-FORMS): :OPTION,
:POSITIONAL, :COMMAND (for a subcommand), and :COMMANDS-FROM. COMMAND-ARGS
are passed through verbatim to MAKE-COMMAND (:NAME, :DESCRIPTION, :ALIASES,
:HANDLER, etc.) -- this macro supplies the :OPTIONS/:POSITIONALS/:SUBCOMMANDS
keys itself, so COMMAND-ARGS must not repeat them.

The bound COMMAND-SPEC is independently reusable -- README's \"reusable app,
command, option, and positional specs\" -- so it can be spliced into more
than one DEFINE-APP via a `(:commands-from (list NAME))` clause."
  `(defparameter ,name
     ,(%clause-spec-form 'make-command command-args clauses
                         :options :positionals :subcommands)))
