(in-package :cl-cli)

(defun %wire-exclusive-group (options required-p)
  "Give each option in OPTIONS the others as conflicts and a shared group marker.

Exclusivity is enforced by the same option-relation-graph conflict validation
used for :conflicts-with (including hidden-target-safe error messages).
Conflicts an option already declares are preserved. The shared OPTION-GROUP
lets parsing add the at-least-one obligation when REQUIRED-P, and lets help
render the members as a single choice instead of pairwise conflicts."
  (let ((keys (mapcar #'option-key options))
        (group (%make-option-group :members (mapcar #'option-key options)
                                   :required-p required-p
                                   :mode :exclusive)))
    (dolist (option options)
      (let ((others (remove (option-key option) keys)))
        (setf (option-conflicts-with option)
              (remove-duplicates (append (option-conflicts-with option) others))
              (option-group option) group)))
    (copy-list options)))

(defun inclusive-group (&rest options)
  "Wire OPTIONS as an all-or-none group and return them as a fresh list.

If any member is supplied, every member must be supplied; supplying none is also
fine. Splice the result into :global-options or a command's :options. Unlike
EXCLUSIVE-GROUP this adds no conflicts -- the members are meant to be used
together (for example a paired --host and --port)."
  (let ((group (%make-option-group :members (mapcar #'option-key options)
                                   :required-p nil
                                   :mode :inclusive)))
    (dolist (option options)
      (setf (option-group option) group))
    (copy-list options)))

(defun exclusive-group (&rest options)
  "Wire OPTIONS as a mutually-exclusive group and return them as a fresh list.

At most one option in the group may be supplied on the command line. Splice the
result into :global-options or a command's :options, e.g.

  :global-options (exclusive-group (make-option :name \"json\" :kind :flag)
                                   (make-option :name \"yaml\" :kind :flag)
                                   (make-option :name \"table\" :kind :flag))"
  (%wire-exclusive-group options nil))

(defun required-exclusive-group (&rest options)
  "Wire OPTIONS as an exactly-one group and return them as a fresh list.

Mutual exclusion is enforced exactly as by EXCLUSIVE-GROUP (at most one member).
In addition, parsing signals CLI-MISSING-OPTION-VALUE when none of the members is
supplied, so callers must choose precisely one."
  (%wire-exclusive-group options t))
