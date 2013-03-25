(asdf:operate 'asdf:load-op :gallery)

(restas:define-module #:gallery.example
    (:use :cl)
  (:export main))

(in-package #:gallery.example)

(restas:define-route main ("")
  "<H1> This is a cl-gallery usage example </h1>
  You can try it <a href=\"gal/\" >here </a>")

(restas:mount-module test-gallery (#:gallery)
  (:url "gal")
  (gallery.internal.render:*render* (make-instance 'gallery.default-render:handler)))

(restas:start '#:gallery.example :port 8082)