(in-package :cl-cli)

(defstruct (option-relation-graph
            (:conc-name "OPTION-RELATION-GRAPH-")
            (:constructor %make-option-relation-graph))
  "The :requires/:requires-any-of/:conflicts-with adjacency for one spec set.

REQUIRES and REQUIRES-ANY hold each option's directly-declared targets, in
declaration order, keyed by OPTION-KEY. CONFLICTS is symmetric: declaring
A :conflicts-with B populates both A's and B's entries. TRANSITIVE-REQUIRES is
the full :requires closure per key, computed once at construction time so
parse-time lookups (TRANSITIVE-REQUIRED-OPTION-KEYS) are a plain hash read
instead of a graph walk on every PARSE-ARGV."
  (requires (make-hash-table :test #'eq))
  (requires-any (make-hash-table :test #'eq))
  (conflicts (make-hash-table :test #'eq))
  (transitive-requires (make-hash-table :test #'eq)))

(defun %relation-graph-transitive-requires (graph root)
  (let ((seen (make-hash-table :test #'eq)))
    (collecting
      (labels ((visit (key)
                 (dolist (dependency (gethash key (option-relation-graph-requires graph)))
                   (unless (gethash dependency seen)
                     (setf (gethash dependency seen) t)
                     (collect dependency)
                     (visit dependency)))))
        (visit root)))))

(defun make-option-relation-graph (specs &optional (spec-by-target (%option-target-table specs)))
  "Build the requires/requires-any/conflicts adjacency for SPECS.

Cycles are rejected by OPTION-REQUIREMENT-CYCLE-P before this is ever called,
so the transitive walk below never needs cycle protection of its own.

SPEC-BY-TARGET defaults to a fresh %OPTION-TARGET-TABLE for standalone
callers; VALIDATE-OPTION-RELATION-GRAPH passes its own already-built one so
the same specs list isn't hashed twice in one validation pass."
  (let ((graph (%make-option-relation-graph)))
    (flet ((resolved-keys (targets)
             (mapcar (lambda (target)
                       (option-key (%lookup-option-target spec-by-target target)))
                     targets)))
      (dolist (spec specs)
        (let ((key (option-key spec)))
          (setf (gethash key (option-relation-graph-requires graph))
                (resolved-keys (option-requires spec)))
          (setf (gethash key (option-relation-graph-requires-any graph))
                (resolved-keys (option-requires-any-of spec)))
          (dolist (other-key (resolved-keys (option-conflicts-with spec)))
            (pushnew other-key (gethash key (option-relation-graph-conflicts graph)))
            (pushnew key (gethash other-key (option-relation-graph-conflicts graph)))))))
    (dolist (spec specs graph)
      (setf (gethash (option-key spec) (option-relation-graph-transitive-requires graph))
            (%relation-graph-transitive-requires graph (option-key spec))))))

(defun option-requirement-cycle-p (specs &optional (spec-by-target (%option-target-table specs)))
  (let ((visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((visit (spec)
               (let ((key (option-key spec)))
                 (cond
                   ((gethash key visiting) t)
                   ((gethash key visited) nil)
                   (t
                    (setf (gethash key visiting) t)
                     (prog1
                         (some (lambda (target)
                                 (visit (%lookup-option-target spec-by-target target)))
                               (option-requires spec))
                      (remhash key visiting)
                      (setf (gethash key visited) t)))))))
      (some #'visit specs))))

(defun %requires-any-of-unsatisfiable-p (spec spec-by-target graph)
  "True when every one of SPEC's :REQUIRES-ANY-OF alternatives conflicts with it.

If so, SPEC could never be validly supplied: alone it fails the any-of
requirement, and paired with any alternative it fails a :conflicts check."
  (let ((alternatives (option-requires-any-of spec)))
    (and alternatives
         (every (lambda (target)
                  (let ((other (%lookup-option-target spec-by-target target)))
                    (member (option-key other)
                            (gethash (option-key spec)
                                     (option-relation-graph-conflicts graph)))))
                alternatives))))

(defun %relation-graph-conflicting-closure-p (graph keys)
  "True when some KEY's reachable :requires closure (itself included) contains
two options that conflict with each other."
  (some (lambda (root)
          (let ((reachable (cons root (transitive-required-option-keys graph root))))
            (some (lambda (left)
                    (some (lambda (right)
                            (member right (gethash left (option-relation-graph-conflicts graph))))
                          reachable))
                  reachable)))
        keys))

(defun validate-option-relation-graph (specs
                                       &optional (spec-by-target
                                                  (%option-target-table specs)))
  "Validate SPECS' :requires/:conflicts graph and return (values specs graph).

The graph built here to check for conflicting closures is exactly the one
parse-time validation needs again for transitive :requires lookups. Returning
it lets callers cache it on the app/command spec instead of rebuilding an
equivalent graph from scratch on every PARSE-ARGV call. SPEC-BY-TARGET
defaults to a fresh table for standalone callers, but
VALIDATE-OPTION-RELATIONSHIPS-DECLARED passes its own already-built one."
  (when (option-requirement-cycle-p specs spec-by-target)
    (signal-cli-error 'cli-invalid-specification
                      "Option requirements must not contain a cycle."))
  (let ((graph (make-option-relation-graph specs spec-by-target)))
    (when (%relation-graph-conflicting-closure-p graph (mapcar #'option-key specs))
      (signal-cli-error
       'cli-invalid-specification
       "An option requirement closure contains conflicting options."))
    (dolist (spec specs)
      (when (%requires-any-of-unsatisfiable-p spec spec-by-target graph)
        (signal-cli-error
         'cli-invalid-specification
         (format nil "Option ~A's :requires-any-of alternatives all conflict with it, ~
                      so it could never be satisfied."
                 (%option-display-name spec)))))
    (values specs graph)))

(defun transitive-required-option-keys (graph option-key)
  (gethash option-key (option-relation-graph-transitive-requires graph)))

(defun any-of-required-option-keys (graph option-key)
  "Return OPTION-KEY's declared :REQUIRES-ANY-OF alternatives, or NIL.

Unlike :REQUIRES (an AND of individually-mandatory dependencies), satisfying
any single alternative here is sufficient -- callers check presence of at
least one of the returned keys, they do not walk a transitive closure."
  (gethash option-key (option-relation-graph-requires-any graph)))

(defun validate-option-relationships-declared (specs)
  ;; Most CLIs declare no option relations at all -- skip building the
  ;; target-lookup table and the (otherwise unconditional)
  ;; cycle-check/graph-population/conflicting-closure work entirely when
  ;; there is nothing to validate, mirroring the same early-exit already
  ;; applied to each parse-time relation validator
  ;; (src/parser-relation-validation.lisp). A trivial empty graph is a
  ;; correct cache value here: VALIDATE-OPTION-RELATIONSHIPS (the parse-time
  ;; consumer) never even looks at the cached graph when specs declare no
  ;; :requires/:requires-any-of/:conflicts-with, so building a real one here
  ;; for that case is pure waste on every single MAKE-APP call.
  (unless (some (lambda (spec)
                  (or (option-requires spec)
                      (option-requires-any-of spec)
                      (option-required-if spec)
                      (option-required-unless spec)
                      (option-conflicts-with spec)))
                specs)
    (return-from validate-option-relationships-declared
      (values specs (%make-option-relation-graph))))
  (let ((target-table (%option-target-table specs)))
    (dolist (spec specs)
      (%validate-related-option-targets specs spec "requires" (option-requires spec)
                                        target-table)
      (%validate-related-option-targets specs spec "requires-any-of"
                                        (option-requires-any-of spec) target-table)
      (%validate-related-option-targets specs spec "required-if"
                                        (option-required-if spec) target-table)
      (%validate-related-option-targets specs spec "required-unless"
                                        (option-required-unless spec) target-table)
      (%validate-related-option-targets specs spec "conflicts-with"
                                        (option-conflicts-with spec) target-table))
    (validate-option-relation-graph specs target-table)))

(defun %validate-related-option-targets
    (specs spec relation targets &optional (target-table (%option-target-table specs)))
  (dolist (target targets)
    (%validate-related-option-target specs spec target relation target-table)))

(defun %validate-related-option-target
    (specs spec target relation &optional (target-table (%option-target-table specs)))
  (let ((resolved (resolve-related-option-spec specs target target-table)))
    (unless resolved
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Unknown option in ~A for ~A: ~A"
                                relation
                                (%option-display-name spec)
                                (option-relation-target-display-name target))))
    (when (eq (option-key resolved) (option-key spec))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Option ~A cannot declare ~A itself."
                                (%option-display-name spec)
                                relation)))
    resolved))
