;; Processing Unicode Files with ACL2
;; Copyright (C) 2005-2006 by Jared Davis <jared@cs.utexas.edu>
;;
;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.
;;
;; You should have received a copy of the GNU General Public License along with
;; this program; if not, write to the Free Software Foundation, Inc., 59 Temple
;; Place - Suite 330, Boston, MA 02111-1307, USA.

(in-package "ACL2")

(include-book "app")

(include-book "arithmetic/nat-listp" :dir :system)

(defthm nat-listp-of-app
  (implies (true-listp x)
           (equal (nat-listp (app x y))
                  (and (nat-listp x)
                       (nat-listp (list-fix y)))))
  :hints(("Goal" :induct (len x))))

(defthm natp-of-car-when-nat-listp
  (implies (nat-listp x)
           (and (equal (integerp (car x))
                       (consp x))
                (<= 0 (car x))))
  :hints(("Goal" :induct (len x))))
