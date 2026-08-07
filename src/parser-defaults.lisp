(in-package :cl-cli)

(defparameter *environment-variable-reader*
  #+sbcl #'host-kit:getenv
  #-sbcl #'uiop:getenv)

(defvar *option-config-values* nil
  "A plist of option-key -> value consulted for option defaults.

Bound by PARSE-ARGV / RUN-APP from their :CONFIG argument, this lets a caller
supply values from a loaded configuration file. It sits below CLI arguments and
environment variables but above literal :default in the precedence chain, so an
explicit CLI value or environment variable still wins. Values are coerced the
same way literal defaults are (a string is run through the option parser, a list
is spread, a delimited option splits a string value).")

(defparameter *config-absent-sentinel* (list :config-absent)
  "A unique object returned by GETF when a config key is truly absent.

A fresh list is EQ only to itself, so this distinguishes \"no config entry\"
from a legitimate config value of NIL (or any keyword).")

(defun option-config-value (spec)
  "Return (VALUES config-value present-p) for SPEC from *OPTION-CONFIG-VALUES*."
  (let ((value (getf *option-config-values* (option-key spec) *config-absent-sentinel*)))
    (if (eq value *config-absent-sentinel*)
        (values nil nil)
        (values value t))))

(defun option-environment-value (spec)
  (loop for env-var in (option-env-vars spec)
        for raw-value = (funcall *environment-variable-reader* env-var)
        when raw-value
          do (return (values raw-value t))
        finally (return (values nil nil))))

(defun coerce-option-default-value (spec raw-value)
  (if (stringp raw-value)
      (parse-option-value spec raw-value)
      raw-value))

(defun coerce-positional-default-value (spec raw-value)
  (if (stringp raw-value)
      (parse-positional-value spec raw-value)
      raw-value))

(defun positional-default-values (spec)
  (let ((default (positional-default spec)))
    (cond
      ((null default) nil)
      ((listp default)
       (mapcar (lambda (value)
                 (coerce-positional-default-value spec value))
               default))
      (t
       (list (coerce-positional-default-value spec default))))))

(defun positional-default-value (spec)
  (coerce-positional-default-value spec (positional-default spec)))

(defun %option-delimited-p (spec)
  (and (typep spec 'option-spec)
       (option-value-delimiter spec)))

(defun %resolved-default-pieces (spec raw)
  "Split a resolved default/config value RAW into the pieces to store for SPEC.

Delimited: a list stays, a string splits on the delimiter, NIL is empty.
Repeatable: a list stays, else a one-element list. Otherwise a one-element list
(so a scalar -- including NIL -- is stored once)."
  (cond
    ((%option-delimited-p spec)
     (cond
       ((null raw) nil)
       ((listp raw) raw)
       ((stringp raw) (split-delimited-value raw (option-value-delimiter spec)))
       (t (list raw))))
    ((option-multiple-p spec)
     (if (listp raw) raw (list raw)))
    (t (list raw))))

(defun %make-option-fallback-plan (source raw-value apply-mode)
  (list :source source
        :raw-value raw-value
        :apply-mode apply-mode))

(defun resolve-option-fallback-plan (spec)
  "Return a fallback application plan for SPEC, or NIL when none is present.

The returned plist records both provenance and how the raw value must be
applied:

- `:PARSED-ENV` parses one environment string like a CLI value.
- `:DELIMITED-ENV` splits one environment string like a delimited CLI value.
- `:RESOLVED-DEFAULT` applies config/default coercion semantics."
  (multiple-value-bind (raw-env-value env-present-p)
      (option-environment-value spec)
    (multiple-value-bind (config-value config-present-p)
        (option-config-value spec)
      (cond
        ((and env-present-p (%option-delimited-p spec))
         (%make-option-fallback-plan :env raw-env-value :delimited-env))
        (env-present-p
         (%make-option-fallback-plan :env raw-env-value :parsed-env))
        (config-present-p
         (%make-option-fallback-plan :config config-value :resolved-default))
        ((option-default-present-p spec)
         (%make-option-fallback-plan :default (option-default spec)
                                     :resolved-default))
        (t nil)))))

(defun apply-resolved-default (values spec raw)
  "Store RAW as SPEC's value using default coercion semantics.

A string piece is run through the option parser; a non-string is stored as-is.
A delimited option always accumulates its pieces into a list; a repeatable
option accumulates too; otherwise the single value is stored directly. This is
shared by both literal :default and :config resolution so they behave alike."
  (let ((append-p (%option-delimited-p spec)))
    (dolist (piece (%resolved-default-pieces spec raw) values)
      (let ((coerced (coerce-option-default-value spec piece)))
        (setf values (if append-p
                         (%append-option-value values spec coerced)
                         (store-option-value values spec coerced)))))))

(defun apply-option-fallback-plan (values spec plan)
  (%record-option-source spec (getf plan :source))
  (case (getf plan :apply-mode)
    (:delimited-env
     (store-delimited-option-value values spec (getf plan :raw-value)))
    (:parsed-env
     (store-option-value values spec
                         (parse-option-value spec (getf plan :raw-value))))
    (t
     (apply-resolved-default values spec (getf plan :raw-value)))))

(defun apply-option-defaults (values specs)
  (dolist (spec specs values)
    (unless (plist-has-key-p values (option-key spec))
      (let ((plan (resolve-option-fallback-plan spec)))
        (when plan
          ;; Precedence below an explicit CLI value: env var, then :config,
          ;; then literal :default. A delimited env value is split the same way
          ;; a CLI value would be, so `TAGS=a,b,c` matches `--tags a,b,c`.
          (setf values (apply-option-fallback-plan values spec plan)))))))
