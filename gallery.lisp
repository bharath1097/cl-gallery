;;TODO: provide default thumbnails for albums without the ones.

(restas:define-module #:gallery
    (:use :cl :files-locator :gallery.content
          :gallery.internal.render
          :gallery.internal.pics-collection)
  (:export #:main
           #:add-pic
           #:receive-pic
           #:receive-album
           #:add-album
           #:view-album
           #:choose-pic
           #:delete-pic
           
           #:albums-grid
           #:album-pics-grid

           #:static.route

           #:*drawer*
           #:*store*

           #:*extra-params*))

(in-package #:gallery)

(restas:mount-module files (#:restas.directory-publisher)
  (:inherit-parent-context t)
  (:url "files")
  (restas.directory-publisher:*directory* #p"/tmp/")
  (restas.directory-publisher:*autoindex* t))

(restas:mount-module static (#:restas.directory-publisher)
  (:inherit-parent-context t)
  (:url "static")
  (restas.directory-publisher:*directory*
   (asdf:system-relative-pathname '#:gallery #p"static/")))

(defparameter *extra-params* nil)
(defparameter *current-files* nil)

(defvar *store* (make-instance 'files-store :upload-dir "/tmp/" :download-dir "wrong"))

(defmethod restas:initialize-module-instance :after ((module (eql #.*package*)) context)
  (restas:with-context context
    (setf (download-dir *store*) (restas:genurl 'files.route :path ""))))

(restas:mount-module upl (#:upload)
  (:url "upload")
  (:inherit-parent-context t)
  (upload:*store* *store*)
  (upload:*multiple* t)
  (upload:*mime-type* nil)
  (upload:*file-stored-callback*
   (lambda (files)
     (when *current-files*
       (mapcar #'(lambda (file)
                   (delete-file (file-path *store* file)))
               *current-files*))
     (setf *current-files* files)
     (let ((*print-pretty* nil))
       (format nil "parent.done([~{\"~a\"~^, ~}], ~
                                \'(~{\"~a\"~^ ~})\');"
               (mapcar #'(lambda (file)
                           (file-url *store* file))
                       files)
               files)))))

(defun safe-parse-integer (str)
  (let ((int (parse-integer str :junk-allowed t)))
    (if int int 0)))

(defun upload-form ()
  (restas:assert-native-module)
  (restas:in-submodule 'upl
    (upload:form)))

(restas:define-route add-pic ("add")
  (let ((father (hunchentoot:get-parameter "father"))
        (father-name (hunchentoot:get-parameter "father-name")))
    (add-pic-render (upload-form)
                    father
                    father-name)))

(restas:define-route add-album ("new-album")
  (let ((father (hunchentoot:get-parameter "father"))
        (father-name (hunchentoot:get-parameter "father-name")))
    (add-album-render (upload-form) father father-name )))

;; Parse a list, transmitted through the url get-parameter,
;; named param-name
(defun get-list-param (param-name)
  (with-input-from-string (lst (hunchentoot:get-parameter param-name))
    (read lst)))

;; Get a list of uploaded files, given by the url get-parameter,
;; named param-name
(defun get-uploaded-pictures (param-name)
  (setf *current-files* nil)
  (get-list-param param-name))

;; Make a list of pictures using the same title and comment from
;; a list of just raw files.
(defun make-pictures (files titles comments)
  (mapcar #'(lambda (file title comment)
              (make-picture *store* file title comment))
          files titles comments))

(restas:define-route receive-pic ("accept-pic")
  (let ((files (get-uploaded-pictures "pic"))
        (titles (get-list-param "title"))
        (comments (get-list-param "comment"))
        (father-id (safe-parse-integer (hunchentoot:get-parameter "father"))))
    (if (save-pictures-pic-coll (make-pictures files titles comments) father-id)
        (restas:redirect 'view-album :id father-id)
        (no-such-album-render father-id))))

(restas:define-route receive-album ("accept-album")
  (let ((files (get-uploaded-pictures "pic"))
        (titles (get-list-param "title"))
        (comments (get-list-param "comment"))
        (father-id (safe-parse-integer (hunchentoot:get-parameter "father"))))
    (if (save-album-pic-coll (make-album *store* (first files)
                                         (first titles) (first comments)) father-id)
        (restas:redirect 'view-album :id father-id)
        (no-such-album-render father-id))))
          
(restas:define-route main ("")
  (restas:redirect 'view-album :id (root-album-id-pic-coll)))

(restas:define-route view-album ("album/:id")
  (:sift-variables (id #'safe-parse-integer))
  (let ((album (get-item-pic-coll id)))
    (if album
        (view-album-render (restas:genurl 'add-pic :father (item-id album)
                                          :father-name (album-name album))
                           (restas:genurl 'add-album :father (item-id album)
                                          :father-name (album-name album))
                           (restas:genurl 'choose-pic :id id
                                          :action (restas:genurl 'delete-pic :id id))
                           album)
        (no-such-album-render id))))

(restas:define-route choose-pic ("album/choose/:id")
  (:sift-variables (id #'safe-parse-integer))
  (let ((album (get-item-pic-coll id))
        (action (hunchentoot:get-parameter "action")))
    (if album
        (choose-picture-render action album)
        (no-such-album-render id))))

(defun get-parameter-values (name)
  (mapcar #'cdr
          (remove name (hunchentoot:get-parameters*)
                  :test (complement #'equal)
                  :key #'car)))

(restas:define-route delete-pic ("album/delete/:id" :method :get)
  (:sift-variables (id #'safe-parse-integer))
  (let ((pics (get-parameter-values "chosen"))
        (album (get-item-pic-coll id)))
    (when album
        (album-delete-items album (mapcar #'parse-integer pics))
        (update-album-pic-coll album))
    (restas:redirect 'view-album :id id)))

(defun album-pics-grid (album &optional (chkbox nil))
  (restas:assert-native-module)
  (pics-grid-render album chkbox))

(defun draw-preview (content &optional (chkbox nil))
  (preview-render content chkbox))

