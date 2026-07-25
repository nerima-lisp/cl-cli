(in-package :cl-cli)

;;;; The condition hierarchy is the primary integration point for a consumer
;;;; CLI, so it distinguishes two kinds of failure that must not be handled the
;;;; same way:
;;;;
;;;;   CLI-ERROR
;;;;     CLI-USAGE-ERROR ............ the *user* typed something wrong. Print
;;;;                                  the message plus usage and exit non-zero.
;;;;     CLI-INVALID-SPECIFICATION .. the *programmer* declared something wrong.
;;;;                                  A bug in the app spec, surfaced by
;;;;                                  MAKE-APP / MAKE-COMMAND / MAKE-OPTION.
;;;;
;;;; Keeping the second one out of CLI-USAGE-ERROR matters: the idiomatic
;;;; handler is `(handler-case (run-app ...) (cli-usage-error (e) ...))`, and
;;;; if a spec bug landed in that branch the developer's own mistake would be
;;;; swallowed and reported to the end user as a usage message.

(defvar *cli-error-app* nil)
(defvar *cli-error-command* nil)

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message)
   (context-app :initarg :context-app
                :initform nil
                :reader cli-error-app
                :reader cli-usage-error-app)
   (context-command :initarg :context-command
                    :initform nil
                    :reader cli-error-command
                    :reader cli-usage-error-command))
  (:report (lambda (condition stream)
             (format stream "~A" (cli-error-message condition))))
  (:documentation
   "Root of every condition cl-cli signals.

CLI-ERROR-MESSAGE is the human-readable text, already phrased for display.
CLI-ERROR-APP and CLI-ERROR-COMMAND name the app and command in scope when the
error was signaled, so a handler can print the right usage block without
re-deriving where the failure happened; either may be NIL. The
CLI-USAGE-ERROR-APP / -COMMAND readers are the same slots under their original
names."))

(define-condition cli-usage-error (cli-error)
  ()
  (:documentation
   "Superclass of every error caused by what the user typed.

Handle this to catch all of them at once; handle a subtype below to react to
one specific mistake. Signaled directly, with no subtype, for a few failures
that have no more specific class -- see CLI-RESPONSE-FILE-ERROR for the
response-file cases that do."))

(define-condition cli-invalid-specification (cli-error)
  ()
  (:documentation
   "The app specification itself is invalid -- a programmer error, not a user
error.

Signaled while building a spec (unknown relation target, a :requires cycle, a
rest positional that is not last, a reserved option key, and so on), so it
normally surfaces at load time rather than from PARSE-ARGV. Deliberately not a
CLI-USAGE-ERROR: printing usage in response to it would hide a bug."))

(define-condition cli-unknown-option (cli-usage-error)
  ((option :initarg :option :reader cli-unknown-option-name))
  (:documentation
   "An option token matched no declared option. CLI-UNKNOWN-OPTION-NAME is the
token as the user typed it. The message carries a spelling suggestion when a
close declared name exists."))

(define-condition cli-unknown-command (cli-usage-error)
  ((command :initarg :command :reader cli-unknown-command-name))
  (:documentation
   "A command token matched no declared command or alias, or :REQUIRE-COMMAND
was set and none was given. CLI-UNKNOWN-COMMAND-NAME is the offending token,
or NIL when none was supplied."))

(define-condition cli-missing-option-value (cli-usage-error)
  ((option :initarg :option :reader cli-missing-option-value-name))
  (:documentation
   "An option that should have contributed a value did not.

Covers both `--output` typed with nothing after it and a required option never
supplied at all; the latter is the more specific CLI-MISSING-REQUIRED-OPTION
subtype, so a handler can tell them apart while one that does not care still
catches both here. Also signaled when a REQUIRED-EXCLUSIVE-GROUP has no member
and when a :REQUIRED-IF / :REQUIRED-UNLESS condition is unmet.
CLI-MISSING-OPTION-VALUE-NAME is the option key."))

(define-condition cli-missing-required-option (cli-missing-option-value)
  ()
  (:documentation
   "A :REQUIRED-P option was never supplied -- the single most common CLI
mistake there is.

Split out from its parent so a handler can answer \"you forgot --output\"
differently from \"--output needs a value\", which is otherwise the same
condition with a different message."))

(define-condition cli-response-file-error (cli-usage-error)
  ((path :initarg :path :initform nil :reader cli-response-file-error-path))
  (:documentation
   "An @file response-file expansion failed: the file could not be read, the
nesting exceeded +RESPONSE-FILE-MAX-DEPTH+, or the expansion read more than
+RESPONSE-FILE-MAX-TOTAL-BYTES+ in total.

A usage error because the path came from the command line, but worth
distinguishing: \"your @args.txt is missing\" deserves a different message
from \"you mistyped a flag\". CLI-RESPONSE-FILE-ERROR-PATH is the file
involved, when one is known."))

(define-condition cli-missing-dependent-option (cli-usage-error)
  ((option :initarg :option :reader cli-missing-dependent-option-name)
   (dependency :initarg :dependency :reader cli-missing-dependent-option-dependency))
  (:documentation
   "A :REQUIRES relation, or an INCLUSIVE-GROUP, was left unsatisfied.
CLI-MISSING-DEPENDENT-OPTION-NAME is the option the user did supply and
-DEPENDENCY the one it needed."))

(define-condition cli-missing-any-of-options (cli-usage-error)
  ((option :initarg :option :reader cli-missing-any-of-options-name)
   (alternatives :initarg :alternatives :reader cli-missing-any-of-options-alternatives))
  (:documentation
   "A :REQUIRES-ANY-OF relation was left unsatisfied: none of the acceptable
alternatives was supplied. -NAME is the option that imposed the requirement,
-ALTERNATIVES the keys that would each have satisfied it."))

(define-condition cli-conflicting-options (cli-usage-error)
  ((left-option :initarg :left-option :reader cli-conflicting-options-left-option)
   (right-option :initarg :right-option :reader cli-conflicting-options-right-option))
  (:documentation
   "Two options that cannot appear together did, whether declared through
:CONFLICTS-WITH or through an EXCLUSIVE-GROUP. The two readers name the
offending pair; their order reflects declaration order, not the order the user
typed them."))

(define-condition cli-missing-positional (cli-usage-error)
  ((name :initarg :name :reader cli-missing-positional-name))
  (:documentation
   "A required positional argument was not supplied, or a positional with a
:MIN-COUNT received too few values. CLI-MISSING-POSITIONAL-NAME is its display
name."))

(define-condition cli-invalid-option-value (cli-usage-error)
  ((option :initarg :option :reader cli-invalid-option-value-name)
   (value :initarg :value :reader cli-invalid-option-value-value)
   (cause :initarg :cause :reader cli-invalid-option-value-cause))
  (:documentation
   "An option's value was supplied but rejected -- it failed the option's
:TYPE, fell outside :MIN / :MAX, or was not among its :CHOICES.

-NAME is the option key and -VALUE the raw string as typed. -CAUSE is the
underlying condition when a :TYPE coercion or a custom :PARSER signaled one,
and NIL when cl-cli rejected the value itself; it is what to inspect when a
custom parser's own error text matters."))

(define-condition cli-invalid-positional-value (cli-usage-error)
  ((name :initarg :name :reader cli-invalid-positional-value-name)
   (value :initarg :value :reader cli-invalid-positional-value-value)
   (cause :initarg :cause :reader cli-invalid-positional-value-cause))
  (:documentation
   "The positional counterpart of CLI-INVALID-OPTION-VALUE, with the same
three readers; -NAME is the positional's display name."))

(define-condition cli-unexpected-argument (cli-usage-error)
  ((argument :initarg :argument :reader cli-unexpected-argument-name))
  (:documentation
   "A positional value appeared where none could be accepted -- past a rest
positional's :MAX-COUNT, or at all when the app or command declares no
positionals. CLI-UNEXPECTED-ARGUMENT-NAME is the offending token."))

(defun signal-cli-error (type message &rest initargs)
  (apply #'error
         type
         :message message
         :context-app *cli-error-app*
         :context-command *cli-error-command*
         initargs))
