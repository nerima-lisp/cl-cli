(in-package :cl-cli/test)

;;; Parser and renderer performance regression checks.

(defparameter *benchmark-flag-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v
                                               :kind :flag))))

(defparameter *benchmark-rest-app*
  (make-app :name "bench"
            :positionals (list (make-positional :key :rest :rest-p t))))

(defparameter *benchmark-count-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v
                                               :kind :count))))

(defparameter *benchmark-subcommand-app*
  (make-app :name "bench"
            :global-options (list (make-option :name "verbose" :short #\v :kind :flag))
            :commands (list (make-command
                             :name "build"
                             :options (list (make-option :name "target" :kind :value)
                                           (make-option :name "release" :kind :flag))
                             :positionals (list (make-positional :key :input
                                                                 :required-p t))))))

(defparameter *benchmark-relation-heavy-parse-app*
  (make-app
   :name "reltool"
   :global-options
   (append
    (list (make-option :name "profile" :kind :value)
          (make-option :name "config" :kind :value :requires '(:profile))
          (make-option :name "verbose" :kind :flag :conflicts-with '(:quiet))
          (make-option :name "quiet" :kind :flag)
          (make-option :name "output" :kind :value :required-if '(:config)))
    (required-exclusive-group
     (make-option :name "a" :kind :flag)
     (make-option :name "b" :kind :flag)))))

(defun %benchmark-relation-heavy-options (n)
  "Build N flag options with chained requirements and a shared conflict."
  (cons (make-option :name "sentinel" :kind :flag)
        (loop for i below n
              collect (make-option :name (format nil "opt-~D" i) :kind :flag
                                   :requires (when (plusp i) (list (format nil "opt-~D" (1- i))))
                                   :conflicts-with (list "sentinel")))))

(defparameter *benchmark-large-completion-app*
  (make-app
   :name "bench-large"
   :global-options (loop for i below 30
                         collect (make-option :name (format nil "global-opt-~D" i)
                                              :kind :value))
   :commands (loop for i below 20
                   collect (make-command
                            :name (format nil "cmd-~D" i)
                            :options (loop for j below 10
                                          collect (make-option
                                                   :name (format nil "cmd~D-opt-~D" i j)
                                                   :kind :value))))))

(describe-sequential "parser benchmark"
  (it "caches each scope's built-in-augmented specs and lookup table once at MAKE-APP time"
    (expect (consp (cl-cli::app-global-option-cache *benchmark-subcommand-app*)))
    (let* ((build-command (first (app-commands *benchmark-subcommand-app*)))
           (cache (gethash build-command
                          (cl-cli::app-command-option-caches *benchmark-subcommand-app*))))
      (expect (consp cache))
      (expect (member :target (mapcar #'option-key (car cache))))))

  (it "caches built-in-option-specs once at MAKE-APP time for help/completion renderers too"
    (let ((specs (cl-cli::built-in-option-specs *benchmark-subcommand-app*)))
      (expect (eq specs (cl-cli::app-cached-built-in-option-specs
                        *benchmark-subcommand-app*)))
      (expect (eq (option-key (first specs)) :help)))))

#+sbcl
(describe-sequential
    "parser benchmark budgets"
  (it "constructs a 100-option relation-heavy app in well under budget"
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 50)
                      (make-app :name "reltool"
                               :global-options (%benchmark-relation-heavy-options 100))))))
      (expect (< (median-ms result) 2000))))

  (it "constructs a 330-option relation-free app in well under budget"
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 100)
                      (make-app
                       :name "bench-large"
                       :global-options (loop for i below 30
                                             collect (make-option
                                                      :name (format nil "global-opt-~D" i)
                                                      :kind :value))
                       :commands (loop for i below 20
                                       collect (make-command
                                                :name (format nil "cmd-~D" i)
                                                :options (loop for j below 10
                                                              collect (make-option
                                                                       :name (format nil "cmd~D-opt-~D" i j)
                                                                       :kind :value)))))))))
      (expect (< (median-ms result) 2000))))

  (it "repeated small parses against the same app stay well under budget"
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 100000)
                      (parse-argv *benchmark-subcommand-app*
                                 '("bench" "-v" "build" "--target" "x86" "in.lisp"))))))
      (expect (< (median-ms result) 2000))))

  (it "repeated parses against a relation-heavy app stay well under budget"
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 50000)
                      (parse-argv *benchmark-relation-heavy-parse-app*
                                 '("reltool" "--profile" "p" "--config" "c"
                                   "--output" "o" "-a"))))))
      (expect (< (median-ms result) 2000))))

  (it "scans a 5,000-flag argv (%SCAN-OPTIONS-PREFIX) in well under budget"
    (let* ((argv (list* "bench" (loop repeat 5000 collect "--verbose")))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-flag-app* argv))))
      (expect (< (median-ms result) 2000))))

  (it "scans 5,000 positional tokens (%SCAN-MIXED-ARGUMENTS) in well under budget"
    (let* ((argv (list* "bench" "--" (loop for index below 5000
                                           collect (format nil "arg~D" index))))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-rest-app* argv))))
      (expect (< (median-ms result) 2000))))

  (it "scans a 20,000-character short cluster (%SCAN-SHORT-CLUSTER) in well under budget"
    (let* ((argv (list "bench" (format nil "-~A" (make-string 20000
                                                              :initial-element #\v))))
           (result (benchmark (:warmup 1 :samples 5)
                     (parse-argv *benchmark-count-app* argv))))
      (expect (< (median-ms result) 2000))))

  (it "deduplicates a large candidate list in well under budget (guards against an O(n^2) regression)"
    (let* ((strings (loop for i below 10000 collect (format nil "cmd-~D" (mod i 1000))))
           (result (benchmark (:warmup 1 :samples 5)
                     (cl-cli::%completion-space-joined strings))))
      (expect (< (median-ms result) 50))))

  (it-each (("bash") ("zsh") ("fish") ("powershell") ("nushell") ("elvish"))
      "renders a ~A completion script for a 230-option/20-command app in well under budget"
      (shell)
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (render-completion *benchmark-large-completion-app* shell)))))
      (expect (< (median-ms result) 2000))))

  (it-each (("manpage") ("markdown") ("json"))
      "renders a ~A document for a 230-option/20-command app in well under budget"
      (label)
    (let ((result (benchmark (:warmup 1 :samples 5)
                    (dotimes (i 200)
                      (cond
                        ((string= label "manpage") (render-manpage *benchmark-large-completion-app*))
                        ((string= label "markdown") (render-markdown *benchmark-large-completion-app*))
                        (t (render-json *benchmark-large-completion-app*)))))))
      (expect (< (median-ms result) 2000)))))
