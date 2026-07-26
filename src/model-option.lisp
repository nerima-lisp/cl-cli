(in-package :cl-cli)

(defparameter +valueless-option-kinds+ '(:flag :boolean :count)
  "Option kinds that carry no user-supplied value on the command line.")

(defun %valueless-option-kind-p (kind)
  (member kind +valueless-option-kinds+))

(defun %option-carries-value-p (option)
  (and (option-kind option) (not (%valueless-option-kind-p (option-kind option)))))

(defun make-option (&key key name short aliases kind description value-name
                      type min max value-delimiter value-count value-hint complete
                      (default nil default-supplied-p)
                      env-var env-vars choices completion-candidates parser required-p
                      required-if required-unless requires
                      requires-any-of
                      conflicts-with multiple-p
                      consume-optional-value-p stop-parsing-p hidden-p deprecated group)
  "Create a parsed option specification.

NAME is the long option name without leading dashes. SHORT may be a single
character or short-name string. ALIASES is a list of additional option names.

TYPE selects a built-in value parser (:integer, :number, :float, :boolean, or
the default :string) for a :value option; MIN and MAX add inclusive bounds for
numeric types. A :type and an explicit :parser are mutually exclusive. KIND
:count turns the option into a repeatable counter (`-vvv` => 3) that defaults
to 0. VALUE-DELIMITER (a single character) makes a :value option split one
occurrence into a list (`--tags a,b,c` => (\"a\" \"b\" \"c\")), parsing each
piece and accumulating across occurrences. GROUP is a help-section label that
groups related options under a heading, mirroring a command's :group.

KIND :key-value parses each occurrence as `key=value` (a bare `key` yields
value T) and accumulates the pairs into an alist, so `-D a=1 -D b=2` reads as
((\"a\" . \"1\") (\"b\" . \"2\")).

VALUE-COUNT N makes a :value option consume exactly N following tokens as a
parsed list (`--point 1 2` => (1 2)); too few remaining tokens signal
CLI-MISSING-OPTION-VALUE, and with :multiple-p each occurrence contributes its
own N-element list. VALUE-COUNT may also be :+ (one or more) or :* (zero or
more), which greedily consume following tokens up to the next option-like token."
  (let* ((names (normalize-option-names name short aliases))
         (names-present-p (not (null names))))
    (unless names-present-p
      (signal-cli-error 'cli-invalid-specification
                        "An option needs at least one name."))
    (validate-non-empty-strings names "Option names")
    ;; Validate before OPTION-KEYWORD interns a symbol below: a spec that's
    ;; about to be rejected must not leak a permanent :KEYWORD-package symbol
    ;; for every rejected name an embedder tries (e.g. building specs from
    ;; untrusted plugin/config data and catching CLI-INVALID-SPECIFICATION).
    (validate-safe-identifier-names names "Option names")
    (let* ((resolved-key (or key
                             (option-keyword (or name (first names)))))
           (resolved-kind (or kind (if multiple-p :value :flag)))
           (resolved-value-name (cond
                                  (value-name (princ-to-string value-name))
                                  ((eq resolved-kind :key-value) "KEY=VALUE")
                                  (t nil)))
           (resolved-negated-names
             (normalize-negated-option-names resolved-kind names))
           (resolved-env-vars (normalize-env-vars env-var env-vars))
           (resolved-choices (normalize-option-choices choices))
           (resolved-completion-candidates
             (normalize-option-completion-candidates completion-candidates))
           (resolved-requires (normalize-option-relations requires))
           (resolved-required-if (normalize-option-relations required-if))
           (resolved-required-unless (normalize-option-relations required-unless))
           (resolved-requires-any-of (normalize-option-relations requires-any-of))
           (resolved-conflicts-with (normalize-option-relations conflicts-with))
           ;; Validate the :type / :min / :max / :parser combination BEFORE
           ;; RESOLVED-PARSER runs BUILD-TYPED-VALUE-PARSER: that helper's ECASE
           ;; would otherwise raise a raw CASE-FAILURE on an unknown :type
           ;; instead of the CLI-INVALID-SPECIFICATION callers expect. LET* runs
           ;; bindings top-to-bottom, so this guard fires first.
           (%typed-value-check
             (progn
               ;; Restrict typed values to :value options. An :optional-value
               ;; stores the sentinel T for its bare form (`--opt` with no
               ;; value), which a typed parser such as :integer cannot accept --
               ;; so allowing :type there would make the bare form signal a
               ;; spurious invalid-value error at parse time.
               (when (and (or type min max)
                          (not (eq resolved-kind :value)))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :type / :min / :max apply ~
                                                only to :value options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (validate-typed-value-spec type min max parser
                                          (format nil "Option ~A"
                                                  (option-token-display-name (first names))))
               (when (and value-delimiter (not (eq resolved-kind :value)))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :value-delimiter applies ~
                                                only to :value options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (when value-count
                 (unless (or (variadic-value-count-p value-count)
                             (and (integerp value-count) (>= value-count 1)))
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count must be a ~
                                                  positive integer or :+ / :*, got: ~S"
                                             (option-token-display-name (first names))
                                             value-count)))
                 (unless (eq resolved-kind :value)
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count applies only ~
                                                  to :value options, not ~A."
                                             (option-token-display-name (first names))
                                             resolved-kind)))
                 (when (and value-delimiter (multi-value-count-p value-count))
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count cannot combine ~
                                                  with :value-delimiter."
                                             (option-token-display-name (first names))))))
               (when (and value-hint
                          (%valueless-option-kind-p resolved-kind))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :value-hint applies only to ~
                                                value-bearing options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (normalize-value-hint value-hint
                                     (format nil "Option ~A"
                                             (option-token-display-name (first names))))))
           (resolved-value-delimiter (normalize-value-delimiter value-delimiter))
           (resolved-parser (cond
                              (type (build-typed-value-parser type min max))
                              (parser parser)
                              (t (ecase resolved-kind
                                   (:flag (lambda (value)
                                            (declare (ignore value))
                                            t))
                                   (:count (lambda (value)
                                             (declare (ignore value))
                                             t))
                                   (:boolean (let ((display-name
                                                     (if (= (length (first names)) 1)
                                                         (format nil "-~A" (first names))
                                                         (format nil "--~A" (first names)))))
                                               (lambda (value)
                                                 (parse-boolean-designator value
                                                                           display-name
                                                                           resolved-key))))
                                   (:value #'identity)
                                   (:optional-value #'identity)
                                   (:key-value #'identity)))))
           ;; A :count option is an accumulating counter, so it always has a
           ;; well-defined resolved value even when never supplied: default it
           ;; to 0 (unless the caller overrode :default) so OPTION-VALUE returns
           ;; a number rather than NIL.
           (count-default-p (and (eq resolved-kind :count)
                                 (not default-supplied-p)))
           (resolved-default (if count-default-p 0 default))
           (default-present-p (or default-supplied-p count-default-p)))
      (declare (ignore %typed-value-check))
      (when resolved-value-name
        (validate-non-empty-strings (list resolved-value-name) "Option value names")
        (validate-no-control-characters (list resolved-value-name) "Option value names"))
      (when (and complete (not (functionp complete)))
        (signal-cli-error 'cli-invalid-specification
                          (format nil "Option ~A: :complete must be a function."
                                  (option-token-display-name (first names)))))
      (validate-option-multiplicity resolved-kind multiple-p)
      (%make-option-spec :key resolved-key
                         :names names
                         :negated-names resolved-negated-names
                         :kind resolved-kind
                         :description (normalize-positional-description description)
                         :value-name resolved-value-name
                         :value-type type
                         :value-min min
                         :value-max max
                         :value-delimiter resolved-value-delimiter
                         :value-count value-count
                         :value-hint value-hint
                         :default resolved-default
                         :env-vars resolved-env-vars
                         :choices resolved-choices
                         :completion-candidates resolved-completion-candidates
                         :complete complete
                         :parser resolved-parser
                         :required-p required-p
                         :required-if resolved-required-if
                         :required-unless resolved-required-unless
                         :requires resolved-requires
                         :requires-any-of resolved-requires-any-of
                         :conflicts-with resolved-conflicts-with
                         :multiple-p multiple-p
                         :default-present-p default-present-p
                         :consume-optional-value-p consume-optional-value-p
                         :stop-parsing-p stop-parsing-p
                         :hidden-p hidden-p
                         :deprecated (normalize-deprecated deprecated)
                         :help-group (normalize-command-group group)))))

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
