
(defpackage :transliterate
  (:use :cl-user :cl)
  (:export :transliterate))

(in-package :transliterate)

(defun transliterate (str)
  (let ((correspondence
         '((#\а . "a")
           (#\б . "b")
           (#\в . "v")
           (#\г . "g")
           (#\д . "d")
           (#\е . "e")
           (#\ё . "yo")
           (#\ж . "g")
           (#\з . "z")
           (#\и . "i")
           (#\й . "y")
           (#\к . "k")
           (#\л . "l")
           (#\м . "m")
           (#\н . "n")
           (#\о . "o")
           (#\п . "p")
           (#\р . "r")
           (#\с . "s")
           (#\т . "t")
           (#\у . "u")
           (#\ф . "f")
           (#\х . "kh")
           (#\ц . "ts")
           (#\ч . "ch")
           (#\ш . "sh")
           (#\щ . "shch")
           (#\ь . "")
           (#\ы . "i")
           (#\ъ . "")
           (#\э . "a")
           (#\ю . "u")
           (#\я . "ya")
           (#\SPACE  . ".")
           (#\COMMA . ".")
           (#\! . ".")
           (#\? . "."))))
    (with-output-to-string (out)
      (loop for c across str do
            (let ((change (assoc c correspondence)))
              (if change
                  (write-string (cdr change) out)
                  (write-char c out)))))))
        
        
