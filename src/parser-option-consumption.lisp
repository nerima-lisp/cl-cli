(in-package :cl-cli)

(defun parse-long-option-token (token)
  (let ((body (subseq token 2)))
    (multiple-value-bind (name attached) (split-string-once body #\=)
      (values (canonical-option-name name) attached))))

(defun parse-short-cluster (token)
  (subseq token 1))

(defun consume-long-option-token (token specs table values action remaining)
  (multiple-value-bind (name attached) (parse-long-option-token token)
    (let* ((entry (resolve-long-option-entry name table specs))
           (spec (option-entry-spec entry))
           (negated-p (option-entry-negated-p entry)))
      (case (option-kind spec)
        (:flag
         (when attached
           (signal-option-does-not-take-value (format nil "--~A" name)))
         (multiple-value-bind (new-values new-action)
             (store-flag-option values spec action)
           (values new-values (rest remaining) new-action
                   (option-stop-parsing-p spec))))
        (:count
         (when attached
           (signal-option-does-not-take-value (format nil "--~A" name)))
         (multiple-value-bind (new-values new-action)
             (store-count-option values spec action)
           (values new-values (rest remaining) new-action
                   (option-stop-parsing-p spec))))
        (:boolean
         (when attached
           (signal-option-does-not-take-value (format nil "--~A" name)))
         (multiple-value-bind (new-values new-action)
             (store-boolean-option-value values spec action negated-p)
           (values new-values (rest remaining) new-action
                   (option-stop-parsing-p spec))))
        ((:value :optional-value :key-value)
         (consume-value-option spec attached (rest remaining) values action
                               (format nil "--~A" name)))))))

(defun %multi-value-option-p (spec)
  (and (typep spec 'option-spec)
       (multi-value-count-p (option-value-count spec))))

(defun %store-multi-values (spec values taken)
  (store-option-value values spec
                      (mapcar (lambda (token) (parse-option-value spec token))
                              taken)))

(defun consume-multi-value-option (spec attached tokens values action token-name)
  "Consume SPEC's value list: a fixed count, or greedily for :+ / :*.

A fixed N takes exactly N tokens (too few is an error). :+ / :* take every
leading token up to the next option-like token; :+ requires at least one."
  (let ((count (option-value-count spec)))
    (when attached
      (signal-cli-error 'cli-usage-error
                        (format nil "Option ~A takes separate values, not an attached one."
                                token-name)))
    (if (variadic-value-count-p count)
        (let ((taken (loop for token in tokens
                           until (option-like-token-p token)
                           collect token)))
          (when (and (eq count :+) (null taken))
            (signal-cli-error 'cli-missing-option-value
                              (format nil "Option ~A requires at least one value." token-name)
                              :option (option-key spec)))
          (multiple-value-setq (values action)
            (values (%store-multi-values spec values taken)
                    (built-in-option-action spec action)))
          (values values (nthcdr (length taken) tokens) action
                  (option-stop-parsing-p spec)))
        (progn
          (when (< (length tokens) count)
            (signal-cli-error 'cli-missing-option-value
                              (format nil "Option ~A requires ~A values." token-name count)
                              :option (option-key spec)))
          (let ((taken (subseq tokens 0 count)))
            (multiple-value-setq (values action)
              (values (%store-multi-values spec values taken)
                      (built-in-option-action spec action)))
            (values values (nthcdr count tokens) action
                    (option-stop-parsing-p spec)))))))

(defun consume-value-option (spec attached tokens values action token-name)
  (when (%multi-value-option-p spec)
    (return-from consume-value-option
      (consume-multi-value-option spec attached tokens values action token-name)))
  (when (and (member (option-kind spec) '(:value :key-value))
             (null attached)
             (null tokens))
    (signal-cli-error 'cli-missing-option-value
                      (format nil "Missing value for ~A" token-name)
                      :option (option-key spec)))
  (let* ((consume-separated-optional-p
           (and (eq (option-kind spec) :optional-value)
                (option-consume-optional-value-p spec)
                tokens
                (not (option-like-token-p (first tokens)))))
         (raw (cond
                (attached attached)
                (consume-separated-optional-p (first tokens))
                ((eq (option-kind spec) :optional-value) t)
                (t (first tokens)))))
    (multiple-value-setq (values action)
      (store-parsed-option-value values spec action raw))
    (when (and (member (option-kind spec) '(:value :key-value))
               (null attached)
               tokens)
      (setf tokens (rest tokens)))
    (when consume-separated-optional-p
      (setf tokens (rest tokens)))
    (values values tokens action (option-stop-parsing-p spec))))

(defun %prepend-short-cluster-remainder (cluster index tokens)
  "Preserve unconsumed characters after a stop-parsing flag/boolean at INDEX.

A stop-parsing flag/boolean has no value of its own to absorb the rest of the
cluster the way :VALUE/:OPTIONAL-VALUE options do, so without this the
remaining characters (e.g. \"b\" in \"-xb\" when \"-x\" stops parsing) were
silently discarded instead of surfacing as literal input. Parsing already
switches to literal mode once stop-parsing fires, so the exact spelling only
affects the stored value, not control flow; the leading \"-\" is restored so
the token reflects what was actually typed."
  (let ((rest (subseq cluster (1+ index))))
    (if (plusp (length rest))
        (cons (format nil "-~A" rest) tokens)
        tokens)))

(defun %scan-short-cluster (cluster tokens specs table values action index on-done)
  "Scan CLUSTER's characters from INDEX, calling ON-DONE with
(values tokens action done-p) once the cluster is exhausted or a character
consumes the rest of the cluster / following tokens as a value.

Genuine continuation-passing style: every terminal case (each option kind
that absorbs a value, a stop-parsing flag/count/boolean, or running off the
end of CLUSTER) calls ON-DONE instead of RETURN-FROM, and the one
keep-scanning case is a tail call, so SBCL compiles this to a loop with no
stack growth regardless of CLUSTER's length."
  (if (>= index (length cluster))
      (funcall on-done values tokens action nil)
      (let* ((name (string (char cluster index)))
             (entry (resolve-option-entry table name)))
        (unless entry
          (signal-unknown-short-option name specs))
        (let ((spec (option-entry-spec entry)))
          (flet ((continue-or-stop (new-values new-action)
                   (if (option-stop-parsing-p spec)
                       (funcall on-done new-values
                                (%prepend-short-cluster-remainder cluster index tokens)
                                new-action t)
                       (%scan-short-cluster cluster tokens specs table new-values
                                            new-action (1+ index) on-done))))
            (case (option-kind spec)
              (:flag
               (multiple-value-bind (new-values new-action)
                   (store-flag-option values spec action)
                 (continue-or-stop new-values new-action)))
              ;; A :count short option keeps scanning the cluster, so a
              ;; repeated character such as `-vvv` increments the counter
              ;; once per occurrence -- exactly the conventional verbosity
              ;; shape. Like :flag it never absorbs a value of its own.
              (:count
               (multiple-value-bind (new-values new-action)
                   (store-count-option values spec action)
                 (continue-or-stop new-values new-action)))
              (:boolean
               (multiple-value-bind (new-values new-action)
                   (store-boolean-option-value values spec action nil)
                 (continue-or-stop new-values new-action)))
              (:optional-value
               (let* ((rest (subseq cluster (1+ index)))
                      (attached (and (> (length rest) 0) rest))
                      (consume-separated-optional-p
                        (and (null attached)
                             (option-consume-optional-value-p spec)
                             tokens
                             (not (option-like-token-p (first tokens)))))
                      (raw (cond
                             (attached attached)
                             (consume-separated-optional-p (first tokens))
                             (t t))))
                 (multiple-value-bind (new-values new-action)
                     (store-parsed-option-value values spec action raw)
                   (funcall on-done new-values
                            (if consume-separated-optional-p (rest tokens) tokens)
                            new-action (option-stop-parsing-p spec)))))
              ((:value :key-value)
               (if (%multi-value-option-p spec)
                   (let ((rest (subseq cluster (1+ index))))
                     (multiple-value-bind (new-values new-tokens new-action done-p)
                         (consume-multi-value-option
                          spec (and (plusp (length rest)) rest) tokens values action
                          (format nil "-~A" name))
                       (funcall on-done new-values new-tokens new-action done-p)))
                   (let* ((rest (subseq cluster (1+ index)))
                          (attached (and (> (length rest) 0) rest))
                          (raw (or attached (first tokens))))
                     (when (and (null attached) (null tokens))
                       (signal-cli-error 'cli-missing-option-value
                                         (format nil "Missing value for -~A" name)
                                         :option (option-key spec)))
                     (multiple-value-bind (new-values new-action)
                         (store-parsed-option-value values spec action raw)
                       (funcall on-done new-values
                                (if (and (null attached) tokens) (rest tokens) tokens)
                                new-action (option-stop-parsing-p spec))))))))))))

(defun consume-short-cluster (cluster tokens specs table values action)
  (%scan-short-cluster cluster tokens specs table values action 0 #'values))

(defun consume-argument-option-token (token validated-specs table values action
                                      remaining)
  (cond
    ((long-option-token-p token)
     (multiple-value-bind (new-values new-remaining new-action done-p)
         (consume-long-option-token token validated-specs table values action
                                    remaining)
       (values new-values new-remaining new-action done-p t)))
    ((short-option-token-p token)
     (multiple-value-bind (new-values new-remaining new-action done-p)
         (consume-short-cluster (parse-short-cluster token)
                                (rest remaining)
                                validated-specs
                                table
                                values
                                action)
       (values new-values new-remaining new-action done-p t)))
    (t
     (values values remaining action nil nil))))
