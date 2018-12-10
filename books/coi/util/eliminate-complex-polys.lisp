;; ===================================================================
;; 
;; Copyright (C) 2018, David Greve
;; All rights reserved.
;; 
;; This software may be modified and distributed under the terms of
;; the 3-clause BSD license.  See the LICENSE file distributed with
;; ACL2.
;; 
;; ===================================================================
(in-package "ACL2")

;; ===================================================================
;;
;; This book was inspired by the following comment from Matt Kaufmann:
;;
;; Interesting!  I wonder if this can be taken a step further, to
;; replace a complex inequality by two real inequalities.
;;
;; Note that after evaluating the first encapsulate in your book
;; [linearize-complex-polys] we can prove
;;
;; (thm (implies (and (rationalp x) (rationalp y))
;;               (iff (< 0 (+ x (* #c(0 1) y)))
;;                    (or (< 0 x)
;;                        (and (equal 0 x) (< 0 y)))))
;;      :hints (("Goal" :use ((:instance completion-of-<
;;                                       (x 0) (y (+ x (* #c(0 1) y))))))))
;;
;; Even proving equivalence of these two seems a bit of a challenge,
;; but I think it's essentially an instance of completion-of-<.  From
;; that equivalence, one could perhaps prove a useful meta rule that
;; splits an inequality involving (imaginary) into two inequalities,
;; one for the real parts and one for the imaginary parts.
;;
;; ===================================================================


;; ===================================================================
;;
;; meta-complex-rationalp tells us when to apply complex elimination
;; rules to an expression.  While technically the predicate is always
;; true, in practice we disable the definition and relay on the
;; following set of rules to determine whether a polynomial expression
;; contains a complex number.
;;
;; Note that we use "meta-complex-rationalp-realpart-imagpart" to
;; suggest that arguments of (realpart x) and (imagpart x) are
;; meta-complex-rationalp.  We use this to induce real/imag reduction
;; of variables in otherwise rational expressions when they have
;; already appeared in complex expressions.  Note that the example
;; at the end of this file will fail to prove without such a rule.
;;
;; ===================================================================

(encapsulate
    ()

  (set-tau-auto-mode nil)

  (defun meta-complex-rationalp (x)
    (declare (ignore x))
    t)
  
  (defthm complex-rationalp-implies-meta-complex-rationalp
    (implies
     (complex-rationalp x)
     (meta-complex-rationalp x))
    :rule-classes (:rewrite :type-prescription :forward-chaining))
  
  (defthm meta-complex-rationalp-complex
    (meta-complex-rationalp (complex x y)))
  
  (defthm meta-complex-rationalp-+
    (implies
     (or (meta-complex-rationalp x)
         (meta-complex-rationalp y))
     (meta-complex-rationalp (+ x y))))
  
  (defthm meta-complex-rationalp-*
    (implies
     (or (meta-complex-rationalp x)
         (meta-complex-rationalp y))
     (meta-complex-rationalp (* x y))))
  
  (defthm meta-complex-rationalp--
    (implies
     (meta-complex-rationalp x)
     (meta-complex-rationalp (- x))))
  
  (defthm meta-complex-rationalp-/
    (implies
     (meta-complex-rationalp x)
     (meta-complex-rationalp (/ x))))
  
  (defthm meta-complex-rationalp-realpart-imagpart
    (meta-complex-rationalp x)
    :rule-classes ((:forward-chaining :trigger-terms ((realpart x)
                                                      (imagpart x)))))

  )

(in-theory (disable meta-complex-rationalp
                    (meta-complex-rationalp)
                    (:type-prescription meta-complex-rationalp)))

;; ===================================================================
;;
;; The following reduction rules "get rid of" complex coefficients by
;; driving realpart/imagpart to the leaves of the expression.
;;
;; ===================================================================

(defthm realpart-rationalp
  (implies
   (rationalp x)
   (equal (realpart x)
          x)))

(defthm imagpart-rationalp
  (implies
   (rationalp x)
   (equal (imagpart x)
          0)))

(defthm realpart-complex-better
  (equal (realpart (complex x y))
         (rfix x))
  :hints (("Goal" :cases ((rationalp y)))))

(defthm imagpart-complex-better
  (equal (imagpart (complex x y))
         (rfix y))
  :hints (("Goal" :cases ((rationalp x)))))

(defthm realpart-+
  (equal (realpart (+ x y))
         (+ (realpart x) (realpart y))))

(defthm imagpart-+
  (equal (imagpart (+ x y))
         (+ (imagpart x) (imagpart y))))

(encapsulate
    ()

  (local (include-book "workshops/2006/cowles-gamboa-euclid/Euclid/ed5aa" :dir :system))

  (defthm realpart-*
    (equal (realpart (* x y))
           (- (* (realpart x)
                 (realpart y))
              (* (imagpart x)
                 (imagpart y)))))
  
  (defthm imagpart-*
    (equal (imagpart (* x y))
           (+ (* (realpart x)
                 (imagpart y))
              (* (imagpart x)
                 (realpart y)))))

  )

(encapsulate
    ()

  (local
   (defthm negate-to-times
     (equal (- x)
            (* -1 x))))
  
  (defthm realpart--
    (equal (realpart (- x))
           (- (realpart x))))
  
  (defthm imagpart--
    (equal (imagpart (- x))
           (- (imagpart x))))

  )

(encapsulate
    ()

  (local
   (encapsulate
       ()

     (defthmd strong-equal-acl2-numberp
       (implies
        (or (acl2-numberp x)
            (acl2-numberp y))
        (iff (equal x y)
             (and (acl2-numberp x)
                  (acl2-numberp y)
                  (equal (realpart x) (realpart y))
                  (equal (imagpart x) (imagpart y))))))

     (defthm non-zero-imagpart
       (implies
        (complex-rationalp x)
        (not (equal (imagpart x) 0)))
       :rule-classes ((:forward-chaining :trigger-terms ((imagpart x)))))
     
     (defthm non-negative-product
       (implies
        (rationalp x)
        (<= 0 (* x x)))
       :rule-classes (:linear
                      (:forward-chaining :trigger-terms ((binary-* x x)))))
     
     (defthm positive-product
       (implies
        (and
         (rationalp x)
         (not (equal x 0)))
        (< 0 (* x x)))
       :rule-classes (:linear
                      (:forward-chaining :trigger-terms ((binary-* x x)))))
     
     (defthm positive-expt
       (implies
        (and
         (rationalp x)
         (not (equal x 0)))
        (< 0 (expt x 2)))
       :hints (("Goal" :expand (:free (n) (expt x n))))
       :rule-classes (:linear
                      (:forward-chaining :trigger-terms ((expt x 2)))))
     
     (defthm non-negative-expt
       (implies
        (rationalp x)
        (<= 0 (expt x 2)))
       :hints (("Goal" :expand (:free (n) (expt x n))))
       :rule-classes (:linear
                      (:forward-chaining :trigger-terms ((expt x 2)))))
     
     (local (include-book "arithmetic-5/top" :dir :system))
     
     (defthmd definition-of-inverse
       (implies
        (equal (* x y) 1)
        (equal (/ x) y)))

     (defthm complex-reciporical
       (implies
        (complex-rationalp x)
        (equal (/ x)
               (/ (complex (realpart x) (- (imagpart x)))
                  (+ (* (realpart x) (realpart x)) (* (imagpart x) (imagpart x))))))
       :hints (("Goal" :use ((:instance definition-of-inverse
                                        (x x)
                                        (y (/ (complex (realpart x) (- (imagpart x)))
                                              (+ (* (realpart x) (realpart x)) (* (imagpart x) (imagpart x))))))
                             (:instance strong-equal-acl2-numberp
                                        (y 1)
                                     (x (* x
                                           (complex (realpart x) (- (imagpart x)))
                                           (/ (+ (expt (imagpart x) 2)
                                                 (expt (realpart x) 2))))))))))

     ))

  (defthm realpart-/
    (equal (realpart (/ x))
           (if (complex-rationalp x)
               (/ (realpart x)
                  (+ (* (realpart x) (realpart x)) (* (imagpart x) (imagpart x))))
             (/ x))))

  (defthm imagpart-/
    (equal (imagpart (/ x))
           (if (complex-rationalp x)
               (/ (- (imagpart x))
                  (+ (* (realpart x) (realpart x)) (* (imagpart x) (imagpart x))))
             0)))

  )
  
;; ===================================================================
;;
;; The following rules eliminate complex polys by replacing linear
;; expressions over complex polys with linear expressions over
;; rational polys.
;;
;; ===================================================================

(defthm <-meta-complex-rationalp
  (implies
   (or (meta-complex-rationalp x)
       (meta-complex-rationalp y))
   (iff (< x y)
        (or (< (realpart x) (realpart y))
            (and (equal (realpart x) (realpart y))
                 (< (imagpart x) (imagpart y))))))
  :hints (("Goal" :use completion-of-<)))

(defthm equal-meta-complex-rationalp
  (implies
   (and
    (or (meta-complex-rationalp x)
        (meta-complex-rationalp y))
    (or (acl2-numberp x)
        (acl2-numberp y)))
   (iff (equal x y)
        (and (acl2-numberp x)
             (acl2-numberp y)
             (equal (realpart x) (realpart y))
             (equal (imagpart x) (imagpart y))))))

(local
 (defthm complex-poly-test
   (implies
    (and
     (< 0 (+ (* #C( 1  2) x) (* #C(4  3) y)))
     (< 0 (+ (* #C(-1 -2) x) (* #C(0 -3) y)))
     (< 0 (+ (- y) -2))
     )
    nil)
   :rule-classes nil)
 )

