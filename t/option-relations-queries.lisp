(in-package :cl-cli/test)

(deftest-queries normalized-requires-relations
    ((make-option-relations-rulebase
      (list (make-option :name "profile"
                         :aliases '("p")
                         :kind :value)
            (make-option :name "config"
                         :kind :value
                         :requires '("p")))))
  ("resolves alias dependencies to canonical keys"
   (requires :config ?dependency)
   :ordered
   (((?dependency . :profile))))
   ("does not attach dependencies to unrelated options"
    (requires :profile ?dependency)
    :fails))

(deftest-queries normalized-requires-relations-character-target
    ((make-option-relations-rulebase
      (list (make-option :name "profile"
                         :aliases '("p")
                         :kind :value)
            (make-option :name "config"
                         :kind :value
                         ;; A short-option alias may also be given as a raw
                         ;; character (#\p), not just a string ("p") --
                         ;; NORMALIZE-OPTION-RELATION-TARGET's ETYPECASE
                         ;; declares CHARACTER as its own branch, distinct
                         ;; from STRING.
                         :requires (list #\p)))))
  ("resolves a character-designated alias dependency to its canonical key"
   (requires :config ?dependency)
   :ordered
   (((?dependency . :profile)))))

(deftest-queries normalized-conflict-relations
    ((make-option-relations-rulebase
      (list (make-option :name "internal-token"
                         :kind :value
                         :hidden-p t)
            (make-option :name "config"
                         :kind :value
                         :conflicts-with '(:internal-token)))))
  ("retains conflicts against hidden targets"
   (conflicts :config ?target)
   :ordered
   (((?target . :internal-token))))
  ("tracks which options are hidden"
   (hidden :internal-token)
   :succeeds))
