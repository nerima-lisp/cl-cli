(in-package :cl-cli)

(defvar *help-color* nil
  "When true, the help printers wrap headings and names in ANSI styling.

Bound by PRINT-APP-HELP / PRINT-COMMAND-HELP / RUN-APP. The :color argument that
sets it accepts T, NIL, or :AUTO; :AUTO resolves via %RESOLVE-HELP-COLOR
(NO_COLOR / CLICOLOR_FORCE / terminal detection) before this variable is bound,
so by the time styling runs the value is always a concrete boolean.")

(defun %ansi (code text)
  (if *help-color*
      (format nil "~C[~Am~A~C[0m" #\Escape code text #\Escape)
      text))

(defun %terminal-safe-text (text)
  "Drop terminal control characters from free-form help metadata."
  (with-output-to-string (out)
    (loop for char across (or text "")
          do (let ((code (char-code char)))
               (cond
                 ((member char '(#\Newline #\Return #\Tab))
                  (write-char #\Space out))
                 ((or (< code 32)
                      (= code 127)
                      (and (>= code 128) (< code 160))))
                 (t (write-char char out)))))))

(defun %style-heading (text)
  (%ansi "1" text))

(defun %style-name (text)
  (%ansi "36" text))

(defun %style-padded-name (text width)
  "Pad TEXT to WIDTH visible columns, then style it, so alignment is preserved."
  (%style-name (format nil "~VA" width text)))

(defvar *help-width* nil
  "When a positive integer, help descriptions are word-wrapped to this column.

Bound by PRINT-APP-HELP / PRINT-COMMAND-HELP / RUN-APP. The :width argument that
sets it accepts a positive integer, NIL, or :AUTO; :AUTO resolves via
%RESOLVE-HELP-WIDTH ($COLUMNS) to a width or NIL before this variable is bound.")

(defparameter +help-description-column+ 27
  "The visible column where a help row's description begins: 2 + 24 + 1.")

(defun %wrap-text (text width)
  "Greedily word-wrap TEXT to WIDTH columns, returning a list of lines."
  (let ((words (remove-if (lambda (w) (zerop (length w)))
                          (uiop:split-string text
                                             :separator '(#\Space #\Tab #\Newline))))
        (current ""))
    (collecting
      (dolist (word words)
        (cond
          ((zerop (length current)) (setf current word))
          ((<= (+ (length current) 1 (length word)) width)
           (setf current (concatenate 'string current " " word)))
          (t (collect current)
             (setf current word))))
      (when (plusp (length current))
        (collect current)))))

(defun %group-by-key (items key-fn)
  "Group ITEMS by (KEY-FN item) into ((key . items-in-that-group) ...).

Keys appear in first-seen order; an item whose key is NIL is excluded (it
belongs to whatever ungrouped bucket the caller tracks separately)."
  (let ((order nil)
        (table (make-hash-table :test #'equal)))
    (dolist (item items)
      (let ((key (funcall key-fn item)))
        (when key
          (unless (nth-value 1 (gethash key table))
            (setf (gethash key table) nil)
            (push key order))
          (push item (gethash key table)))))
    (mapcar (lambda (key) (cons key (nreverse (gethash key table))))
            (nreverse order))))

(defun %emit-help-row (stream padded-name description)
  "Emit a `  NAME  DESCRIPTION` row, word-wrapping DESCRIPTION under *HELP-WIDTH*."
  (let ((width *help-width*)
        (description (%terminal-safe-text description)))
    (if (and width
             (integerp width)
             (plusp (length description))
             (> width (+ +help-description-column+ 8)))
        (let ((lines (%wrap-text description
                                 (- width +help-description-column+))))
          (format stream "  ~A ~A~%" padded-name (or (first lines) ""))
          (dolist (line (rest lines))
            (format stream "~A~A~%"
                    (make-string +help-description-column+ :initial-element #\Space)
                    line)))
        (format stream "  ~A ~A~%" padded-name description))))
