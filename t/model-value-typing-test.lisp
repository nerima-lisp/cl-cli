(in-package :cl-cli/test)

(defun typed-option-app (&rest option-args)
  (make-app :name "tool"
            :global-options (list (apply #'make-option :name "count" :kind :value
                                         option-args))))

(describe-sequential "typed values"
  (it "parses integer option values"
    (with-parsed-argv (inv (typed-option-app :type :integer)
                          '("tool" "--count" "42"))
      (expect (eql (option-value inv :count) 42))))

  (it-each (("rejects a non-integer value" (:type :integer) "4x")
            ("rejects a value below the inclusive minimum" (:type :integer :min 1) "0")
            ("rejects a value above the inclusive maximum" (:type :integer :max 10) "11"))
      "~A"
      (label option-args input)
    (declare (ignore label))
    (signals cli-invalid-option-value
      (parse-argv (apply #'typed-option-app option-args)
                  (list "tool" "--count" input))))

  (it "reports the failing option in the invalid-value condition"
    (caught-signal= (cli-invalid-option-value condition)
        (parse-argv (typed-option-app :type :integer)
                    '("tool" "--count" "nope"))
      (:eq cli-invalid-option-value-name :count)
      (:equal cli-invalid-option-value-value "nope")))

  (it "accepts a value inside the range"
    (with-parsed-argv (inv (typed-option-app :type :integer :min 1 :max 10)
                          '("tool" "--count" "5"))
      (expect (eql (option-value inv :count) 5))))

  (it "parses float values and coerces to double-float"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :global-options (list (make-option :name "rate"
                                                                        :kind :value
                                                                        :type :float)))
                          '("tool" "--rate" "1.5"))
      (expect (typep (option-value inv :rate) 'double-float))
      (expect (= (option-value inv :rate) 1.5d0))))

  (it "parses number values keeping exact ratios"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :global-options (list (make-option :name "ratio"
                                                                        :kind :value
                                                                        :type :number)))
                          '("tool" "--ratio" "1/2"))
      (expect (= (option-value inv :ratio) 1/2))))

  (it "parses boolean-typed value options"
    (with-parsed-invocations (app (make-app
                                   :name "tool"
                                   :global-options (list (make-option :name "enabled"
                                                                      :kind :value
                                                                      :type :boolean)))
                                 (yes '("tool" "--enabled" "yes"))
                                 (off '("tool" "--enabled" "off")))
      (expect (eq (option-value yes :enabled) t))
      (expect (eq (option-value off :enabled) nil))))

  (it "rejects an unrecognized boolean-typed value"
    ;; BUILD-TYPED-VALUE-PARSER's :boolean parser calls PARSE-BOOLEAN-DESIGNATOR
    ;; with no display-name/option-key, so an invalid value here -- unlike the
    ;; :parser-lambda-with-context path -- takes PARSE-BOOLEAN-DESIGNATOR's
    ;; plain (ERROR ...) fallback, rewrapped by WITH-VALUE-PARSE-ERRORS.
    (signals cli-invalid-option-value
      (parse-argv (make-app :name "tool"
                            :global-options (list (make-option :name "enabled"
                                                               :kind :value
                                                               :type :boolean)))
                 '("tool" "--enabled" "maybe"))))

  (it "never evaluates read-eval syntax in numeric values"
    (signals cli-invalid-option-value
      (parse-argv (make-app :name "tool"
                            :global-options (list (make-option :name "ratio"
                                                               :kind :value
                                                               :type :number)))
                  '("tool" "--ratio" "#.(+ 1 2)"))))

  (it "rejects a numeric value with trailing junk"
    (signals cli-invalid-option-value
      (parse-argv (make-app :name "tool"
                            :global-options (list (make-option :name "ratio"
                                                               :kind :value
                                                               :type :number)))
                  '("tool" "--ratio" "1 2"))))

  (it "rejects a value that reads cleanly but is not a real number"
    ;; Distinct from the trailing-junk case above: %READ-CLI-REAL-NUMBER's own
    ;; (REALP VALUE) check, not its consumed-whitespace loop -- "abc" reads as
    ;; one whole symbol token (END already at the string's length), so only
    ;; REALP rejects it. Every other :type :number/:float error test in the
    ;; suite (read-eval, trailing junk) fails the whitespace loop instead.
    (signals cli-invalid-option-value
      (parse-argv (make-app :name "tool"
                            :global-options (list (make-option :name "ratio"
                                                               :kind :value
                                                               :type :number)))
                  '("tool" "--ratio" "abc"))))

  (it "accepts surrounding whitespace in numeric values"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :global-options (list (make-option :name "ratio"
                                                                        :kind :value
                                                                        :type :number)))
                          '("tool" "--ratio" "  1/2  "))
      (expect (= (option-value inv :ratio) 1/2))))

  (it "coerces a string literal default through the typed parser"
    (with-parsed-argv (inv (typed-option-app :type :integer :default "7")
                          '("tool"))
      (expect (eql (option-value inv :count) 7))))

  (it "applies a type to positional values"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :positionals (list (make-positional :key :port
                                                                         :type :integer
                                                                         :min 1
                                                                         :max 65535)))
                          '("tool" "8080"))
      (expect (eql (positional-value inv :port) 8080))))

  (it "rejects a positional value outside the range"
    (signals cli-invalid-positional-value
      (parse-argv (make-app :name "tool"
                            :positionals (list (make-positional :key :port
                                                                :type :integer
                                                                :max 100)))
                  '("tool" "999"))))

  (it "surfaces the type and range in help output"
    (let ((app (typed-option-app :type :integer :min 1 :max 10)))
      (with-app-help-text (text app)
        (assert-searches text "type: integer" "range: 1..10"))))

  (it "surfaces a lone minimum in help output"
    (let ((app (typed-option-app :type :integer :min 1)))
      (with-app-help-text (text app)
        (assert-searches text "min: 1")
        (assert-not-searches text "range:"))))

  (it "does not label the default string type in help"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "name"
                                                            :kind :value
                                                            :type :string)))))
      (with-app-help-text (text app)
        (assert-not-searches text "type: string"))))

  ;; --- specification validation (fail fast at make time) ---

  (it "rejects combining :type with an explicit :parser"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :type :integer :parser #'identity)))

  (it-each (("rejects an unknown :type" (:kind :value :type :date))
          ("rejects :min on a non-numeric type" (:kind :value :type :string :min 1))
          ("rejects :type on a flag option" (:kind :flag :type :integer))
          ("rejects :type on an optional-value option" (:kind :optional-value :type :integer)))
      "~A"
      (label plist)
    (declare (ignore label))
    (signals-invalid-specification
      (apply #'make-option :name "x" plist)))

  (it "applies the type to each occurrence of a repeatable option"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "port"
                                                               :kind :value
                                                               :type :integer
                                                               :multiple-p t)))
                          '("tool" "--port" "80" "--port" "443"))
      (expect (equal (option-value inv :port) '(80 443)))))

  (it-each (("rejects a non-real bound" (:kind :value :type :integer :min "1"))
          ("rejects an inverted min/max" (:kind :value :type :integer :min 10 :max 1)))
      "~A"
      (label plist)
    (declare (ignore label))
    (signals-invalid-specification
      (apply #'make-option :name "x" plist)))

  (it "rejects :type combined with :parser on a positional"
    (signals-invalid-specification
      (make-positional :key :port :type :integer :parser #'identity))))
