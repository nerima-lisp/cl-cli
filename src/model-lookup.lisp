(in-package :cl-cli)

(defun %option-display-name (spec)
  (option-token-display-name (first (option-names spec))))

(defun %option-key-table (specs)
  (let ((table (make-hash-table :test #'eq)))
    (dolist (spec specs table)
      (setf (gethash (option-key spec) table) spec))))

(defun %option-target-table (specs)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (spec specs table)
      (setf (gethash (option-key spec) table) spec)
      (dolist (name (option-names spec))
        (setf (gethash name table) spec)))))

(defun %lookup-option-target (table target)
  (gethash target table))

(defun resolve-related-option-spec (specs target
                                    &optional (target-table (%option-target-table specs)))
  "Resolve TARGET (an option name/key) to its SPECS member via TARGET-TABLE.

TARGET-TABLE defaults to a fresh %OPTION-TARGET-TABLE for standalone callers,
but VALIDATE-OPTION-RELATIONSHIPS-DECLARED passes its own already-built one
down through every :requires/:conflicts-with/etc target it validates -- this
function used to rebuild the whole table from scratch on every single call,
once per declared relation target across every option."
  (%lookup-option-target target-table target))
