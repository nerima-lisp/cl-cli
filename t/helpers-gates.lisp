(in-package :cl-cli/test)

;;;; ---------------------------------------------------------------------
;;;; Implementation gating
;;;;
;;;; cl-cli itself is portable Common Lisp over UIOP, and the bulk of this
;;;; suite runs unchanged on every implementation. The parser fuzz suite
;;;; needs a harness capability cl-weave only wires up on some
;;;; implementations; its gate is a predicate on that capability rather than
;;;; an implementation name, so it cannot silently hide a cl-cli bug.

(defun harness-timeout-available-p ()
  "True when cl-weave can enforce the per-case timeout IT-FUZZ requires.

cl-weave registers its :TIMEOUT platform capability only where it has an
implementation-specific way to interrupt a running case; elsewhere IT-FUZZ
signals PLATFORM-CAPABILITY-UNAVAILABLE before any cl-cli code runs, which
would read as a cl-cli parser failure. Probing cl-weave's own capability list
rather than testing for an implementation by name means the gate opens by
itself if cl-weave gains the capability somewhere new."
  (let ((probe (find-symbol "PLATFORM-CAPABILITY-AVAILABLE-P" "CL-WEAVE")))
    (and probe (funcall probe :timeout) t)))
