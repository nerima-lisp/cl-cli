(in-package :cl-cli)

(defun %consume-option-token-step (token validated-specs table values action remaining)
  "Interpret CONSUME-ARGUMENT-OPTION-TOKEN's result as a scan step.

Returns (values status new-values new-remaining new-action), where STATUS is
one of :UNCONSUMED, :DONE, or :CONTINUE."
  (multiple-value-bind (new-values new-remaining new-action done-p consumed-p)
      (consume-argument-option-token token validated-specs table values action
                                     remaining)
    (values (cond
              ((not consumed-p) :unconsumed)
              (done-p :done)
              (t :continue))
            (if consumed-p new-values values)
            (if consumed-p new-remaining remaining)
            (if consumed-p new-action action))))
