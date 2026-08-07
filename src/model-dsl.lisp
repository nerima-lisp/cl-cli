(in-package :cl-cli)

(defmacro %define-leaf-spec-macro (macro-name constructor binding-kind)
  `(defmacro ,macro-name (name &rest spec-args)
     ,(format nil "Declaratively bind NAME to a ~A-SPEC built via ~A.

SPEC-ARGS are passed through verbatim to ~A. This is additive sugar for
reusable ~A specs; the underlying functional API remains independently
usable."
              (string-upcase binding-kind)
              (string-upcase constructor)
              (string-upcase constructor)
              binding-kind)
     `(defparameter ,name
        (,',constructor ,@spec-args))))

(defmacro %define-composite-spec-macro
    (macro-name constructor options-key positionals-key commands-key docstring)
  `(defmacro ,macro-name (name (&rest spec-args) &body clauses)
     ,docstring
     `(defparameter ,name
        ,(%clause-spec-form ',constructor spec-args clauses
                            ,options-key ,positionals-key ,commands-key))))

(%define-leaf-spec-macro define-option make-option "option")
(%define-leaf-spec-macro define-positional make-positional "positional")

(%define-composite-spec-macro
 define-app make-app :global-options :positionals :commands
 "Declaratively bind NAME to an APP-SPEC built via MAKE-APP.

CLAUSES may be headed by :OPTION, :POSITIONAL, :COMMAND, or
:COMMANDS-FROM. A :COMMAND clause recursively accepts the same clause
vocabulary for nested command specs. APP-ARGS are forwarded to MAKE-APP;
this macro supplies :GLOBAL-OPTIONS, :POSITIONALS, and :COMMANDS.")

(%define-composite-spec-macro
 define-command make-command :options :positionals :subcommands
 "Declaratively bind NAME to a COMMAND-SPEC built via MAKE-COMMAND.

CLAUSES use the same vocabulary as DEFINE-APP. COMMAND-ARGS are forwarded
to MAKE-COMMAND; this macro supplies :OPTIONS, :POSITIONALS, and
:SUBCOMMANDS. The bound spec can be reused through :COMMANDS-FROM.")
