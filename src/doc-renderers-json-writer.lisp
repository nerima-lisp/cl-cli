(in-package :cl-cli)

;;;; Low-level JSON writer primitives shared by document renderers.

(defvar *json-object-first-member-p* "True when no member of the JSON object currently being written via
WITH-JSON-OBJECT has been written yet -- rebound per object (including
nested objects), so JSON-MEMBER knows whether to emit a leading comma.")

(defun %json-write-escaped-string (stream text)
  (write-char #\" stream)
  (loop for char across (or text "")
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (t
              (if (< (char-code char) #x20)
                  (format stream "\\u~4,'0X" (char-code char))
                  (write-char char stream)))))
  (write-char #\" stream))

(defun %json-write-number (stream number)
  "Write NUMBER as a valid JSON numeric token.

Integers print directly; any other real is coerced to a double and printed in
fixed notation so a Lisp exponent marker (`1.5d0`) never leaks into the output."
  (if (integerp number)
      (format stream "~D" number)
      (format stream "~F" (coerce number 'double-float))))

(defun %json-write-bool (stream value)
  (write-string (if value "true" "false") stream))

(defun %json-write-keyword-name (stream keyword)
  (%json-write-escaped-string stream (string-downcase (symbol-name keyword))))

(defun %json-write-array (stream items writer)
  "Write a JSON array to STREAM: '[' then WRITER called as (FUNCALL WRITER
STREAM ITEM) for each of ITEMS, comma-separated, then ']'."
  (write-char #\[ stream)
  (loop for item in items
        for first = t then nil
        do (unless first
             (write-char #\, stream))
           (funcall writer stream item))
  (write-char #\] stream))

(defun %json-write-string-array (stream strings)
  (%json-write-array stream strings #'%json-write-escaped-string))

(defun %json-write-scalar (stream value)
  "Write a Lisp default VALUE as a JSON scalar or array."
  (cond
    ((null value) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((stringp value) (%json-write-escaped-string stream value))
    ((numberp value) (%json-write-number stream value))
    ((listp value) (%json-write-array stream value #'%json-write-scalar))
    (t (%json-write-escaped-string stream (princ-to-string value)))))

(defun %json-write-deprecated (stream deprecated)
  "Write a :deprecated designator as a JSON value, or do nothing (the caller
must have already checked presence) when DEPRECATED is a bare T."
  (if (stringp deprecated)
      (%json-write-escaped-string stream deprecated)
      (write-string "true" stream)))

(defmacro with-json-object ((stream) &body body)
  "Write a JSON object to STREAM: BODY should call JSON-MEMBER for each
potential key. Handles the leading brace, trailing brace, and the
leading-comma-before-every-member-after-the-first bookkeeping, so each
JSON-MEMBER call only needs to decide whether it has a value at all."
  `(progn
     (write-char #\{ ,stream)
     (let ((*json-object-first-member-p* t))
       ,@body)
     (write-char #\} ,stream)))

(defun json-member (stream key present-p writer)
  "Write \"KEY\":<value> to STREAM via (FUNCALL WRITER) when PRESENT-P is
true, with a leading comma if this isn't the first member written inside the
enclosing WITH-JSON-OBJECT. WRITER receives no arguments -- it closes over
STREAM and whatever value it needs to write, matching every call site's
existing style of computing its own value expression inline."
  (when present-p
    (unless *json-object-first-member-p*
      (write-char #\, stream))
    (setf *json-object-first-member-p* nil)
    (%json-write-escaped-string stream key)
    (write-char #\: stream)
    (funcall writer)))

(defmacro json-member-call (stream key present-p writer &rest args)
  "Write KEY when PRESENT-P by calling WRITER as (WRITER STREAM . ARGS)."
  `(json-member
    ,stream
    ,key
    ,present-p
    (lambda ()
      (,writer ,stream ,@args))))

(defmacro json-required-member-call (stream key writer &rest args)
  "Like JSON-MEMBER-CALL, but always emits the member."
  `(json-member-call ,stream ,key t ,writer ,@args))

(defmacro json-optional-member (stream key writer value-form &optional present-form)
  "Write KEY from VALUE-FORM when PRESENT-FORM is true.

When PRESENT-FORM is omitted, the bound VALUE-FORM itself decides presence, so
callers can spell a getter once and keep the presence test next to it."
  (let ((value (gensym "VALUE")))
    `(let ((,value ,value-form))
       (json-member-call
        ,stream
        ,key
        ,(or present-form value)
        ,writer
        ,value))))

(defmacro json-required-member (stream key writer value-form)
  "Write KEY from VALUE-FORM unconditionally, evaluating VALUE-FORM once."
  (let ((value (gensym "VALUE")))
    `(let ((,value ,value-form))
       (json-required-member-call
        ,stream
        ,key
        ,writer
        ,value))))
