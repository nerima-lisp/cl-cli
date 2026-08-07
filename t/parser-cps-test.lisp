(in-package :cl-cli/test)

(describe-sequential "parser CPS contracts"
  (it "passes an empty option scan to its continuation"
    (cl-weave:with-continuation-values (captured next called-p)
        (cl-cli::%scan-options-prefix nil nil nil :seed :dispatch nil #'next)
      (expect called-p)
      (expect (equal captured '(:seed nil :dispatch nil)))))

  (it "passes an option separator to its continuation"
    (cl-weave:with-continuation-values (captured next called-p)
        (cl-cli::%scan-options-prefix nil nil '("--" "input")
                                      :seed :dispatch nil #'next)
      (expect called-p)
      (expect (equal captured '(:seed ("input") :dispatch t)))))

  (it "recurses through a flag before completing the option scan"
    (let ((app (make-app :name "cps"
                         :global-options
                         (list (make-option :name "verbose" :kind :flag)))))
      (multiple-value-bind (specs table)
          (cl-cli::prepare-option-parser-state
           app (app-global-options app)
           (cl-cli::app-global-option-cache app))
        (cl-weave:with-continuation-values (captured next called-p)
            (cl-cli::%scan-options-prefix specs table '("--verbose")
                                          nil :dispatch nil #'next)
          (expect called-p)
          (expect (getf (first captured) :verbose))
          (expect (null (second captured)))
          (expect (eq (third captured) :dispatch))
          (expect (null (fourth captured)))))))

  (it "consumes literal positional arguments in the mixed scanner"
    (let ((positionals (list (make-positional :key :input :required-p t))))
      (cl-weave:with-continuation-values (captured next called-p)
          (cl-cli::%scan-mixed-arguments
           nil nil '("--" "input") positionals nil nil :dispatch nil #'next)
        (expect called-p)
        (expect (null (first captured)))
        (expect (null (second captured)))
        (expect (string= (getf (third captured) :input) "input"))
        (expect (eq (fourth captured) :dispatch)))))

  (it "completes a deep CPS scan with parsed values intact"
    (let* ((flags (loop repeat 2048 collect "--verbose"))
           (arguments (loop for index below 2048
                            collect (format nil "arg-~D" index)))
           (app (make-app
                 :name "cps-depth"
                 :global-options
                 (list (make-option :name "verbose" :kind :count))
                 :positionals
                 (list (make-positional :key :rest :rest-p t))))
           (invocation (parse-argv app
                                   (append (list "cps-depth")
                                           flags
                                           (list "--")
                                           arguments))))
      (expect (= (option-value invocation :verbose) 2048))
      (expect (equal (positional-value invocation :rest) arguments)))))
