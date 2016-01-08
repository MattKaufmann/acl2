; Testing Facilities
;
; Copyright (C) 2015-2016 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Authors:
;   Alessandro Coglio (coglio@kestrel.edu)
;   Eric Smith (eric.smith@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This file contains macros for building tests,
; related to MUST-SUCCEED and MUST-FAIL.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "ACL2")

(include-book "std/util/top" :dir :system)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defxdoc must-succeed*

  :parents (kestrel-general-utilities errors)

  :short
  "A version of @(tsee must-succeed)
  that takes multiple forms
  and uses default options."

  :long "@(def must-succeed*)")

(defmacro must-succeed* (&rest forms)
  `(must-succeed (progn ,@forms)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defxdoc must-succeed**

  :parents (kestrel-general-utilities errors)

  :short
  "A version of @(tsee must-succeed)
  that takes multiple forms
  and explicit options."

  :long
  "<p>
  The first two arguments are
  the @(':with-output-off') and @(':check-expansion') options
  of @(tsee must-succeed).
  The remaining arguments are the forms.
  </p>
  @(def must-succeed**)")

(defmacro must-succeed** (with-output-off check-expansion &rest forms)
  `(must-succeed (progn ,@forms)
                 :with-output-off ,with-output-off
                 :check-expansion ,check-expansion))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defxdoc must-be-redundant

  :parents (kestrel-general-utilities errors)

  :short
  "A top-level @(tsee assert$)-like command
  to ensure that given forms are redundant."

  :long
  "<p>
  The forms are put into an @(tsee encapsulate),
  along with a @(tsee set-enforce-redundancy) command that precedes them.
  </p>
  @(def must-be-redundant)")

(defmacro must-be-redundant (&rest forms)
  `(encapsulate
     ()
     (set-enforce-redundancy t)
     ,@forms))
