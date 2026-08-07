(in-package :cl-cli/test)

(defun optional-value-option (name &key short consume-optional-value-p)
  (make-option :name name
               :short short
               :kind :optional-value
               :consume-optional-value-p consume-optional-value-p))

(defun value-option (name &key short multiple-p default parser env-var env-vars
                             choices hidden-p required-p)
  (make-option :name name
               :short short
               :kind :value
               :multiple-p multiple-p
               :default default
               :parser parser
               :env-var env-var
               :env-vars env-vars
               :choices choices
               :hidden-p hidden-p
               :required-p required-p))

(defun flag-option (name &key short hidden-p)
  (make-option :name name
               :short short
               :kind :flag
               :hidden-p hidden-p))

(defun stop-parsing-option (name &key short)
  (make-option :name name
               :short short
               :kind :value
               :stop-parsing-p t))

(defmacro with-environment-variable-reader ((reader) &body body)
  `(let ((cl-cli::*environment-variable-reader* ,reader))
     ,@body))

(defmacro with-parsed-argv ((invocation app-form argv-form) &body body)
  (let ((app (gensym "APP")))
    `(let* ((,app ,app-form)
            (,invocation (parse-argv ,app ,argv-form)))
       ,@body)))

(defmacro with-parsed-argv-with-environment-variable-reader
    ((invocation app-form argv-form reader-form) &body body)
  (let ((app (gensym "APP"))
        (reader (gensym "READER")))
    `(let* ((,app ,app-form)
            (,reader ,reader-form))
       (with-environment-variable-reader (,reader)
         (let ((,invocation (parse-argv ,app ,argv-form)))
           ,@body)))))

(defmacro with-caught-signal-from-argv (((condition-type condition)
                                         (app app-form argv-form))
                                        &body body)
  (declare (ignore app))
  (let ((app-sym (gensym "APP")))
    `(let ((,app-sym ,app-form))
       (caught-signal= (,condition-type ,condition)
           (parse-argv ,app-sym ,argv-form)
         ,@body))))

(defmacro with-parsed-invocations ((app app-form &rest bindings) &body body)
  (let ((app-sym (gensym "APP")))
    `(let* ((,app-sym ,app-form)
            ,@(loop for (name argv-form) in bindings
                    collect `(,name (parse-argv ,app-sym ,argv-form))))
       (let ((,app ,app-sym))
         (declare (ignorable ,app))
         ,@body))))
