(defpackage #:gallery.mongo-db-pics-collection
  (:use #:cl #:gallery.content #:mongo.sugar #:iterate
        #:gallery.policy.pics-collection)
  (:export #:handler
           #:make))

(in-package #:gallery.mongo-db-pics-collection)

(defclass handler ()
  ((dbspec :initarg :dbspec :initform '(:name "gallery") :reader dbspec)
   (db :accessor actual-db :initform nil
       :documentation "The actual connection to the mongo database")
   (db-open-counter :accessor db-open-counter :initform 0
                    :documentation "The counter of open - closes")))

(defun make (&rest dbspec)
  (make-instance 'handler :dbspec dbspec))

;; TODO: discover a way to save the number of connections in nesteed queries

#+nil
(defun open-db (db)
  (incf (db-open-counter db))
  (if (actual-db db)
      (actual-db db)
      (setf (actual-db db) (apply 'make-instance 'mongo:database (dbspec db)))))
#+nil
(defun close-db (db)
  (when (> (db-open-counter db) 0)
    (decf (db-open-counter db))
    (when (<= (db-open-counter db) 0)
      (mongo:close-database (actual-db db))
      (setf (actual-db db) nil))))
#+nil
(defmacro with-open-db ((db-name db) &body body)
  `(let ((,db-name (open-db ,db)))
     (unwind-protect
          (progn ,@body)
       (close-db ,db))))

(defmacro with-open-db ((db-name db) &body body)
  (let ((client-name (gensym))
        (dbspec-name (gensym)))
    `(let ((,dbspec-name (dbspec ,db)))
       (mongo:with-client 
           (,client-name (mongo:create-mongo-client 
                          :usocket
                          :server (make-instance 'mongo:server-config
                                                 :hostname 
                                                 (getf ,dbspec-name :hostname)
                                                 :port
                                                 (getf ,dbspec-name :port))))
         (let ((,db-name (make-instance 'mongo:database
                                        :mongo-client ,client-name
                                        :name (getf ,dbspec-name :name))))
           ,@body)))))
            
(defmacro with-a-collection ((coll name db) &body body)
  (let ((base-name (gensym)))
    `(with-open-db (,base-name ,db)
       (let ((,coll (mongo:collection ,base-name ,name)))
         ,@body))))

(defmacro with-pics-collection ((name db) &body body)
  `(with-a-collection (,name "galitems" ,db) ,@body))

(defmacro with-misc-collection ((name db) &body body)
  `(with-a-collection (,name "galmisc" ,db) ,@body))

(defun init-db (db)
  (with-misc-collection (coll db)
    (mongo:insert-op coll (son "_id" "nextid" "seq" 0))
    (let ((root-album (make-root-album "Hi, \<bro\> ..." "I'm your father, Luke")))
      (mongo:insert-op coll (son "_id" "rootid" "val" (item-id root-album)))
      (with-pics-collection (pics db)
        (mongo:insert-op pics (item-to-ht root-album)))
      (item-id root-album))))

(defgeneric read-item-from-hash-table (type hash-table db)
  (:documentation "Get an item from the given hash-table "))
(defgeneric write-item-to-hash-table (item)
  (:documentation "Write all neccesary data to a hash table,
   for further recreation a copy of the item"))

(defmethod write-item-to-hash-table ((time local-time:timestamp))
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash "val" table) time)
    table))

(defmethod write-item-to-hash-table ((time period))
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash "begin" table) (period-begin time))
    (setf (gethash "end" table) (period-end time))
    table))

(defmethod write-item-to-hash-table ((item item))
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash "_id" table) (item-id item))
    (setf (gethash "ownerid" table) (item-owner-id item))
    (setf (gethash "thumbnail" table) (item-thumbnail item))
    (setf (gethash "title" table) (item-title item))
    (setf (gethash "comment" table) (item-comment item))
    (setf (gethash "time" table) (write-item-to-hash-table (item-time item)))
    table))

(defmethod write-item-to-hash-table ((item picture))
  (let ((table (call-next-method)))
    (setf (gethash "url" table) (pic-url item))
    table))

(defmethod write-item-to-hash-table ((item album))
  (let ((table (call-next-method)))
    (setf (gethash "name" table) (album-name item))
    (setf (gethash "items" table) (mapcar #'item-id (album-items item)))
    table))
          

(defmethod read-item-from-hash-table ((type (eql :timestamp)) ht db)
  (gethash "val" ht))

(defmethod read-item-from-hash-table ((type (eql :period)) ht db)
  (make-embracing-period (list (gethash "begin" ht) (gethash "end" ht))))

(defmethod read-item-from-hash-table ((type (eql :picture)) ht db)
  (make-instance 'picture
                 :id (gethash "_id" ht)
                 :owner-id (gethash "ownerid" ht)
                 :url (gethash "url" ht)
                 :thumbnail (gethash "thumbnail" ht)
                 :title (gethash "title" ht)
                 :time (read-item-from-hash-table
                        :timestamp (gethash "time" ht) db)
                 :comment (gethash "comment" ht)))

(defmethod read-item-from-hash-table ((type (eql :album)) ht db)
  (make-instance 'album
                 :id (gethash "_id" ht)
                 :owner-id (gethash "ownerid" ht)
                 :name (gethash "name" ht)
                 :title (gethash "title" ht)
                 :comment (gethash "comment" ht)
                 :thumbnail (gethash "thumbnail" ht)
                 :time (read-item-from-hash-table
                        :period (gethash "time" ht) db)
                 :items (mapcar #'(lambda (id)
                                    (p-coll.get-item db id))
                                (gethash "items" ht))))

(defun item-from-ht (hash-table db)
  (when hash-table
    (let ((type (intern (string-upcase (gethash "type" hash-table)) :keyword)))
      (read-item-from-hash-table type hash-table db))))

(defun item-to-ht (item)
  (let ((table (write-item-to-hash-table item)))
    (setf (gethash "type" table) (symbol-name (type-of item)))
    table))

;; TODO: restrict the depth
(defmethod p-coll.get-item ((db handler) (id number))
  (with-pics-collection (pics db)
    (item-from-ht
     (mongo:find-one pics :query (son "_id" id)) db)))

(defmethod p-coll.save-pictures ((db handler) pics father-id)
  (let ((father (p-coll.get-item db father-id))
        (period (make-embracing-period pics)))
    (when father
      (adjust-album-period #'(lambda (it) (p-coll.update-item db it))
                           father period)
      (setf (album-items father) (append pics (album-items father)))
      (with-pics-collection (items db)
        (iter (for pic in pics)
              (mongo:insert-op items (item-to-ht pic)))
        (mongo:update-op items (son "_id" (item-id father)) (item-to-ht father)))
      t)))

(defmethod p-coll.save-album ((db handler) album father-id)
  (let ((father (p-coll.get-item db father-id)))
    (when father
      (push album (album-items father))
      (with-pics-collection (pics db)
      (adjust-album-period #'(lambda (it) (p-coll.update-item db it))
                           father (item-time album))
        (mongo:insert-op pics  (item-to-ht album))
        (mongo:update-op pics (son "_id" (item-id father)) (item-to-ht father)))
      t)))

;; Todo: check for deleted pictures from the album, and delete them?
(defmethod p-coll.update-item ((db handler) item)
  (with-pics-collection (pics db)
    (mongo:update-op pics (son "_id" (item-id item)) (item-to-ht item)))
  (when (item-owner-id item)
    (adjust-album-period #'(lambda (it) (p-coll.update-item db it))
                       (p-coll.get-item db (item-owner-id item))
                       (item-time item))))

(defmethod p-coll.gen-uniq-id ((db handler))
  (with-misc-collection (misc db)
    (let ((id (mongo:find-one misc :query (son "_id" "nextid"))))
      (mongo:update-op misc (son "_id" "nextid") (son "seq" (incf (gethash "seq" id))))
      (gethash "seq" id))))

(defmethod p-coll.root-album-id ((db handler))
  (let ((root-id (with-misc-collection (misc db)
                   (mongo:find-one misc :query (son "_id" "rootid")))))
    (if root-id
        (gethash "val" root-id)
        (init-db db))))
  