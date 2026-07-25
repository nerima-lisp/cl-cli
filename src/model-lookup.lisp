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

(defun resolve-related-option-spec (specs target)
  (%lookup-option-target (%option-target-table specs) target))
