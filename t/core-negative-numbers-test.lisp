(in-package :cl-cli/test)

(defun negatives-app (&key (allow t))
  (make-app :name "calc"
            :allow-negative-numbers allow
            :global-options (list (make-option :name "scale" :short #\s :kind :value))
            :positionals (list (make-positional :key :n :type :number))))

(describe-sequential "negative-number positionals"
  (it "accepts a negative integer positional"
    (with-parsed-argv (inv (negatives-app) '("calc" "-5"))
      (expect (eql (positional-value inv :n) -5))))

  (it "accepts a negative decimal positional"
    (with-parsed-argv (inv (negatives-app) '("calc" "-1.5"))
      (expect (= (positional-value inv :n) -3/2))))

  (it "accepts a leading-dot negative decimal positional"
    (with-parsed-argv (inv (negatives-app) '("calc" "-.5"))
      (expect (= (positional-value inv :n) -1/2))))

  (it "still parses real short options"
    (with-parsed-argv (inv (negatives-app) '("calc" "-s" "2" "-7"))
      (expect (string= (option-value inv :scale) "2"))
      (expect (eql (positional-value inv :n) -7))))

  (it "treats a negative number as an option value"
    (with-parsed-argv (inv (negatives-app) '("calc" "--scale" "-3" "10"))
      (expect (string= (option-value inv :scale) "-3"))
      (expect (eql (positional-value inv :n) 10))))

  (it "treats -5 as an option cluster when the feature is disabled"
    (signals cli-unknown-option
      (parse-argv (negatives-app :allow nil) '("calc" "-5")))))

(describe-sequential "property-list key presence"
  (it "recognizes a key whose value matches the old internal sentinel"
    (expect (cl-cli::plist-has-key-p (list :value :__missing__) :value))
    (expect (not (cl-cli::plist-has-key-p (list :value :__missing__) :other)))))

(describe-sequential "control character classification"
  (it "recognizes C0, DEL, and C1 controls without swallowing printable boundaries"
    (expect (cl-cli::%control-character-code-p 0))
    (expect (cl-cli::%control-character-code-p 31))
    (expect (cl-cli::%control-character-code-p 127))
    (expect (cl-cli::%control-character-code-p 128))
    (expect (cl-cli::%control-character-code-p 159))
    (expect (not (cl-cli::%control-character-code-p 32)))
    (expect (not (cl-cli::%control-character-code-p 160)))))
