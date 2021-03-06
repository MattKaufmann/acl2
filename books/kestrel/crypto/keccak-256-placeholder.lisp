; Cryptography -- Keccak-256 Placeholder
;
; Copyright (C) 2019 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Author: Alessandro Coglio (coglio@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "CRYPTO")

(include-book "kestrel/fty/byte-list32" :dir :system)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defsection keccak-256-placeholder
  :parents (placeholders)
  :short "Keccak-256 placeholder."
  :long
  (xdoc::topstring
   (xdoc::p
    "Keccak-256 is specified in the
     <a href=\"https://keccak.team/keccak.html\">Keccak web site</a>,
     in particular `The Keccak Reference' document, Version 3.0.")
   (xdoc::p
    "According to the aforementioned specification,
     the input of Keccak-256 is a sequence of any number of bits,
     or any number of bytes.
     This is formalized by the guard of the constrained function below.")
   (xdoc::p
    "According to the aforementioned specification,
     the output of Keccak-256 is a sequence of exactly 256 bits, or 32 bytes.
     We constrain our function to return a list of 32 bytes unconditionally.")
   (xdoc::p
    "We also constrain our function to fix its input to a true list of bytes.")
   (xdoc::@def "keccak-256"))

  (encapsulate

    (((keccak-256 *) => *
      :formals (bytes)
      :guard (byte-listp bytes)))

    (local
     (defun keccak-256 (bytes)
       (declare (ignore bytes))
       (make-list 32 :initial-element 0)))

    (defrule byte-list32p-of-keccak-256
      (byte-list32p (keccak-256 bytes)))

    (defrule len-of-keccak-256
      (equal (len (keccak-256 bytes))
             32))

    (fty::deffixequiv keccak-256
      :args ((bytes byte-listp))))

  (defrule true-listp-of-keccak-256
    (true-listp (keccak-256 bytes))
    :rule-classes :type-prescription
    :enable acl2::true-listp-when-byte-listp)

  (defrule consp-of-keccak-256
    (consp (keccak-256 bytes))
    :rule-classes :type-prescription
    :use len-of-keccak-256
    :disable len-of-keccak-256))
