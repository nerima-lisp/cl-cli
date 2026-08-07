(in-package :cl-cli/test)

(defmacro signals-all (condition-type &body forms)
  `(progn
     ,@(loop for form in forms
             collect `(signals ,condition-type ,form))))

(defmacro signals-invalid-specification (&body forms)
  `(signals-all cli-invalid-specification ,@forms))

(defmacro catching-signal ((condition-type condition) form &body body)
  (let ((seen (gensym "SEEN")))
    `(let ((,seen nil))
       (handler-case
           ,form
         (,condition-type (,condition)
           (setf ,seen t)
           ,@body))
       (expect ,seen))))

(defun app-help-text (app)
  (with-string-output (stream)
    (print-app-help app stream)))

(defun command-help-text (app command)
  (with-string-output (stream)
    (print-command-help app command stream)))

(defmacro with-app-help-text ((text app) &body body)
  `(let ((,text (app-help-text ,app)))
     ,@body))

(defmacro with-command-help-text ((text app command) &body body)
  `(let ((,text (command-help-text ,app ,command)))
     ,@body))

(defun search-not-found-p (needle text)
  (null (search needle text)))

(defmacro assert-searches* (text predicate &rest needles)
  `(progn
     ,@(loop for needle in needles
             collect `(expect (funcall ,predicate ,needle ,text)))))

(defmacro assert-searches (text &rest needles)
  `(assert-searches* ,text #'search ,@needles))

(defmacro assert-not-searches (text &rest needles)
  `(assert-searches* ,text #'search-not-found-p ,@needles))

(defmacro assert-search-order (text &rest needles)
  `(progn
     ,@(loop for (left right) on needles
             while right
             collect `(expect (< (search ,left ,text)
                                 (search ,right ,text))))))

(defmacro plist-values= (invocation accessor expected-label &rest pairs)
  (declare (ignore expected-label))
  (let ((normalized-pairs
          (if (and pairs (every #'consp pairs))
              pairs
              (loop for (key expected) on pairs by #'cddr
                    collect (list key expected)))))
    `(with-soft-assertions
       ,@(loop for pair in normalized-pairs
               for (key expected) = pair
               collect `(expect (equal (,accessor ,invocation ,key) ,expected))))))

(defmacro invocation-values= (invocation &rest clauses)
  `(with-soft-assertions
     ,@(loop for clause in clauses
             collect (destructuring-bind (kind key expected) clause
                       (ecase kind
                         (:option
                          `(expect (equal (option-value ,invocation ,key) ,expected)))
                         (:positional
                          `(expect (equal (positional-value ,invocation ,key) ,expected))))))))

(defmacro option-values= (invocation &rest pairs)
  `(plist-values= ,invocation option-value "option" ,@pairs))

(defmacro positional-values= (invocation &rest pairs)
  `(plist-values= ,invocation positional-value "positional" ,@pairs))

(defmacro caught-signal= ((condition-type condition) form &body clauses)
  `(catching-signal (,condition-type ,condition)
     ,form
     ,@(loop for clause in clauses
             collect (destructuring-bind (kind accessor &rest args) clause
                       (ecase kind
                         (:eq
                          (let ((expected (first args)))
                            `(expect (eq (,accessor ,condition) ,expected))))
                         (:equal
                          (let ((expected (first args)))
                            `(expect (equal (,accessor ,condition) ,expected))))
                         (:searches
                          `(assert-searches (,accessor ,condition)
                             ,@args))
                         (:not-searches
                          `(assert-not-searches (,accessor ,condition)
                             ,@args)))))))
