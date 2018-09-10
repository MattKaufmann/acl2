; X86ISA Library

; Note: The license below is based on the template at:
; http://opensource.org/licenses/BSD-3-Clause

; Copyright (C) 2015, Regents of the University of Texas
; All rights reserved.

; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are
; met:

; o Redistributions of source code must retain the above copyright
;   notice, this list of conditions and the following disclaimer.

; o Redistributions in binary form must reproduce the above copyright
;   notice, this list of conditions and the following disclaimer in the
;   documentation and/or other materials provided with the distribution.

; o Neither the name of the copyright holders nor the names of its
;   contributors may be used to endorse or promote products derived
;   from this software without specific prior written permission.

; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
; HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

; Original Author(s):
; Shilpi Goel         <shigoel@cs.utexas.edu>

(in-package "X86ISA")

;; ----------------------------------------------------------------------

(include-book "instructions/top"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "dispatch-macros")
(include-book "std/strings/hexify" :dir :system)

(local (include-book "dispatch"))
(local (include-book "centaur/bitops/ihs-extensions" :dir :system))
(local (include-book "centaur/bitops/signed-byte-p" :dir :system))

(local (in-theory (e/d ()
                       (app-view-rml08-no-error
                        (:meta acl2::mv-nth-cons-meta)
                        rme08-value-when-error
                        member-equal))))

;; ----------------------------------------------------------------------

(defsection x86-decoder
  :parents (machine)
  :short "Definitions of the x86 fetch, decode, and execute function
  and the top-level run function"
  )

(defsection implemented-opcodes
  :parents (x86isa instructions x86-decoder)
  :short "Intel Opcodes Supported in @('x86isa')"
  :long

  "<h3>How to Read the Opcode Tables</h3>

 <p>The opcode tables have 2^8 = 256 rows, one row for each relevant opcode
 byte (i.e., the only opcode byte for one-byte opcodes in @(see
 one-byte-opcodes-table), the second opcode byte for the two-byte opcodes in
 @(see two-byte-opcodes-table), and the third opcode byte for the three-byte
 opcodes in @(see 0F-38-three-byte-opcodes-table) and @(see
 0F-3A-three-byte-opcodes-table)).  Each row lists the opcode, the name of the
 Intel instruction corresponding to it, and the instruction semantic function
 that implements that opcode.</p>

 <p>Often, just the opcode byte is not enough to determine the x86 instruction.
 We may need to know the processor's mode of operation (e.g., 32-bit or 64-bit
 mode), the value in the fields of the ModR/M byte (the so-called opcode
 extensions grouped together in Intel Volume 2, Table A-6), the mandatory
 prefixes, etc.  The following keywords are used to describe such information
 in these tables.</p>

 <ul>
   <li>@(':i64'):    Invalid in 64-bit mode</li>
   <li>@(':o64'):    Valid only in 64-bit mode</li>
   <li>@(':reg'):    Value of ModR/M.reg</li>
   <li>@(':mod'):    Value of ModR/M.mod</li>
   <li>@(':r/m'):    Value of ModR/M.r/m</li>
   <li>@(':66'):     Mandatory Prefix 0x66</li>
   <li>@(':F2'):     Mandatory Prefix 0xF2</li>
   <li>@(':F3'):     Mandatory Prefix 0xF3</li>
   <li>@(':No-Pfx'): No Mandatory Prefix</li>
 </ul>

 <p>Instead of the instruction semantic function, these tables may also list
 <i>Reserved</i> or <i>Unimplemented</i> for certain opcodes.  <i>Reserved</i>
 stands for opcodes that Intel deems reserved --- an x86 processor is supposed
 to throw a @('#UD') (undefined instruction) exception if that opcode is
 encountered --- we call @(tsee x86-illegal-instruction) in such cases.
 <i>Unimplemented</i> stands for legal x86 instructions that are not yet
 supported in @('x86isa') --- we call @(tsee x86-step-unimplemented) in such
 cases.</p>"

  )

(local (xdoc::set-default-parents x86-decoder))

;; ----------------------------------------------------------------------

(define get-prefixes
  ((proc-mode :type (integer 0 #.*num-proc-modes-1*))
   (start-rip :type (signed-byte #.*max-linear-address-size*))
   (prefixes  :type (unsigned-byte #.*prefixes-width*))
   (rex-byte  :type (unsigned-byte 8))
   (cnt       :type (integer 0 15))
   x86)

  :guard (prefixes-p prefixes)
  :guard-hints
  (("Goal" :in-theory
    (e/d ()
         (negative-logand-to-positive-logand-with-integerp-x
          signed-byte-p))))

  :measure (nfix cnt)
  :hints (("Goal" :in-theory (e/d () ((tau-system)))))

  :returns
  (mv flg

      (new-prefixes natp :rule-classes :type-prescription
                    :hyp (forced-and (natp prefixes)
                                     (canonical-address-p start-rip)
                                     (x86p x86))
                    :hints
                    (("Goal"
                      :in-theory
                      (e/d ()
                           (force
                            (force)
                            acl2::zp-open not
                            unsigned-byte-p
                            signed-byte-p
                            negative-logand-to-positive-logand-with-integerp-x
                            acl2::ash-0
                            unsigned-byte-p-of-logior
                            acl2::zip-open
                            bitops::unsigned-byte-p-incr)))))

      (new-rex-byte natp :rule-classes :type-prescription
                    :hyp (forced-and (natp rex-byte)
                                     (natp prefixes)
                                     (x86p x86))
                    :hints
                    (("Goal"
                      :in-theory
                      (e/d ()
                           (force
                            (force)
                            acl2::zp-open not
                            unsigned-byte-p
                            signed-byte-p
                            negative-logand-to-positive-logand-with-integerp-x
                            acl2::ash-0
                            unsigned-byte-p-of-logior
                            acl2::zip-open
                            bitops::unsigned-byte-p-incr)))))

      (new-x86 x86p
               :hyp (forced-and (x86p x86)
                                (canonical-address-p start-rip))
               :hints
               (("Goal"
                 :in-theory
                 (e/d ()
                      (acl2::zp-open
                       force (force)
                       not
                       unsigned-byte-p
                       signed-byte-p
                       acl2::ash-0
                       acl2::zip-open
                       bitops::logtail-of-logior
                       unsigned-byte-p-of-logtail
                       acl2::logtail-identity
                       ash-monotone-2
                       bitops::logand-with-negated-bitmask
                       (:linear bitops::logior-<-0-linear-1)
                       (:linear bitops::logior-<-0-linear-2)
                       (:linear bitops::logand->=-0-linear-1)
                       (:linear bitops::logand->=-0-linear-2)
                       bitops::logtail-natp
                       natp-of-get-one-byte-prefix-array-code
                       acl2::ifix-when-not-integerp
                       bitops::basic-signed-byte-p-of-+
                       default-<-1
                       negative-logand-to-positive-logand-with-integerp-x
                       negative-logand-to-positive-logand-with-n52p-x))))))

  :parents (x86-decoder)

  :short "Fetch and store legacy and REX prefixes, if any, of an instruction"

  :long "<p>The function @('get-prefixes') fetches the legacy and REX prefixes
  of an instruction and also returns the first byte following the last such
  prefix.  The input @('start-rip') points to the first byte of an instruction,
  which may potentially be a legacy prefix.  The initial value of @('cnt')
  should be @('15') so that the result @('(- 15 cnt)') returned at the end of
  the recursion is the correct number of legacy and/or REX bytes parsed by this
  function.</p>

  <h3>Legacy Prefixes</h3>

  <p>From Intel Manual, Vol. 2, May 2018, Section 2.1.1 (Instruction
  Prefixes):</p>

  <p><em>Instruction prefixes are divided into four groups, each with a set of
     allowable prefix codes. For each instruction, it is only useful to include
     up to one prefix code from each of the four groups (Groups 1, 2, 3,
     4). Groups 1 through 4 may be placed in any order relative to each
     other.</em></p>

  <p>Despite the quote from the Intel Manual above, the order of the legacy
  prefixes does matter when there is more than one prefix from the same group
  --- <b>all but the last prefix from a single prefix group are ignored</b>.
  The only <b>exception</b> in this case is for <b>Group 1</b> prefixes --- see
  below for details.</p>

  <ul>
  <li>@('0x64_88_00')    is @('mov byte ptr fs:[rax], al')</li>
  <li>@('0x65_88_00')    is @('mov byte ptr gs:[rax], al')</li>
  <li>@('0x64_65_88_00') is @('mov byte ptr gs:[rax], al')</li>
  <li>@('0x65_64_88_00') is @('mov byte ptr fs:[rax], al')</li>
  </ul>

  <ul>
  <li>@('0xf2_a4')    is @('repne movsb byte ptr [rdi], byte ptr [rsi]')</li>
  <li>@('0xf3_a4')    is @('repe  movsb byte ptr [rdi], byte ptr [rsi]')</li>
  <li>@('0xf2_f3_a4') is @('repe  movsb byte ptr [rdi], byte ptr [rsi]')</li>
  <li>@('0xf3_f2_a4') is @('repne movsb byte ptr [rdi], byte ptr [rsi]')</li>
  </ul>

  <p>We now discuss the Group 1 exception below.</p>

  <p>@('0xf0_f2_a4') is <b>NOT</b> <br/>
  @('repne movsb byte ptr [rdi], byte ptr [rsi]') <br/>
  It is: <br/>
  @('lock repne movsb byte ptr [rdi], byte ptr [rsi]') <br/>

  Note that lock and rep/repne are Group 1 prefixes.  It is important to record
  the lock prefix, even if it is overshadowed by a rep/repne prefix, because
  the former instruction will not @('#UD'), but the latter instruction will.
  This is akin to the lock prefix being in a separate group than the rep/repne
  prefixes; in fact, AMD manuals (Section 1.2.1: Summary of Legacy Prefixes,
  Vol. 3 May 2018 Edition) treat them as such.</p>

  <p>For details about how mandatory prefixes are picked from legacy prefixes,
  see @(see mandatory-prefixes-computation).</p>

  <h3>REX Prefixes</h3>

  <p>A REX prefix (applicable only to 64-bit mode) is treated as a null prefix
  if it is followed by a legacy prefix.  Here is an illustrative example (using
  Intel's XED, x86 Encoder Decoder --- see
  @('https://intelxed.github.io/')):</p>

  <ul>

  <li>@('xed -64 -d 48670100') is @('add dword ptr [eax], eax'); the REX.W
  prefix does not have any effect on the operand size, which remains 32 (i.e.,
  the default operand size in the 64-bit mode).</li>

  <li>@('xed -64 -d 67480100') is @('add qword ptr [eax], rax'); the REX prefix
  has the intended effect of promoting the operand size to 64 bits.</li>

  </ul>

  <p>Note that the prefixes structure output of this function does not include
  the REX byte (which is a separate return value of this function), but its
  @(':num-prefixes') field includes a count of the REX prefixes encountered.
  This is because adding an 8-bit field to the prefixes structure to store a
  REX byte will make it a bignum, thereby impacting execution efficiency.</p>"

  :prepwork

  ((defthm return-type-of-prefixes->num-linear
     (< (prefixes->num prefixes) 16)
     :hints (("Goal" :in-theory (e/d (prefixes->num) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->lck-linear
     (< (prefixes->lck prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->lck) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->rep-linear
     (< (prefixes->rep prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->rep) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->seg-linear
     (< (prefixes->seg prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->seg) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->opr-linear
     (< (prefixes->opr prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->opr) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->adr-linear
     (< (prefixes->adr prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->adr) ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->nxt-linear
     (< (prefixes->nxt prefixes) 256)
     :hints (("Goal" :in-theory (e/d (prefixes->nxt prefixes-fix)
                                     ())))
     :rule-classes :linear)

   (defthm return-type-of-prefixes->num-rewrite
     (unsigned-byte-p 4 (prefixes->num prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->num) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->lck-rewrite
     (unsigned-byte-p 8 (prefixes->lck prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->lck) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->rep-rewrite
     (unsigned-byte-p 8 (prefixes->rep prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->rep) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->seg-rewrite
     (unsigned-byte-p 8 (prefixes->seg prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->seg) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->opr-rewrite
     (unsigned-byte-p 8 (prefixes->opr prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->opr) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->adr-rewrite
     (unsigned-byte-p 8 (prefixes->adr prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->adr) ())))
     :rule-classes :rewrite)

   (defthm return-type-of-prefixes->nxt-rewrite
     (unsigned-byte-p 8 (prefixes->nxt prefixes))
     :hints (("Goal" :in-theory (e/d (prefixes->nxt prefixes-fix)
                                     ())))
     :rule-classes :rewrite)

   (encapsulate
     ()

     (local (include-book "arithmetic-5/top" :dir :system))

     (defthm return-type-of-!prefixes->*-linear
       (and (< (!prefixes->num x prefixes) #.*2^52*)
            (< (!prefixes->lck x prefixes) #.*2^52*)
            (< (!prefixes->rep x prefixes) #.*2^52*)
            (< (!prefixes->seg x prefixes) #.*2^52*)
            (< (!prefixes->opr x prefixes) #.*2^52*)
            (< (!prefixes->adr x prefixes) #.*2^52*)
            (< (!prefixes->nxt x prefixes) #.*2^52*))
       :hints (("Goal" :in-theory
                (e/d* (loghead
                       !prefixes->num
                       !prefixes->lck
                       !prefixes->rep
                       !prefixes->seg
                       !prefixes->opr
                       !prefixes->adr
                       !prefixes->nxt
                       prefixes-fix
                       num-prefixes-fix
                       lck-fix rep-fix seg-fix
                       opr-fix adr-fix next-byte-fix)
                      (bitops::logand-with-negated-bitmask))))
       :rule-classes :linear))

   (local
    (encapsulate
      ()

      (local (include-book "arithmetic-5/top" :dir :system))

      (defthm get-prefixes-storing-last-byte-lemma
        (implies (unsigned-byte-p 8 byte)
                 (< (logior (logand 4503599626326015 prefixes)
                            (ash byte 12))
                    4503599627370496))
        :rule-classes :linear)

      (defthm negative-logand-to-positive-logand-with-n52p-x
        (implies (and (< n 0)
                      (syntaxp (quotep n))
                      (equal m 52)
                      (integerp n)
                      (n52p x))
                 (equal (logand n x)
                        (logand (logand (1- (ash 1 m)) n) x))))))

   (defthm loghead-ash-0
     (implies (and (natp i)
                   (natp j)
                   (natp x)
                   (<= i j))
              (equal (loghead i (ash x j))
                     0))
     :hints (("Goal"
              :in-theory (e/d* (acl2::ihsext-inductions
                                acl2::ihsext-recursive-redefs)
                               ()))))

   (local
    (defthm signed-byte-p-48-lemma
      (implies (signed-byte-p 48 start-rip)
               (equal (signed-byte-p 48 (1+ start-rip))
                      (< (1+ start-rip) *2^47*)))))

   (local (in-theory (e/d () (unsigned-byte-p)))))


  (if (mbe :logic (zp cnt)
           :exec (eql cnt 0))
      ;; Error, too many prefix bytes --- invalid instruction length.
      (mv t prefixes rex-byte x86)

    (b* ((ctx 'get-prefixes)
         ((mv flg (the (unsigned-byte 8) byte) x86)
          (rme08 proc-mode start-rip #.*cs* :x x86))
         ((when flg)
          (mv (cons ctx flg) byte rex-byte x86))

         (prefix-byte-group-code
          (the (integer 0 4) (get-one-byte-prefix-array-code byte))))

      (case prefix-byte-group-code

        (0
         (b* ((rex? (and
                     (eql proc-mode #.*64-bit-mode*)
                     (equal (the (unsigned-byte 4) (ash byte -4)) 4)))
              ((when rex?)
               (mv-let
                 (flg next-rip)
                 (add-to-*ip proc-mode start-rip 1 x86)
                 (if flg
                     (mv flg prefixes rex-byte x86)
                   (get-prefixes
                    proc-mode next-rip prefixes
                    byte ;; REX prefix, overwriting a previously encountered REX,
                    ;; if any
                    (the (integer 0 15) (1- cnt))
                    x86)))))
           ;; Storing the number of prefixes seen and the first byte
           ;; following the prefixes in "prefixes":
           (let ((prefixes
                  (the (unsigned-byte #.*prefixes-width*)
                    (!prefixes->nxt byte prefixes))))
             (mv nil
                 (the (unsigned-byte #.*prefixes-width*)
                   (!prefixes->num (- 15 cnt) prefixes))
                 rex-byte ;; Preserving rex-byte
                 x86))))

        (1
         ;; LOCK (F0), REPE (F3), REPNE (F2)
         (b* (((mv flg next-rip)
               (add-to-*ip proc-mode start-rip 1 x86))
              ((when flg)
               (mv flg prefixes rex-byte x86))
              ((the (unsigned-byte #.*prefixes-width*) prefixes)
               (if (equal byte #.*lock*)
                   (!prefixes->lck byte prefixes)
                 (!prefixes->rep byte prefixes))))
           ;; Storing the group 1 prefix (possibly overwriting a
           ;; previously seen group 1 prefix) and going on...
           (get-prefixes
            proc-mode next-rip prefixes
            0 ;; Nullify a previously read REX prefix, if any
            (the (integer 0 15) (1- cnt)) x86)))

        (2
         ;; ES (26), CS (2E), SS (36), DS (3E), FS (64), GS (65)
         (b* (((mv flg next-rip)
               (add-to-*ip proc-mode start-rip 1 x86))
              ((when flg)
               (mv flg prefixes rex-byte x86)))

           (if (or
                ;; In 64-bit mode, all segment override prefixes except FS
                ;; and GS overrides are treated as null prefixes.  So a
                ;; segment override prefix other than the FS and GS overrides
                ;; cannot overshadow a FS/GS override.  In case two or more
                ;; FS/GS overrides are present, all but the last are ignored.

                ;; Source: XED (https://intelxed.github.io/)
                ;; Some tests:
                ;; xed -64 -d 260f0100     => sgdt ptr [rax]
                ;; xed -64 -d 640f0100     => sgdt ptr fs:[rax]
                ;; xed -64 -d 64260f0100   => sgdt ptr fs:[rax]
                ;; xed -64 -d 6426650f0100 => sgdt ptr gs:[rax]
                (and (eql proc-mode #.*64-bit-mode*)
                     (or (equal byte #.*fs-override*)
                         (equal byte #.*gs-override*)))
                ;; All segment overrides are active in the 32-bit mode, and
                ;; all but the last one are ignored.
                (not (eql proc-mode #.*64-bit-mode*)))

               ;; Storing the group 2 prefix (possibly overwriting a
               ;; previously seen group 2 prefix) and going on...

               (get-prefixes
                proc-mode next-rip
                (the (unsigned-byte #.*prefixes-width*)
                  (!prefixes->seg byte prefixes))
                0 ;; Nullify a previously read REX prefix, if any
                (the (integer 0 15) (1- cnt))
                x86)

             ;; We will be here if we are in the 64-bit mode and have seen a
             ;; null segment override prefix; we will not store the prefix
             ;; but simply decrement cnt.
             (get-prefixes proc-mode next-rip prefixes
                           0 ;; Nullify a previously read REX prefix, if any
                           (the (integer 0 15) (1- cnt)) x86))))

        (3
         ;; Operand-Size Override (66)
         (mv-let
           (flg next-rip)
           (add-to-*ip proc-mode start-rip 1 x86)
           (if flg
               (mv flg prefixes rex-byte x86)
             ;; Storing the group 3 prefix (possibly overwriting a
             ;; previously seen group 3 prefix) and going on...
             (get-prefixes
              proc-mode next-rip
              (the (unsigned-byte #.*prefixes-width*)
                (!prefixes->opr byte prefixes))
              0 ;; Nullify a previously read REX prefix, if any
              (the (integer 0 15) (1- cnt))
              x86))))

        (4
         ;; Address-Size Override (67)
         (mv-let
           (flg next-rip)
           (add-to-*ip proc-mode start-rip 1 x86)
           (if flg
               (mv flg prefixes rex-byte x86)
             ;; Storing the group 4 prefix (possibly overwriting a
             ;; previously seen group 4 prefix) and going on...
             (get-prefixes
              proc-mode next-rip
              (the (unsigned-byte #.*prefixes-width*)
                (!prefixes->adr byte prefixes))
              0 ;; Nullify a previously read REX prefix, if any
              (the (integer 0 15) (1- cnt))
              x86))))

        (otherwise
         (mv t prefixes rex-byte x86)))))

  ///

  (local (in-theory (e/d () (acl2::zp-open not))))

  (defthm-usb prefixes-width-p-of-get-prefixes.new-prefixes
    ;; [Shilpi] I tried to use defret here instead of defthm-usb, but I got
    ;; into trouble, probably because of the different order of lambda
    ;; expansions in defret.
    :hyp (and (unsigned-byte-p #.*prefixes-width* prefixes)
              (canonical-address-p start-rip)
              (x86p x86))
    :bound #.*prefixes-width*
    :concl (mv-nth 1 (get-prefixes
                      proc-mode start-rip prefixes rex-byte cnt x86))
    :hints (("Goal"
             :induct (get-prefixes
                      proc-mode start-rip prefixes rex-byte cnt x86)
             :in-theory (e/d ()
                             (signed-byte-p
                              acl2::ash-0
                              acl2::zip-open
                              bitops::logtail-of-logior
                              unsigned-byte-p-of-logtail
                              acl2::logtail-identity
                              ash-monotone-2
                              bitops::logand-with-negated-bitmask
                              (:linear bitops::logior-<-0-linear-1)
                              (:linear bitops::logior-<-0-linear-2)
                              (:linear bitops::logand->=-0-linear-1)
                              (:linear bitops::logand->=-0-linear-2)
                              bitops::logtail-natp
                              natp-of-get-one-byte-prefix-array-code
                              acl2::ifix-when-not-integerp
                              bitops::basic-signed-byte-p-of-+
                              default-<-1
                              force (force)))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d () (get-prefixes)))))

  (defthm-usb byte-p-of-get-prefixes.new-rex-byte
    ;; [Shilpi] I tried to use defret here instead of defthm-usb, but I got
    ;; into trouble, probably because of the different order of lambda
    ;; expansions in defret.
    :hyp (and (unsigned-byte-p 8 rex-byte)
              (natp prefixes)
              (x86p x86))
    :bound 8
    :concl (mv-nth 2 (get-prefixes
                      proc-mode start-rip prefixes rex-byte cnt x86))
    :hints (("Goal"
             :induct (get-prefixes
                      proc-mode start-rip prefixes rex-byte cnt x86)
             :in-theory (e/d ()
                             (unsigned-byte-p
                              signed-byte-p
                              acl2::ash-0
                              acl2::zip-open
                              bitops::logtail-of-logior
                              unsigned-byte-p-of-logtail
                              acl2::logtail-identity
                              ash-monotone-2
                              bitops::logand-with-negated-bitmask
                              (:linear bitops::logior-<-0-linear-1)
                              (:linear bitops::logior-<-0-linear-2)
                              (:linear bitops::logand->=-0-linear-1)
                              (:linear bitops::logand->=-0-linear-2)
                              bitops::logtail-natp
                              natp-of-get-one-byte-prefix-array-code
                              acl2::ifix-when-not-integerp
                              bitops::basic-signed-byte-p-of-+
                              default-<-1
                              force (force)))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d () (get-prefixes)))))

  (defret get-prefixes-does-not-modify-x86-state-in-app-view
    (implies (app-view x86)
             (equal new-x86 x86))
    :hints (("Goal"
             :in-theory
             (union-theories
              '(get-prefixes
                rme08-does-not-affect-state-in-app-view)
              (theory 'minimal-theory)))))

  (defret get-prefixes-does-not-modify-x86-state-in-system-level-non-marking-view
    (implies (and (not (app-view x86))
                  (not (marking-view x86))
                  (x86p x86)
                  (not flg))
             (equal new-x86 x86))
    :hints (("Goal"
             :in-theory (union-theories
                         '(get-prefixes
                           mv-nth-2-rme08-in-system-level-non-marking-view)
                         (theory 'minimal-theory)))))

  (local
   (in-theory (e/d
               (rme08 rml08 rvm08)
               (force
                (force)
                signed-byte-p-48-lemma
                signed-byte-p
                bitops::logior-equal-0
                acl2::zp-open
                not
                (:congruence acl2::int-equiv-implies-equal-logand-2)
                (:congruence acl2::int-equiv-implies-equal-loghead-2)))))


  (defthm num-prefixes-get-prefixes-bound
    (implies (and (<= cnt 15)
                  (x86p x86)
                  (canonical-address-p start-rip)
                  (unsigned-byte-p #.*prefixes-width* prefixes)
                  (< (part-select prefixes :low 0 :high 2) 5))
             (<=
              (prefixes->num
               (mv-nth
                1
                (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)))
              15))
    :hints (("Goal"
             :induct (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
             :in-theory (e/d (rme08 rme08-value-when-error)
                             (signed-byte-p
                              unsigned-byte-p rme08 rml08
                              (force) force
                              canonical-address-p
                              not acl2::zp-open
                              acl2::ash-0
                              acl2::zip-open
                              bitops::logtail-of-logior
                              unsigned-byte-p-of-logtail
                              acl2::logtail-identity
                              ash-monotone-2
                              bitops::logand-with-negated-bitmask
                              (:linear bitops::logior-<-0-linear-1)
                              (:linear bitops::logior-<-0-linear-2)
                              (:linear bitops::logand->=-0-linear-1)
                              (:linear bitops::logand->=-0-linear-2)
                              bitops::logtail-natp
                              natp-of-get-one-byte-prefix-array-code
                              acl2::ifix-when-not-integerp
                              bitops::basic-signed-byte-p-of-+
                              default-<-1))))
    :rule-classes :linear)

  (defthm get-prefixes-opener-lemma-zero-cnt
    (implies (zp cnt)
             (equal (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
                    (mv t prefixes rex-byte x86)))
    :hints (("Goal" :in-theory (e/d (get-prefixes) ()))))

  (local
   (defthmd get-prefixes-opener-lemma-no-prefix-byte-pre
     ;; Note that this lemma is applicable in the system-level view too.
     ;; This lemma would be used for those instructions which do not have
     ;; any prefix byte.
     (b* (((mv flg byte byte-x86)
           (rme08 proc-mode start-rip #.*cs* :x x86))
          (prefix-byte-group-code
           (get-one-byte-prefix-array-code byte)))
       (implies
        (and (not flg)
             (zp prefix-byte-group-code)
             (not (zp cnt)))
        (equal
         (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
         (b* ((rex? (and
                     (eql proc-mode #.*64-bit-mode*)
                     (equal (ash byte -4) 4)))
              ((when rex?)
               (mv-let
                 (flg next-rip)
                 (add-to-*ip proc-mode start-rip 1 byte-x86)
                 (if flg
                     (mv flg prefixes rex-byte byte-x86)
                   (get-prefixes
                    proc-mode next-rip prefixes
                    byte ;; REX prefix, overwriting a previously encountered REX,
                    ;; if any
                    (the (integer 0 15) (1- cnt))
                    byte-x86)))))
           ;; Storing the number of prefixes seen and the first byte
           ;; following the prefixes in "prefixes":
           (let ((prefixes
                  (!prefixes->nxt byte prefixes)))
             (mv nil
                 (!prefixes->num (- 15 cnt) prefixes)
                 rex-byte ;; Preserving rex-byte
                 byte-x86))))))
     :hints (("Goal"
              :induct
              (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
              :in-theory (e/d ()
                              (unsigned-byte-p
                               negative-logand-to-positive-logand-with-n52p-x))))))

  (defthm get-prefixes-opener-lemma-no-prefix-byte
    ;; This lemma is applicable in all the views of the x86isa model. This
    ;; lemma would be used for those instructions which do not have any prefix
    ;; byte --- either legacy or rex.
    (implies
     (b* (((mv flg byte &)
           (rme08 proc-mode start-rip #.*cs* :x x86))
          (prefix-byte-group-code
           (get-one-byte-prefix-array-code byte)))
       (and (not flg)
            (zp prefix-byte-group-code)
            (if (equal proc-mode #.*64-bit-mode*)
                (not (equal (ash byte -4) 4))
              t)
            (not (zp cnt))))
     (equal
      (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
      (let ((prefixes
             (!prefixes->nxt
              (mv-nth 1 (rme08 proc-mode start-rip #.*cs* :x x86))
              prefixes)))
        (mv nil
            (!prefixes->num (- 15 cnt) prefixes)
            rex-byte ;; Preserving rex-byte
            (mv-nth 2 (rme08 proc-mode start-rip #.*cs* :x x86))))))
    :hints (("Goal" :in-theory (e/d (get-prefixes-opener-lemma-no-prefix-byte-pre)
                                    (rme08 get-prefixes)))))

  (defthm get-prefixes-opener-lemma-no-legacy-prefix-but-rex-prefix
    ;; Note that this lemma is applicable only in 64-bit mode.
    ;; This lemma is applicable in all the views of the x86isa model.
    (implies
     (b* (((mv flg byte &)
           (rme08 proc-mode start-rip #.*cs* :x x86))
          (prefix-byte-group-code
           (get-one-byte-prefix-array-code byte)))
       (and (equal proc-mode #.*64-bit-mode*)
            (not flg)
            (zp prefix-byte-group-code)
            (equal (ash byte -4) 4)
            (not (zp cnt))))
     (equal
      (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
      (b* (((mv & byte byte-x86)
            (rme08 proc-mode start-rip #.*cs* :x x86))
           ((mv flg next-rip)
            (add-to-*ip proc-mode start-rip 1 byte-x86)))
        (if flg
            (mv flg prefixes rex-byte byte-x86)
          (get-prefixes
           proc-mode next-rip prefixes
           byte ;; REX prefix, overwriting a previously encountered REX,
           ;; if any
           (1- cnt)
           byte-x86)))))
    :hints (("Goal" :in-theory (e/d (get-prefixes-opener-lemma-no-prefix-byte-pre)
                                    (rme08 get-prefixes)))))

  (defthm get-prefixes-opener-lemma-group-1-prefix
    (b* (((mv flg byte x86)
          (rme08 proc-mode start-rip #.*cs* :x x86))
         (prefix-byte-group-code (get-one-byte-prefix-array-code byte)))
      (implies
       (and (or (app-view x86)
                (not (marking-view x86)))
            (not flg) ;; No error in reading a byte
            (equal prefix-byte-group-code 1)
            (not (zp cnt))
            (not (mv-nth 0 (add-to-*ip proc-mode start-rip 1 x86))))
       (equal (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
              (let ((prefixes
                     (if (equal byte #.*lock*)
                         (!prefixes->lck byte prefixes)
                       (!prefixes->rep byte prefixes))))
                (get-prefixes
                 proc-mode (1+ start-rip) prefixes 0 (1- cnt) x86)))))
    :hints (("Goal"
             :in-theory
             (e/d* (add-to-*ip)
                   (rb
                    unsigned-byte-p
                    negative-logand-to-positive-logand-with-n52p-x
                    negative-logand-to-positive-logand-with-integerp-x)))))

  (defthm get-prefixes-opener-lemma-group-2-prefix
    (b* (((mv flg byte byte-x86)
          (rme08 proc-mode start-rip #.*cs* :x x86))
         (prefix-byte-group-code
          (get-one-byte-prefix-array-code
           byte)))
      (implies
       (and (or (app-view x86)
                (and (not (app-view x86))
                     (not (marking-view x86))))
            (not flg) ;; No error in reading a byte
            (equal prefix-byte-group-code 2)
            (not (zp cnt))
            (not (mv-nth 0 (add-to-*ip proc-mode start-rip 1 x86))))
       (equal (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
              (if (or
                   (and (eql proc-mode #.*64-bit-mode*)
                        (or (equal byte #.*fs-override*)
                            (equal byte #.*gs-override*)))
                   (not (eql proc-mode #.*64-bit-mode*)))
                  (get-prefixes proc-mode (1+ start-rip)
                                (!prefixes->seg byte prefixes)
                                0
                                (1- cnt) byte-x86)
                (get-prefixes
                 proc-mode (1+ start-rip) prefixes 0 (1- cnt) byte-x86)))))
    :hints (("Goal"
             :in-theory
             (e/d* (add-to-*ip)
                   (rb
                    unsigned-byte-p
                    negative-logand-to-positive-logand-with-n52p-x
                    negative-logand-to-positive-logand-with-integerp-x)))))

  (defthm get-prefixes-opener-lemma-group-3-prefix
    (implies (and (or (app-view x86)
                      (and (not (app-view x86))
                           (not (marking-view x86))))
                  (let* ((flg (mv-nth 0 (rme08 proc-mode start-rip #.*cs* :x x86)))
                         (prefix-byte-group-code
                          (get-one-byte-prefix-array-code
                           (mv-nth 1 (rme08 proc-mode start-rip #.*cs* :x x86)))))
                    (and (not flg) ;; No error in reading a byte
                         (equal prefix-byte-group-code 3)))
                  (not (zp cnt))
                  (not (mv-nth 0 (add-to-*ip proc-mode start-rip 1 x86))))
             (equal (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
                    (get-prefixes proc-mode (1+ start-rip)
                                  (!prefixes->opr
                                   (mv-nth 1
                                           (rme08
                                            proc-mode start-rip #.*cs* :x x86))
                                   prefixes)
                                  0
                                  (1- cnt) x86)))
    :hints (("Goal"
             :in-theory
             (e/d* (add-to-*ip)
                   (rb
                    unsigned-byte-p
                    negative-logand-to-positive-logand-with-n52p-x
                    negative-logand-to-positive-logand-with-integerp-x)))))

  (defthm get-prefixes-opener-lemma-group-4-prefix
    (implies (and (or (app-view x86)
                      (and (not (app-view x86))
                           (not (marking-view x86))))
                  (let* ((flg (mv-nth 0 (rme08 proc-mode start-rip #.*cs* :x x86)))
                         (prefix-byte-group-code
                          (get-one-byte-prefix-array-code
                           (mv-nth 1 (rme08 proc-mode start-rip #.*cs* :x x86)))))
                    (and (not flg) ;; No error in reading a byte
                         (equal prefix-byte-group-code 4)))
                  (not (zp cnt))
                  (not (mv-nth 0 (add-to-*ip proc-mode start-rip 1 x86))))
             (equal (get-prefixes proc-mode start-rip prefixes rex-byte cnt x86)
                    (get-prefixes proc-mode (1+ start-rip)
                                  (!prefixes->adr
                                   (mv-nth 1 (rme08
                                              proc-mode start-rip #.*cs* :x x86))
                                   prefixes)
                                  0
                                  (1- cnt) x86)))
    :hints (("Goal"
             :in-theory
             (e/d* (add-to-*ip)
                   (rb
                    unsigned-byte-p
                    negative-logand-to-positive-logand-with-n52p-x
                    negative-logand-to-positive-logand-with-integerp-x)))))

  (local
   (defret xr-msr-and-seg-hidden-of-get-prefixes-in-app-view
     (implies (app-view x86)
              (and
               (equal (xr :msr idx new-x86)
                      (xr :msr idx x86))
               (equal (xr :seg-hidden idx new-x86)
                      (xr :seg-hidden idx x86))))
     :hints (("Goal"
              :in-theory (e/d () (las-to-pas rb rme08 rml08))))))

  (local
   (defret xr-msr-of-get-prefixes-in-sys-view
     (implies (not (app-view x86))
              (and
               (equal (xr :msr idx new-x86)
                      (xr :msr idx x86))
               (equal (xr :seg-hidden idx new-x86)
                      (xr :seg-hidden idx x86))))
     :hints (("Goal"
              :induct <call>
              :in-theory (e/d ()
                              (unsigned-byte-p
                               (:linear <=-logior)
                               negative-logand-to-positive-logand-with-n52p-x
                               las-to-pas rb rme08 rml08))))))

  (local
   (defret xr-msr-of-get-prefixes
     (and
      (equal (xr :msr idx new-x86)
             (xr :msr idx x86))
      (equal (xr :seg-hidden idx new-x86)
             (xr :seg-hidden idx x86)))
     :hints (("Goal"
              :cases ((app-view x86))
              :do-not-induct t
              :in-theory (e/d () (get-prefixes las-to-pas rb rme08 rml08))))))

  (defret 64-bit-modep-of-get-prefixes
    (equal (64-bit-modep new-x86)
           (64-bit-modep x86))
    :hints (("Goal"
             :do-not-induct t
             :in-theory (e/d (64-bit-modep) ()))))

  (defret x86-operation-mode-of-get-prefixes
    (equal (x86-operation-mode new-x86)
           (x86-operation-mode x86))
    :hints (("Goal" :in-theory (e/d (x86-operation-mode) (get-prefixes))))))

;; ----------------------------------------------------------------------

;; Three-byte Opcode Maps:

(make-event
 (b* (((mv table-doc-string dispatch)
       (create-dispatch-from-opcode-map
        *0F-38-three-byte-opcode-map-lst*
        (w state)
        :escape-bytes #ux0F_38_00)))

   `(progn
      (define first-three-byte-opcode-execute
        ((proc-mode        :type (integer 0 #.*num-proc-modes-1*))
         (start-rip        :type (signed-byte   #.*max-linear-address-size*))
         (temp-rip         :type (signed-byte   #.*max-linear-address-size*))
         (prefixes         :type (unsigned-byte #.*prefixes-width*))
         (mandatory-prefix :type (unsigned-byte 8))
         (rex-byte         :type (unsigned-byte 8))
         (opcode           :type (unsigned-byte 8))
         (modr/m           :type (unsigned-byte 8))
         (sib              :type (unsigned-byte 8))
         x86)

        ;; #x0F #x38 are the first two opcode bytes.

        :parents (x86-decoder)
        ;; The following arg will avoid binding __function__ to
        ;; first-three-byte-opcode-execute. The automatic __function__ binding
        ;; that comes with define causes stack overflows during the guard proof
        ;; of this function.
        :no-function t
        :ignore-ok t
        :short "First three-byte opcode dispatch function."
        :long "<p>@('first-three-byte-opcode-execute) is the doorway to the
     first three-byte opcode map, i.e., to all three-byte opcodes whose first
     two opcode bytes are @('0F 38').</p>"
        :guard-hints (("Goal"
                       :do-not '(preprocess)
                       :in-theory
                       (e/d
                        ()
                        (unsigned-byte-p signed-byte-p))))

        (case opcode ,@dispatch)

        ///

        (defthm x86p-first-three-byte-opcode-execute
          (implies (and (x86p x86)
                        (canonical-address-p temp-rip))
                   (x86p
                    (first-three-byte-opcode-execute
                     proc-mode start-rip temp-rip prefixes
                     mandatory-prefix rex-byte opcode modr/m sib x86)))))

      (defsection 0F-38-three-byte-opcodes-table
        :parents (implemented-opcodes)
        :short "@('x86isa') Support for Opcodes in the @('0F 38') Three Byte
        Map; see @(see implemented-opcodes) for details."
        :long ,table-doc-string))))

(make-event
 (b* (((mv table-doc-string dispatch)
       (create-dispatch-from-opcode-map
        *0F-3A-three-byte-opcode-map-lst*
        (w state)
        :escape-bytes #ux0F_3A_00)))

   `(progn
      (define second-three-byte-opcode-execute
        ((proc-mode        :type (integer 0 #.*num-proc-modes-1*))
         (start-rip        :type (signed-byte   #.*max-linear-address-size*))
         (temp-rip         :type (signed-byte   #.*max-linear-address-size*))
         (prefixes         :type (unsigned-byte #.*prefixes-width*))
         (mandatory-prefix :type (unsigned-byte 8))
         (rex-byte         :type (unsigned-byte 8))
         (opcode           :type (unsigned-byte 8))
         (modr/m           :type (unsigned-byte 8))
         (sib              :type (unsigned-byte 8))
         x86)

        ;; #x0F #x3A are the first two opcode bytes.

        :parents (x86-decoder)
        ;; The following arg will avoid binding __function__ to
        ;; second-three-byte-opcode-execute. The automatic __function__ binding that
        ;; comes with define causes stack overflows during the guard proof of this
        ;; function.
        :no-function t
        :ignore-ok t
        :short "Second three-byte opcode dispatch function."
        :long "<p>@('second-three-byte-opcode-execute) is the doorway to the second
     three-byte opcode map, i.e., to all three-byte opcodes whose second two
     opcode bytes are @('0F 3A').</p>"
        :guard-hints (("Goal"
                       :do-not '(preprocess)
                       :in-theory (e/d () (unsigned-byte-p signed-byte-p))))

        (case opcode ,@dispatch)

        ///

        (defthm x86p-second-three-byte-opcode-execute
          (implies (and (x86p x86)
                        (canonical-address-p temp-rip))
                   (x86p (second-three-byte-opcode-execute
                          proc-mode start-rip temp-rip prefixes
                          mandatory-prefix rex-byte opcode modr/m sib x86)))))

      (defsection 0F-3A-three-byte-opcodes-table
        :parents (implemented-opcodes)
        :short "@('x86isa') Support for Opcodes in the @('0F 3A') Three Byte
        Map; see @(see implemented-opcodes) for details."
        :long ,table-doc-string))))

(define three-byte-opcode-decode-and-execute
  ((proc-mode          :type (integer 0 #.*num-proc-modes-1*))
   (start-rip          :type (signed-byte #.*max-linear-address-size*))
   (temp-rip           :type (signed-byte #.*max-linear-address-size*))
   (prefixes           :type (unsigned-byte #.*prefixes-width*))
   (rex-byte           :type (unsigned-byte 8))
   (second-escape-byte :type (unsigned-byte 8))
   x86)

  :ignore-ok t
  :guard (or (equal second-escape-byte #x38)
             (equal second-escape-byte #x3A))
  :guard-hints (("Goal" :do-not '(preprocess)
                 :in-theory (e/d*
                             (add-to-*ip add-to-*ip-is-i48p-rewrite-rule)
                             (unsigned-byte-p
                              (:type-prescription bitops::logand-natp-type-2)
                              (:type-prescription bitops::ash-natp-type)
                              acl2::loghead-identity
                              not
                              tau-system
                              (tau-system)))))
  :parents (x86-decoder)
  :short "Decoder and dispatch function for three-byte opcodes, where @('0x0F
  0x38') are the first two opcode bytes"
  :long "<p>Source: Intel Manual, Volume 2, Appendix A-2</p>"

  (b* ((ctx 'three-byte-opcode-decode-and-execute)

       ((mv flg0 (the (unsigned-byte 8) opcode) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg0)
        (!!ms-fresh :opcode-byte-access-error flg0))

       ;; Possible values of opcode: all values denote opcodes of the first or
       ;; second three-byte map, depending on the value of second-escape-byte.
       ;; The function first-three-byte-opcode-execute or
       ;; second-three-byte-opcode-execute case-splits on this opcode byte and
       ;; calls the appropriate instruction semantic function.

       ((mv flg temp-rip) (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg) (!!ms-fresh :increment-error flg))

       ((mv msg (the (unsigned-byte 8) mandatory-prefix))
        (compute-mandatory-prefix-for-three-byte-opcode
         proc-mode second-escape-byte opcode prefixes))
       ((when msg)
        (x86-illegal-instruction msg start-rip temp-rip x86))

       (modr/m?
        (three-byte-opcode-ModR/M-p
         proc-mode mandatory-prefix second-escape-byte opcode))
       ((mv flg1 (the (unsigned-byte 8) modr/m) x86)
        (if modr/m?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg1) (!!ms-fresh :modr/m-byte-read-error flg1))

       ((mv flg temp-rip) (if modr/m?
                              (add-to-*ip proc-mode temp-rip 1 x86)
                            (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg))

       (sib? (and modr/m?
                  (b* ((p4? (eql #.*addr-size-override*
                                 (prefixes->adr prefixes)))
                       (16-bit-addressp (eql 2 (select-address-size proc-mode p4? x86))))
                    (x86-decode-SIB-p modr/m 16-bit-addressp))))
       ((mv flg2 (the (unsigned-byte 8) sib) x86)
        (if sib?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg2)
        (!!ms-fresh :sib-byte-read-error flg2))

       ((mv flg temp-rip) (if sib?
                              (add-to-*ip proc-mode temp-rip 1 x86)
                            (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg)))

    (case second-escape-byte
      (#x38
       (first-three-byte-opcode-execute
        proc-mode start-rip temp-rip prefixes rex-byte
        mandatory-prefix opcode modr/m sib x86))
      (#x3A
       (second-three-byte-opcode-execute
        proc-mode start-rip temp-rip prefixes rex-byte
        mandatory-prefix opcode modr/m sib x86))
      (otherwise
       ;; Unreachable.
       (!!ms-fresh :illegal-value-of-second-escape-byte second-escape-byte))))

  ///

  (defrule x86p-three-byte-opcode-decode-and-execute
    (implies (and (canonical-address-p temp-rip)
                  (x86p x86))
             (x86p (three-byte-opcode-decode-and-execute
                    proc-mode start-rip temp-rip prefixes rex-byte escape-byte x86)))
    :enable add-to-*ip-is-i48p-rewrite-rule
    :disable signed-byte-p))

;; ----------------------------------------------------------------------

;; Increasing the rewrite stack limit to help the guard proofs of
;; two-byte-opcode-execute and one-byte-opcode-execute go through; note that
;; this is local to this book.
(set-rewrite-stack-limit (+ 6000 acl2::*default-rewrite-stack-limit*))

;; ----------------------------------------------------------------------

;; Two-byte Opcode Map:

(local
 (defthm unsigned-byte-p-1-of-logbit
   (unsigned-byte-p 1 (logbit i x))))

(make-event
 (b* (((mv table-doc-string dispatch)
       (create-dispatch-from-opcode-map
        *two-byte-opcode-map-lst*
        (w state)
        :escape-bytes #ux0F_00)))

   `(progn
      (define two-byte-opcode-execute
        ((proc-mode        :type (integer 0 #.*num-proc-modes-1*))
         (start-rip        :type (signed-byte   #.*max-linear-address-size*))
         (temp-rip         :type (signed-byte   #.*max-linear-address-size*))
         (prefixes         :type (unsigned-byte #.*prefixes-width*))
         (mandatory-prefix :type (unsigned-byte 8))
         (rex-byte         :type (unsigned-byte 8))
         (opcode           :type (unsigned-byte 8))
         (modr/m           :type (unsigned-byte 8))
         (sib              :type (unsigned-byte 8))
         x86)

        :parents (x86-decoder)
        ;; The following arg will avoid binding __function__ to
        ;; two-byte-opcode-execute. The automatic __function__ binding that comes
        ;; with define causes stack overflows during the guard proof of this
        ;; function.
        :no-function t

        :short "Two-byte opcode dispatch function."
        :long "<p>@('two-byte-opcode-execute') is the doorway to the two-byte
     opcode map, and will lead to the three-byte opcode map if @('opcode') is
     either @('#x38') or @('#x3A').</p>"
        :guard (and (prefixes-p prefixes)
                    (modr/m-p modr/m)
                    (sib-p sib))
        :guard-hints (("Goal"
                       :do-not '(preprocess)
                       :in-theory (e/d (member-equal)
                                       (logbit
                                        bitops::logbit-to-logbitp
                                        unsigned-byte-p
                                        (:t unsigned-byte-p)
                                        signed-byte-p))))

        (case opcode ,@dispatch)

        ///

        (defthm x86p-two-byte-opcode-execute
          (implies (and (x86p x86)
                        (canonical-address-p temp-rip))
                   (x86p (two-byte-opcode-execute
                          proc-mode start-rip temp-rip prefixes mandatory-prefix
                          rex-byte opcode modr/m sib x86)))))

      (defsection two-byte-opcodes-table
        :parents (implemented-opcodes)
        :short "@('x86isa') Support for Opcodes in the Two-Byte Map (i.e.,
        first opcode byte is 0x0F); see @(see implemented-opcodes) for details."
        :long ,table-doc-string))))

(define two-byte-opcode-decode-and-execute
  ((proc-mode     :type (integer 0 #.*num-proc-modes-1*))
   (start-rip     :type (signed-byte #.*max-linear-address-size*))
   (temp-rip      :type (signed-byte #.*max-linear-address-size*))
   (prefixes      :type (unsigned-byte #.*prefixes-width*))
   (rex-byte      :type (unsigned-byte 8))
   (escape-byte   :type (unsigned-byte 8))
   x86)

  :ignore-ok t
  :guard (and (prefixes-p prefixes)
              (equal escape-byte #x0F))
  :guard-hints (("Goal" :do-not '(preprocess)
                 :in-theory (e/d*
                             (add-to-*ip
                              modr/m-p
                              add-to-*ip-is-i48p-rewrite-rule)
                             (unsigned-byte-p
                              (:type-prescription bitops::logand-natp-type-2)
                              (:type-prescription bitops::ash-natp-type)
                              acl2::loghead-identity
                              not
                              tau-system
                              (tau-system)))))
  :parents (x86-decoder)
  :short "Decoder and dispatch function for two-byte opcodes"
  :long "<p>Source: Intel Manual, Volume 2, Appendix A-2</p>"

  (b* ((ctx 'two-byte-opcode-decode-and-execute)

       ((mv flg0 (the (unsigned-byte 8) opcode) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg0)
        (!!ms-fresh :opcode-byte-access-error flg0))

       ;; Possible values of opcode:

       ;; 1. #x38 and #x3A: These are escapes to the two three-byte opcode
       ;;    maps.  Function three-byte-opcode-decode-and-execute is called
       ;;    here, which also fetches the ModR/M and SIB bytes for these
       ;;    opcodes.

       ;; 2. All other values denote opcodes of the two-byte map.  The function
       ;;    two-byte-opcode-execute case-splits on this opcode byte and calls
       ;;    the appropriate instruction semantic function.

       ((mv flg temp-rip) (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg) (!!ms-fresh :increment-error flg))

       ((mv msg (the (unsigned-byte 8) mandatory-prefix))
        (compute-mandatory-prefix-for-two-byte-opcode
         proc-mode opcode prefixes))
       ((when msg)
        (x86-illegal-instruction msg start-rip temp-rip x86))

       (modr/m?
        (two-byte-opcode-ModR/M-p
         proc-mode mandatory-prefix opcode))
       ((mv flg1 (the (unsigned-byte 8) modr/m) x86)
        (if modr/m?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg1) (!!ms-fresh :modr/m-byte-read-error flg1))

       ((mv flg temp-rip) (if modr/m?
                              (add-to-*ip proc-mode temp-rip 1 x86)
                            (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg))

       (sib? (and modr/m?
                  (b* ((p4? (eql #.*addr-size-override*
                                 (the (unsigned-byte 8) (prefixes->adr prefixes))))
                       (16-bit-addressp (eql 2 (select-address-size proc-mode p4? x86))))
                    (x86-decode-SIB-p modr/m 16-bit-addressp))))
       ((mv flg2 (the (unsigned-byte 8) sib) x86)
        (if sib?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg2)
        (!!ms-fresh :sib-byte-read-error flg2))

       ((mv flg temp-rip) (if sib?
                              (add-to-*ip proc-mode temp-rip 1 x86)
                            (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg)))

    (two-byte-opcode-execute
     proc-mode start-rip temp-rip prefixes mandatory-prefix
     rex-byte opcode modr/m sib x86))

  ///

  (defrule x86p-two-byte-opcode-decode-and-execute
    (implies (and (canonical-address-p temp-rip)
                  (x86p x86))
             (x86p (two-byte-opcode-decode-and-execute
                    proc-mode start-rip temp-rip prefixes
                    rex-byte escape-byte x86)))
    :enable add-to-*ip-is-i48p-rewrite-rule
    :disable signed-byte-p))

;; ----------------------------------------------------------------------

;; One-byte Opcode Map:

;; BOZO Rob -- for some reason, we now need this to get the guard theorem through..

(local
 (defthm unsigned-byte-p-bool->bit
   (unsigned-byte-p 1 (bool->bit x))))

(make-event

 (b* (((mv table-doc-string dispatch)
       (create-dispatch-from-opcode-map
        *one-byte-opcode-map-lst*
        (w state)
        :escape-bytes #ux00)))

   `(progn
      (define one-byte-opcode-execute
        ((proc-mode     :type (integer 0 #.*num-proc-modes-1*))
         (start-rip     :type (signed-byte   #.*max-linear-address-size*))
         (temp-rip      :type (signed-byte   #.*max-linear-address-size*))
         (prefixes      :type (unsigned-byte #.*prefixes-width*))
         (rex-byte      :type (unsigned-byte 8))
         (opcode        :type (unsigned-byte 8))
         (modr/m        :type (unsigned-byte 8))
         (sib           :type (unsigned-byte 8))
         x86)

        :parents (x86-decoder)
        ;; The following arg will avoid binding __function__ to
        ;; one-byte-opcode-execute. The automatic __function__ binding
        ;; that comes with define causes stack overflows during the guard
        ;; proof of this function.
        :no-function t
        :short "Top-level dispatch function."
        :long "<p>@('one-byte-opcode-execute') is the doorway to all the opcode
     maps (for non-AVX/AVX512 instructions).</p>"

        :guard (and (prefixes-p prefixes)
                    (modr/m-p modr/m)
                    (sib-p sib))
        :guard-hints (("Goal"
                       :do-not '(preprocess)
                       :in-theory (e/d () (unsigned-byte-p signed-byte-p))))

        (case opcode ,@dispatch)

        ///

        (defthm x86p-one-byte-opcode-execute
          (implies (and (x86p x86)
                        (canonical-address-p temp-rip))
                   (x86p (one-byte-opcode-execute
                          proc-mode start-rip temp-rip
                          prefixes rex-byte opcode modr/m sib x86)))))

      (defsection one-byte-opcodes-table
        :parents (implemented-opcodes)
        :short "@('x86isa') Support for Opcodes in the One-Byte Map; see @(see
        implemented-opcodes) for details."
        :long ,table-doc-string))))

;; ----------------------------------------------------------------------

;; VEX-encoded instructions:

(local
 (defthm dumb-integerp-of-mv-nth-1-rme08-rule
   (implies (force (x86p x86))
            (integerp (mv-nth 1 (rme08 proc-mode eff-addr seg-reg r-x x86))))
   :rule-classes (:rewrite :type-prescription)))

(local
 (defthm unsigned-byte-p-24-of-vex-prefixes-rule
   (implies
    (unsigned-byte-p 8 byte)
    (and (unsigned-byte-p 24 (logior #xC400 (ash byte 16)))
         (unsigned-byte-p 24 (logior #xC500 (ash byte 16)))))))

(make-event
 `(define vex-0F-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                              opcode byte")
     (vex-prefixes           :type (unsigned-byte 24)
                             "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for VEX-encoded instructions in the two-byte opcode map"
    :guard (and (vex-prefixes-byte0-p vex-prefixes)
                (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))
    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86)))

    (case opcode
      ,@(avx-case-gen *vex-0F-opcodes* t state))))

(make-event
 `(define vex-0F38-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                             opcode byte")
     (vex-prefixes           :type (unsigned-byte 24)
                             "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for VEX-encoded instructions in the first
    three-byte opcode map"
    :guard (and (vex-prefixes-byte0-p vex-prefixes)
                (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))

    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86)))

    (case opcode
      ,@(avx-case-gen *vex-0F38-opcodes* t state))))

(make-event
 `(define vex-0F3A-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                            opcode byte")
     (vex-prefixes           :type (unsigned-byte 24)
                             "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for VEX-encoded instructions in the second
    three-byte opcode map"
    :guard (and (vex-prefixes-byte0-p vex-prefixes)
                (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))

    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86)))

    (case opcode
      ,@(avx-case-gen *vex-0F3A-opcodes* t state))))

(define vex-decode-and-execute
  ((proc-mode              :type (integer 0 #.*num-proc-modes-1*))
   (start-rip              :type (signed-byte   #.*max-linear-address-size*))
   (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                           "@('temp-rip') points to the byte following the
                            first two VEX prefixes that were already read and
                            placed in the @('vex-prefixes') structure in @(tsee
                            x86-fetch-decode-execute).")
   (prefixes               :type (unsigned-byte #.*prefixes-width*))
   (rex-byte               :type (unsigned-byte 8))
   (vex-prefixes           :type (unsigned-byte 24)
                           "Only @('byte0') and @('byte1') fields are populated
                            when this function is called.")
   x86)

  :guard (and (prefixes-p prefixes)
              (vex-prefixes-byte0-p vex-prefixes))

  :guard-hints
  (("Goal"
    :in-theory
    (e/d (modr/m-p
          vex-prefixes-byte0-p
          vex-prefixes-map-p add-to-*ip
          add-to-*ip-is-i48p-rewrite-rule)
         (bitops::logand-with-negated-bitmask not (tau-system)))))
  :prepwork
  ((local
    (defthm vex-decode-and-execute-guard-helper
      (implies (and (unsigned-byte-p 8 byte-1)
                    (unsigned-byte-p 8 byte-2))
               (and
                (<
                 (logior
                  (logand #xffffff00
                          (logior (logand #xffffffff00ffffff vex-prefixes)
                                  (ash byte-1
                                       24)))
                  byte-2)
                 4294967296)
                (<=
                 0
                 (logior byte-1
                         (logand #xffffff00
                                 (logior (logand #xffffffff00ffffff vex-prefixes)
                                         (ash byte-2 24)))))
                (<
                 (logior byte-1
                         (logand #xffffff00
                                 (logior (logand #xffffffff00ffffff vex-prefixes)
                                         (ash byte-2 24))))
                 4294967296)))))

   (local
    (defthm logtail-16-of-unsigned-byte-p-8
      (implies (unsigned-byte-p 8 byte)
               (equal (logtail 16 byte) 0)))))

  :parents (x86-decoder)

  :long "<p>@('vex-decode-and-execute') dispatches control to VEX-encoded
  instructions.</p>

  <p><i>Reference: Intel Vol. 2A, Section 2.3: Intel Advanced Vector
   Extensions (Intel AVX)</i></p>"

  (b* ((ctx 'vex-decode-and-execute)
       ;; Reference for the following checks that lead to #UD:
       ;; Intel Vol. 2,
       ;; Section 2.3.2 - VEX and the LOCK prefix
       ;; Section 2.3.3 - VEX and the 66H, F2H, and F3H prefixes
       ;; Section 2.3.4 - VEX and the REX prefix

       ;; Any VEX-encoded instruction with mandatory (SIMD) prefixes, lock
       ;; prefix, and REX prefixes (i.e., 66, F2, F3, F0, and 40-4F) preceding
       ;; VEX will #UD.  Therefore, we fetch VEX prefixes after the legacy
       ;; prefixes (function get-prefixes) and the REX prefix have been
       ;; detected and fetched in x86-fetch-decode-execute.

       ((when (not (equal rex-byte 0)))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :rex rex-byte))
       ;; TODO: Intel Vol. 2A Sections 2.3.2 and 2.3.3 say "Any VEX-encoded
       ;; instruction with a LOCK/66H/F2H/F3H prefix preceding VEX will #UD."
       ;; So, should I check :last-byte here instead?
       ((when (equal (the (unsigned-byte 8) (prefixes->lck prefixes)) #.*lock*))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :lock-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->rep prefixes)) #.*mandatory-f2h*))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :F2-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->rep prefixes)) #.*mandatory-f3h*))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :F3-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->opr prefixes)) #.*mandatory-66h*))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :66-prefix))

       (vex2-prefix?
        (equal (vex-prefixes-slice :byte0 vex-prefixes) #.*vex2-byte0*))
       (vex3-prefix?
        (equal (vex-prefixes-slice :byte0 vex-prefixes) #.*vex3-byte0*))
       (vex-byte1 (vex-prefixes-slice :byte1 vex-prefixes))
       ;; VEX3 Byte 1 #UD Checks for M-MMMM field:
       ;; References: Intel Vol. 2, Figure 2-9 and Section 2.3.6.1
       ((mv vex3-0F-map? vex3-0F38-map? vex3-0F3A-map?)
        (if vex3-prefix?
            (mv (equal (vex3-byte1-slice :m-mmmm vex-byte1) #.*v0F*)
                (equal (vex3-byte1-slice :m-mmmm vex-byte1) #.*v0F38*)
                (equal (vex3-byte1-slice :m-mmmm vex-byte1) #.*v0F3A*))
          (mv nil nil nil)))
       ((when (and vex3-prefix?
                   (not (or vex3-0F-map? vex3-0F38-map? vex3-0F3A-map?))))
        (!!fault-fresh :ud :vex-prefixes vex-prefixes :m-mmmm vex-byte1))

       ;; Completely populating the vex-prefixes structure --- filling out only
       ;; next-byte for vex2-prefixes and both byte2 and next-byte for
       ;; vex3-prefix:
       ((mv flg0 (the (unsigned-byte 8) byte2/next-byte) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg0)
        (!!ms-fresh :vex-byte2/next-byte-read-error flg0))
       ((mv flg1 temp-rip)
        (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg1)
        (!!ms-fresh :increment-error flg1))
       (vex-prefixes
        (if vex3-prefix?
            (!vex-prefixes-slice :byte2 byte2/next-byte vex-prefixes)
          vex-prefixes))
       ((mv flg2 (the (unsigned-byte 8) next-byte) x86)
        (if vex3-prefix?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg2)
        (!!ms-fresh :next-byte-read-error flg2))
       ((mv flg3 temp-rip)
        (if vex3-prefix?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg3)
        (!!ms-fresh :increment-error flg3))

       (opcode
        (the (unsigned-byte 8)
          (if vex3-prefix? next-byte byte2/next-byte)))

       (modr/m? (vex-opcode-ModR/M-p vex-prefixes opcode))
       ((mv flg4 (the (unsigned-byte 8) modr/m) x86)
        (if modr/m?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg4)
        (!!ms-fresh :modr/m-byte-read-error flg4))
       ((mv flg5 temp-rip)
        (if modr/m?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg5) (!!ms-fresh :increment-error flg5))

       (sib? (and modr/m?
                  (b* ((p4? (eql #.*addr-size-override*
                                 (the (unsigned-byte 8) (prefixes->adr prefixes))))
                       (16-bit-addressp (eql 2 (select-address-size proc-mode p4? x86))))
                    (x86-decode-SIB-p modr/m 16-bit-addressp))))
       ((mv flg6 (the (unsigned-byte 8) sib) x86)
        (if sib?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg6)
        (!!ms-fresh :sib-byte-read-error flg6))
       ((mv flg7 temp-rip)
        (if sib?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg7) (!!ms-fresh :increment-error flg7)))

    (cond
     ((mbe :logic (vex-prefixes-map-p #ux0F vex-prefixes)
           :exec (or vex2-prefix? (and vex3-prefix? vex3-0F-map?)))
      (vex-0F-execute start-rip temp-rip vex-prefixes opcode modr/m sib x86))
     ((mbe :logic (vex-prefixes-map-p #ux0F_38 vex-prefixes)
           :exec (and vex3-prefix? vex3-0F38-map?))
      (vex-0F38-execute start-rip temp-rip vex-prefixes opcode modr/m sib x86))
     ((mbe :logic (vex-prefixes-map-p #ux0F_3A vex-prefixes)
           :exec (and vex3-prefix? vex3-0F3A-map?))
      (vex-0F3A-execute start-rip temp-rip vex-prefixes opcode modr/m sib x86))
     (t
      ;; Unreachable.
      (!!ms-fresh :illegal-value-of-VEX-m-mmmm))))

  ///

  (defthm x86p-vex-decode-and-execute
    (implies (and (x86p x86)
                  (canonical-address-p temp-rip))
             (x86p
              (vex-decode-and-execute
               proc-mode
               start-rip temp-rip prefixes rex-byte vex-prefixes x86)))
    :hints (("Goal" :in-theory (e/d (add-to-*ip add-to-*ip-is-i48p-rewrite-rule)
                                    ())))))

;; ----------------------------------------------------------------------

;; EVEX-encoded instructions:

(local
 (defthm unsigned-byte-p-40-of-evex-prefixes-rule
   (implies
    (unsigned-byte-p 8 byte)
    (unsigned-byte-p 40 (logior #x6200 (ash byte 16))))))

(make-event
 `(define evex-0F-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                              opcode byte")
     (evex-prefixes           :type (unsigned-byte #.*evex-width*)
                              "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for EVEX-encoded instructions in the two-byte opcode map"
    :guard (and (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))
    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86))
                  :hints (("Goal" :in-theory (e/d () ((tau-system)
                                                      signed-byte-p)))))

    (case opcode
      ,@(avx-case-gen *evex-0F-opcodes* nil state))))

(make-event
 `(define evex-0F38-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                             opcode byte")
     (evex-prefixes           :type (unsigned-byte #.*evex-width*)
                              "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for EVEX-encoded instructions in the first
    three-byte opcode map"
    :guard (and (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))

    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86))
                  :hints (("Goal" :in-theory (e/d () ((tau-system)
                                                      signed-byte-p)))))

    (case opcode
      ,@(avx-case-gen *evex-0F38-opcodes* nil state))))

(make-event
 `(define evex-0F3A-execute
    ((start-rip              :type (signed-byte   #.*max-linear-address-size*))
     (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                             "@('temp-rip') points to the byte following the
                            opcode byte")
     (evex-prefixes           :type (unsigned-byte #.*evex-width*)
                              "Completely populated when this function is
                              called")
     (opcode                 :type (unsigned-byte 8))
     (modr/m                 :type (unsigned-byte 8))
     (sib                    :type (unsigned-byte 8))
     x86)

    :ignore-ok t

    :parents (x86-decoder)
    :no-function t
    :short "Dispatch function for EVEX-encoded instructions in the second
    three-byte opcode map"
    :guard (and (modr/m-p modr/m)
                (sib-p sib))
    :guard-hints (("Goal"
                   :do-not '(preprocess)
                   :in-theory (e/d ()
                                   (unsigned-byte-p
                                    signed-byte-p
                                    (:forward-chaining acl2::unsigned-byte-p-forward)
                                    ash
                                    (tau-system)))))

    :returns (x86 x86p :hyp (and (canonical-address-p temp-rip)
                                 (x86p x86))
                  :hints (("Goal" :in-theory (e/d () ((tau-system)
                                                      signed-byte-p)))))

    (case opcode
      ,@(avx-case-gen *evex-0F3A-opcodes* nil state))))

(define evex-decode-and-execute
  ((proc-mode              :type (integer 0 #.*num-proc-modes-1*))
   (start-rip              :type (signed-byte   #.*max-linear-address-size*))
   (temp-rip               :type (signed-byte   #.*max-linear-address-size*)
                           "@('temp-rip') points to the byte following the
                            first two EVEX prefixes that were already read and
                            placed in the @('evex-prefixes') structure in @(tsee
                            x86-fetch-decode-execute).")
   (prefixes               :type (unsigned-byte #.*prefixes-width*))
   (rex-byte               :type (unsigned-byte 8))
   (evex-prefixes          :type (unsigned-byte #.*evex-width*)
                           "Only @('byte0') and @('byte1') fields are populated
                            when this function is called.")
   x86)

  :ignore-ok t

  :guard (prefixes-p prefixes)

  :guard-hints
  (("Goal"
    :in-theory
    (e/d (modr/m-p
          add-to-*ip add-to-*ip-is-i48p-rewrite-rule)
         (bitops::logand-with-negated-bitmask))))

  :parents (x86-decoder)

  :long "<p>@('evex-decode-and-execute') dispatches control to EVEX-encoded
  instructions.</p>

  <p><i>Reference: Intel Vol. 2A, Section 2.6: Intel(R) AVX-512
  Encoding</i></p>"

  (b* ((ctx 'evex-decode-and-execute)

       ;; Though I can't find it anywhere explicitly in the Intel manuals, it
       ;; seems reasonable to expect that like the VEX-encoded instructions,
       ;; the use of mandatory and REX prefixes should cause a #UD here too.

       ((when (not (equal rex-byte 0)))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :rex rex-byte))
       ((when (equal (the (unsigned-byte 8) (prefixes->lck prefixes)) #.*lock*))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :lock-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->rep prefixes)) #.*mandatory-f2h*))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :F2-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->rep prefixes)) #.*mandatory-f3h*))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :F3-prefix))
       ((when (equal (the (unsigned-byte 8) (prefixes->opr prefixes)) #.*mandatory-66h*))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :66-prefix))

       ;; EVEX Byte 1:
       (evex-byte1 (evex-prefixes-slice :byte1 evex-prefixes))
       ;; EVEX Byte 1 #UD Checks
       ;; Reference: Intel Vol. 2, Section 2.6.11.2 (Opcode Independent #UD)
       ((when (not (equal (evex-byte1-slice :res evex-byte1) 0)))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :byte1-reserved-bits))
       ((mv evex-0F-map? evex-0F38-map? evex-0F3A-map?)
        (mv (equal (evex-byte1-slice :mm evex-byte1) #.*v0F*)
            (equal (evex-byte1-slice :mm evex-byte1) #.*v0F38*)
            (equal (evex-byte1-slice :mm evex-byte1) #.*v0F3A*)))
       ((when (not (or evex-0F-map? evex-0F38-map? evex-0F3A-map?)))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :mm evex-byte1))

       ;; EVEX Byte 2:
       ((mv flg0 (the (unsigned-byte 8) evex-byte2) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg0)
        (!!ms-fresh :evex-byte2-read-error flg0))
       ((mv flg1 temp-rip)
        (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg1)
        (!!ms-fresh :increment-error flg1))
       (evex-prefixes
        (!evex-prefixes-slice :byte2 evex-byte2 evex-prefixes))
       ;; EVEX Byte 2 #UD Check
       ;; Reference: Intel Vol. 2, Section 2.6.11.2 (Opcode Independent #UD)
       ((when (not (equal (evex-byte2-slice :res evex-byte2) 1)))
        (!!fault-fresh :ud :evex-prefixes evex-prefixes :byte2-reserved-bit))

       ;; EVEX Byte 3:
       ((mv flg2 (the (unsigned-byte 8) evex-byte3) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg2)
        (!!ms-fresh :evex-byte3-read-error flg2))
       ((mv flg3 temp-rip)
        (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg3)
        (!!ms-fresh :increment-error flg3))

       ;; Opcode:
       ((mv flg4 (the (unsigned-byte 8) opcode) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg4)
        (!!ms-fresh :opcode-read-error flg4))
       ((mv flg5 temp-rip)
        (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg5)
        (!!ms-fresh :increment-error flg5))

       ;; All VEX- and EVEX-encoded instructions require a ModR/M byte.
       ;; Reference: Intel Manual, Vol. 2, Figure 2-8 (Instruction Encoding
       ;; Format with VEX Prefix) and Figure 2-10 (AVX-512 Instruction Format
       ;; and the EVEX Prefix)
       ((mv flg6 (the (unsigned-byte 8) modr/m) x86)
        (rme08 proc-mode temp-rip #.*cs* :x x86))
       ((when flg6)
        (!!ms-fresh :modr/m-byte-read-error flg6))
       ((mv flg7 temp-rip)
        (add-to-*ip proc-mode temp-rip 1 x86))
       ((when flg7) (!!ms-fresh :increment-error flg7))

       (sib? (b* ((p4? (eql #.*addr-size-override*
                            (the (unsigned-byte 8) (prefixes->adr prefixes))))
                  (16-bit-addressp
                   (eql 2 (select-address-size proc-mode p4? x86))))
               (x86-decode-SIB-p modr/m 16-bit-addressp)))
       ((mv flg8 (the (unsigned-byte 8) sib) x86)
        (if sib?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg8)
        (!!ms-fresh :sib-byte-read-error flg8))
       ((mv flg9 temp-rip)
        (if sib?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg9) (!!ms-fresh :increment-error flg9)))

    (cond
     (evex-0F-map?
      (evex-0F-execute start-rip temp-rip evex-prefixes opcode modr/m sib x86))
     (evex-0F38-map?
      (evex-0F38-execute start-rip temp-rip evex-prefixes opcode modr/m sib x86))
     (evex-0F3A-map?
      (evex-0F3A-execute start-rip temp-rip evex-prefixes opcode modr/m sib x86))
     (t
      ;; Unreachable.
      (!!ms-fresh :illegal-value-of-EVEX-mm))))

  ///

  (defthm x86p-evex-decode-and-execute
    (implies (and (x86p x86)
                  (canonical-address-p temp-rip))
             (x86p
              (evex-decode-and-execute
               proc-mode
               start-rip temp-rip prefixes rex-byte evex-prefixes x86)))
    :hints (("Goal" :in-theory (e/d (add-to-*ip add-to-*ip-is-i48p-rewrite-rule)
                                    ((tau-system)))))))

;; ----------------------------------------------------------------------

(define x86-fetch-decode-execute (x86)

  :parents (x86-decoder)
  :short "Top-level step function"

  :long "<p>@('x86-fetch-decode-execute') is the step function of our x86
 interpreter.  It fetches one instruction by looking up the memory address
 indicated by the instruction pointer @('rip'), decodes that instruction, and
 dispatches control to the appropriate instruction semantic function.</p>"

  :prepwork
  ((local
    (defthm guard-helper-1
      (implies (and (<= 0 (+ x y))
                    (<= (+ x y) a)
                    (unsigned-byte-p 32 a)
                    (integerp x) (integerp y))
               (signed-byte-p 48 (+ x y)))))

   (local
    (defthm guard-helper-2
      (implies (and (<= 0 (+ x y))
                    (<= (+ x y) a)
                    (unsigned-byte-p 32 a)
                    (integerp x) (integerp y))
               (signed-byte-p 64 (+ x y)))))

   (local
    (defthm guard-helper-3
      (implies (unsigned-byte-p 8 b0)
               (and
                (unsigned-byte-p 32 (logior 98 (ash b0 8)))
                (unsigned-byte-p 24 (logior 196 (ash b0 8)))
                (unsigned-byte-p 24 (logior 197 (ash b0 8)))))))

   (local
    (defthm guard-helper-4
      (implies (and (unsigned-byte-p 4 num)
                    (signed-byte-p 48 rip))
               (and (signed-byte-p 64 (+ 1 rip num))
                    (signed-byte-p 64 (+ 2 rip num))))))

   (local
    (defthm guard-helper-5
      (implies (unsigned-byte-p 4 num)
               (signed-byte-p 48 (+ 1 num)))))

   (local (in-theory (e/d* ()
                           (signed-byte-p
                            unsigned-byte-p
                            not (tau-system))))))

  :guard-hints
  (("Goal" :in-theory (e/d (modr/m-p
                            prefixes-p
                            vex-prefixes-byte0-p
                            add-to-*ip add-to-*ip-is-i48p-rewrite-rule)
                           ())))

  (b* ((ctx 'x86-fetch-decode-execute)
       (proc-mode (x86-operation-mode x86))
       (64-bit-modep (equal proc-mode #.*64-bit-mode*))
       ;; We don't want our interpreter to take a step if the machine is in a
       ;; bad state.  Such checks are made in x86-run but I am duplicating them
       ;; here in case this function is being used at the top-level.
       ((when (or (ms x86) (fault x86))) x86)

       (start-rip (the (signed-byte #.*max-linear-address-size*)
                    (read-*ip proc-mode x86)))

       ((mv flg (the (unsigned-byte #.*prefixes-width*) prefixes)
            (the (unsigned-byte 8) rex-byte)
            x86)
        (get-prefixes proc-mode start-rip 0 0 15 x86))
       ;; Among other errors (including if there are 15 prefix (legacy and REX)
       ;; bytes, which leaves no room for an opcode byte in a legal
       ;; instruction), if get-prefixes detects a non-canonical address while
       ;; attempting to fetch prefixes, flg will be non-nil.
       ((when flg)
        (!!ms-fresh :error-in-reading-prefixes flg))

       ((the (unsigned-byte 8) opcode/vex/evex-byte)
        (prefixes->nxt prefixes))

       ((the (unsigned-byte 4) prefix-length)
        (prefixes->num prefixes))

       ((mv flg temp-rip) (add-to-*ip proc-mode start-rip (1+ prefix-length) x86))
       ((when flg) (!!ms-fresh :increment-error flg))

       (vex-byte0? (or (equal opcode/vex/evex-byte #.*vex2-byte0*)
                       (equal opcode/vex/evex-byte #.*vex3-byte0*)))
       ;; If opcode/vex/evex-byte is either 0xC4 (*vex3-byte0*) or 0xC5
       ;; (*vex2-byte0*), then we always have a VEX-encoded instruction in the
       ;; 64-bit mode.  But in the 32-bit mode, these bytes may not signal the
       ;; start of the VEX prefixes.  0xC4 and 0xC5 map to LES and LDS
       ;; instructions (respectively) in the 32-bit mode if bits[7:6] of the
       ;; next byte, which we call les/lds-distinguishing-byte below, are *not*
       ;; 11b.  Otherwise, they signal the start of VEX prefixes in the 32-bit
       ;; mode too.

       ;; Though the second byte acts as the distinguishing byte only in the
       ;; 32-bit mode, we always read the first two bytes of a VEX prefix in
       ;; this function for simplicity.
       ((mv flg les/lds-distinguishing-byte x86)
        (if vex-byte0?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg)
        (!!ms-fresh :les/lds-distinguishing-byte-read-error flg))
       ;; If the instruction is indeed LDS or LES in the 32-bit mode, temp-rip
       ;; is incremented after the ModR/M is detected (see add-to-*ip following
       ;; modr/m? below).
       ((when (and vex-byte0?
                   (or 64-bit-modep
                       (and (not 64-bit-modep)
                            (equal (part-select
                                    les/lds-distinguishing-byte
                                    :low 6 :high 7)
                                   #b11)))))
        ;; Handle VEX-encoded instructions separately.
        (b* (((mv flg temp-rip)
              (add-to-*ip proc-mode temp-rip 1 x86))
             ((when flg)
              (!!ms-fresh :vex-byte1-increment-error flg))
             (vex-prefixes
              (!vex-prefixes-slice
               :byte0 opcode/vex/evex-byte 0))
             (vex-prefixes
              (!vex-prefixes-slice
               :byte1 les/lds-distinguishing-byte vex-prefixes)))
          (vex-decode-and-execute
           proc-mode
           start-rip temp-rip prefixes rex-byte vex-prefixes x86)))

       (opcode/evex-byte opcode/vex/evex-byte)

       (evex-byte0? (equal opcode/evex-byte #.*evex-byte0*))
       ;; Byte 0x62 is byte0 of the 4-byte EVEX prefix.  In 64-bit mode, this
       ;; byte indicates the beginning of the EVEX prefix --- note that in the
       ;; pre-AVX512 era, this would lead to a #UD, but we don't model that
       ;; here.

       ;; Similar to the VEX prefix situation, things are more complicated in
       ;; the 32-bit mode, where 0x62 aliases to the 32-bit only BOUND
       ;; instruction.  The Intel Manuals (May, 2018) don't seem to say
       ;; anything explicitly about how one differentiates between the EVEX
       ;; prefix and the BOUND instruction in 32-bit mode.  However, a legal
       ;; BOUND instruction must always have a memory operand as its second
       ;; operand, which means that ModR/M.mod != 0b11 (see Intel Vol. 2, Table
       ;; 2-2).  So, if bits [7:6] of the byte following 0x62 are NOT 0b11,
       ;; then 0x62 refers to a legal BOUND instruction.  Otherwise, it signals
       ;; the beginning of the EVEX prefix.

       ;; Again, similar to the VEX prefix situation: though the second byte
       ;; acts as the distinguishing byte only in the 32-bit mode, we always
       ;; read the first two bytes of an EVEX prefix in this function for
       ;; simplicity.
       ((mv flg bound-distinguishing-byte x86)
        (if evex-byte0?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg)
        (!!ms-fresh :bound-distinguishing-byte-read-error flg))
       ;; If the instruction is indeed BOUND in the 32-bit mode, temp-rip is
       ;; incremented after the ModR/M is detected (see add-to-*ip following
       ;; modr/m? below).
       ((when (and evex-byte0?
                   (or 64-bit-modep
                       (and (not 64-bit-modep)
                            (equal (part-select
                                    bound-distinguishing-byte
                                    :low 6 :high 7)
                                   #b11)))))
        ;; Handle EVEX-encoded instructions separately.
        (b* (((mv flg temp-rip)
              (add-to-*ip proc-mode temp-rip 1 x86))
             ((when flg)
              (!!ms-fresh :evex-byte1-increment-error flg))
             (evex-prefixes
              (!evex-prefixes-slice :byte0 opcode/evex-byte 0))
             (evex-prefixes
              (!evex-prefixes-slice
               :byte1 bound-distinguishing-byte evex-prefixes)))
          (evex-decode-and-execute
           proc-mode
           start-rip temp-rip prefixes rex-byte evex-prefixes x86)))


       (opcode-byte opcode/evex-byte)

       ;; Possible values of opcode-byte:

       ;; The opcode-byte should not contain any of the (legacy) prefixes, REX
       ;; bytes, VEX prefixes, and EVEX prefixes -- by this point, all these
       ;; prefix bytes should have been processed.  So, here are the kinds of
       ;; values opcode-byte can have:

       ;; 1. An opcode of the one-byte opcode map: this function prefetches the
       ;;    ModR/M and SIB bytes for these opcodes.  The function
       ;;    one-byte-opcode-execute case-splits on this opcode byte and calls
       ;;    the appropriate instruction semantic function.

       ;; 2. #x0F -- two-byte or three-byte opcode indicator: modr/m? is set to
       ;;    NIL (see *64-bit-mode-one-byte-has-modr/m-ar* and
       ;;    *32-bit-mode-one-byte-has-modr/m-ar*).  No ModR/M and SIB bytes
       ;;    are prefetched by this function for the two-byte or three-byte
       ;;    opcode maps.  In one-byte-opcode-execute, we call
       ;;    two-byte-opcode-decode-and-execute, where we fetch the ModR/M and
       ;;    SIB bytes for the two-byte opcodes or dispatch control to
       ;;    three-byte-opcode-decode-and-execute when appropriate (i.e., when
       ;;    the byte following #x0F is either #x38 or #x3A).  Note that in
       ;;    this function, temp-rip will not be incremented beyond this point
       ;;    for these opcodes --- i.e., it points at the byte *following*
       ;;    #x0F.

       ;; The modr/m and sib byte prefetching in this function is biased
       ;; towards the one-byte opcode map.  The functions
       ;; two-byte-opcode-decode-and-execute and
       ;; three-byte-opcode-decode-and-execute do their own prefetching.  We
       ;; made this choice to take advantage of the fact that the most
       ;; frequently encountered instructions are from the one-byte opcode map.
       ;; Another reason is that the instruction encoding syntax is clearer to
       ;; understand this way; this is a nice way of seeing how one opcode map
       ;; "escapes" into another.

       (modr/m? (one-byte-opcode-ModR/M-p proc-mode opcode-byte))
       ((mv flg (the (unsigned-byte 8) modr/m) x86)
        (if modr/m?
            (if (or vex-byte0? evex-byte0?)
                ;; The above will be true only if the instruction is LES or LDS
                ;; or BOUND in the 32-bit mode.
                (mv nil les/lds-distinguishing-byte x86)
              (rme08 proc-mode temp-rip #.*cs* :x x86))
          (mv nil 0 x86)))
       ((when flg)
        (!!ms-fresh :modr/m-byte-read-error flg))

       ((mv flg temp-rip)
        (if modr/m?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg))

       (sib? (and modr/m?
                  (b* ((p4? (eql #.*addr-size-override*
                                 (the (unsigned-byte 8) (prefixes->adr prefixes))))
                       (16-bit-addressp (eql 2 (select-address-size
                                                proc-mode p4? x86))))
                    (x86-decode-SIB-p modr/m 16-bit-addressp))))

       ((mv flg (the (unsigned-byte 8) sib) x86)
        (if sib?
            (rme08 proc-mode temp-rip #.*cs* :x x86)
          (mv nil 0 x86)))
       ((when flg)
        (!!ms-fresh :sib-byte-read-error flg))

       ((mv flg temp-rip)
        (if sib?
            (add-to-*ip proc-mode temp-rip 1 x86)
          (mv nil temp-rip)))
       ((when flg) (!!ms-fresh :increment-error flg)))

    (one-byte-opcode-execute
     proc-mode start-rip temp-rip prefixes rex-byte opcode-byte
     modr/m sib x86))

  ///

  (defrule x86p-x86-fetch-decode-execute
    (implies (x86p x86)
             (x86p (x86-fetch-decode-execute x86)))
    :enable add-to-*ip-is-i48p-rewrite-rule)

  (defthmd ms-fault-and-x86-fetch-decode-and-execute
    (implies (and (x86p x86)
                  (or (ms x86) (fault x86)))
             (equal (x86-fetch-decode-execute x86) x86)))

  (defthm x86-fetch-decode-execute-opener
    ;; TODO: Extend to VEX and EVEX prefixes when necessary.
    (implies
     (and
      (not (ms x86))
      (not (fault x86))
      (equal proc-mode (x86-operation-mode x86))
      (equal start-rip (read-*ip proc-mode x86))
      (equal 64-bit-modep (equal proc-mode #.*64-bit-mode*))
      (not (mv-nth 0 (get-prefixes proc-mode start-rip 0 0 15 x86)))
      (equal prefixes (mv-nth 1 (get-prefixes proc-mode start-rip 0 0 15 x86)))
      (equal rex-byte (mv-nth 2 (get-prefixes proc-mode start-rip 0 0 15 x86)))
      (equal opcode/vex/evex-byte (prefixes->nxt prefixes))
      (equal prefix-length (prefixes->num prefixes))
      (equal temp-rip0
             (mv-nth 1 (add-to-*ip proc-mode start-rip (1+ prefix-length) x86)))

      ;; *** No VEX prefixes ***
      (not (equal opcode/vex/evex-byte #.*vex3-byte0*))
      (not (equal opcode/vex/evex-byte #.*vex2-byte0*))
      ;; *** No EVEX prefixes ***
      (not (equal opcode/vex/evex-byte #.*evex-byte0*))

      (equal modr/m?
             (one-byte-opcode-ModR/M-p proc-mode opcode/vex/evex-byte))
      (equal modr/m (if modr/m?
                        (mv-nth 1 (rme08 proc-mode temp-rip0 #.*cs* :x x86))
                      0))
      (equal temp-rip1 (if modr/m?
                           (mv-nth 1 (add-to-*ip proc-mode temp-rip0 1 x86))
                         temp-rip0))
      (equal p4? (equal #.*addr-size-override* (prefixes->adr prefixes)))
      (equal 16-bit-addressp (equal 2 (select-address-size proc-mode p4? x86)))
      (equal sib? (and modr/m? (x86-decode-sib-p modr/m 16-bit-addressp)))
      (equal sib (if sib? (mv-nth 1 (rme08 proc-mode temp-rip1 #.*cs* :x x86)) 0))

      (equal temp-rip2 (if sib?
                           (mv-nth 1 (add-to-*ip proc-mode temp-rip1 1 x86))
                         temp-rip1))

      (or (app-view x86) (not (marking-view x86)))
      (not (mv-nth 0 (add-to-*ip proc-mode start-rip (1+ prefix-length) x86)))
      (if modr/m?
          (and (not (mv-nth 0 (add-to-*ip proc-mode temp-rip0 1 x86)))
               (not (mv-nth 0 (rme08 proc-mode temp-rip0 #.*cs* :x x86))))
        t)
      (if sib?
          (and (not (mv-nth 0 (add-to-*ip proc-mode temp-rip1 1 x86)))
               (not (mv-nth 0 (rme08 proc-mode temp-rip1 #.*cs* :x x86))))
        t)
      (x86p x86)
      ;; Print the rip and the first opcode byte of the instruction
      ;; under consideration after all the non-trivial hyps (above) of
      ;; this rule have been relieved:
      (syntaxp
       (and (not (cw "~% [ x86instr @ rip: ~p0 ~%" start-rip))
            (not (cw "              op0: ~s0 ] ~%"
                     (str::hexify (unquote opcode/vex/evex-byte)))))))
     (equal
      (x86-fetch-decode-execute x86)
      (one-byte-opcode-execute
       proc-mode start-rip temp-rip2 prefixes rex-byte
       opcode/vex/evex-byte modr/m sib x86)))
    :hints (("Goal"
             :cases ((app-view x86))
             :in-theory (e/d ()
                             (one-byte-opcode-execute
                              signed-byte-p
                              not
                              member-equal))))))

(in-theory (e/d (vex-decode-and-execute
                 evex-decode-and-execute
                 one-byte-opcode-execute
                 two-byte-opcode-execute
                 first-three-byte-opcode-execute
                 second-three-byte-opcode-execute)
                ()))

;; ----------------------------------------------------------------------

;; Running the interpreter:

;; Schedule: (in the M1 style)

(defun binary-clk+ (i j)
  (+ (nfix i) (nfix j)))

(defthm clk+-associative
  (implies (binary-clk+ (binary-clk+ i j) k)
           (binary-clk+ i (binary-clk+ j k))))

(defmacro clk+ (&rest args)
  (if (endp args)
      0
    (if (endp (cdr args))
        (car args)
      `(binary-clk+ ,(car args)
                    (clk+ ,@(cdr args))))))

(define x86-run
  ;; I fixed n to a fixnum for efficiency.  Also, executing more than
  ;; 2^59 instructions in one go seems kind of daunting.
  ((n :type (unsigned-byte 59))
   x86)

  :parents (x86-decoder)
  :short "Top-level specification function for the x86 ISA model"
  :long "<p>@('x86-run') returns the x86 state obtained by executing
  @('n') instructions or until it halts, whatever comes first.  It
  simply called the step function @(see x86-fetch-decode-execute)
  recursively.</p>"

  :returns (x86 x86p :hyp (x86p x86))

  (cond ((fault x86)
         x86)
        ((ms x86)
         x86)
        ((mbe :logic (zp n)
              :exec (equal 0 n))
         x86)
        (t (let* ((x86 (x86-fetch-decode-execute x86))
                  (n (the (unsigned-byte 59) (1- n))))
             (x86-run n x86))))


  ///

  (defthmd x86-run-and-x86-fetch-decode-and-execute-commutative
    ;; x86-fetch-decode-execute and x86-run can commute.
    (implies (and (natp k)
                  (x86p x86)
                  (not (ms x86))
                  (not (fault x86)))
             (equal (x86-run k (x86-fetch-decode-execute x86))
                    (x86-fetch-decode-execute (x86-run k x86))))
    :hints (("Goal" :in-theory (e/d
                                (ms-fault-and-x86-fetch-decode-and-execute) ()))))


  ;; Some opener theorems for x86-run:

  (defthm x86-run-halted
    (implies (or (ms x86) (fault x86))
             (equal (x86-run n x86) x86)))

  (defthm x86-run-opener-not-ms-not-fault-zp-n
    (implies (and (syntaxp (quotep n))
                  (zp n))
             (equal (x86-run n x86) x86)))

  (defthm x86-run-opener-not-ms-not-zp-n
    (implies (and (not (ms x86))
                  (not (fault x86))
                  (syntaxp (quotep n))
                  (not (zp n)))
             (equal (x86-run n x86)
                    (x86-run (1- n) (x86-fetch-decode-execute x86)))))

  ;; To enable compositional reasoning, we prove the following two
  ;; theorems:

  (defthm x86-run-plus
    (implies (and (natp n1)
                  (natp n2)
                  (syntaxp (quotep n1)))
             (equal (x86-run (clk+ n1 n2) x86)
                    (x86-run n2 (x86-run n1 x86)))))

  (encapsulate
    ()

    (local (include-book "arithmetic/top" :dir :system))

    (defthmd x86-run-plus-1
      (implies (and (natp n1)
                    (natp n2)
                    (syntaxp (quotep n1)))
               (equal (x86-run (clk+ n1 n2) x86)
                      (x86-run n1 (x86-run n2 x86)))))))

(in-theory (disable binary-clk+))

;; ----------------------------------------------------------------------

(define x86-run-steps1
  ((n :type (unsigned-byte 59))
   (n0 :type (unsigned-byte 59))
   x86)

  :enabled t
  :guard (and (natp n)
              (natp n0)
              (<= n n0))

  (let* ((diff (the (unsigned-byte 59) (- n0 n))))

    (cond ((ms x86)
           (mv diff x86))
          ((fault x86)
           (mv diff x86))
          ((zp n)
           (let* ((ctx 'x86-run)
                  (x86 (!!ms-fresh :timeout t)))
             (mv diff x86)))
          (t (let* ((x86 (x86-fetch-decode-execute x86))
                    (n-1 (the (unsigned-byte 59) (1- n))))
               (x86-run-steps1 n-1 n0 x86))))))

(define x86-run-steps
  ((n :type (unsigned-byte 59))
   x86)

  :parents (x86-decoder)
  :short "An alternative to @(see x86-run)"
  :long "<p> @('x86-run-steps') returns two values --- number of steps
  taken by the machine before it comes to a halt and the x86 state.
  Note that the number of steps will always be less than or equal to
  @('n').</p>"

  (x86-run-steps1 n n x86)

  ///

  (defthm x86-run-steps1-is-x86-run-ms
    (implies (ms x86)
             (equal (mv-nth 1 (x86-run-steps1 n n0 x86))
                    (x86-run n x86))))

  (defthm x86-run-steps1-is-x86-run-zp-n
    (implies (and (not (ms x86))
                  (not (fault x86))
                  (zp n))
             (equal (mv-nth 1 (x86-run-steps1 n n0 x86))
                    (!ms (list (list* 'x86-run
                                      :rip (rip x86)
                                      '(:timeout t)))
                         (x86-run n x86))))
    :hints (("Goal" :expand (x86-run n x86))))

  (defthm x86-run-steps1-open
    (implies (and (not (ms x86))
                  (not (fault x86))
                  (not (zp n)))
             (equal (mv-nth 1 (x86-run-steps1 n n0 x86))
                    (mv-nth 1 (x86-run-steps1 (1- n) n0
                                              (x86-fetch-decode-execute x86)))))))

(in-theory (disable x86-run-steps1))

;; ----------------------------------------------------------------------

(define x86-fetch-decode-execute-halt
  ((halt-address :type (signed-byte   #.*max-linear-address-size*))
   x86)
  :enabled t
  :parents (x86-decoder)
  :inline t

  :short "Alternative version of @(tsee x86-fetch-decode-execute) that sets the
  @('MS') field if @('rip') is equal to @('halt-address')"

  :returns (x86 x86p :hyp (x86p x86))

  :prepwork
  ((local (in-theory (e/d* () (signed-byte-p unsigned-byte-p not)))))

  (b* ((ctx __function__))
    (if (equal (the (signed-byte #.*max-linear-address-size*)
                 (rip x86))
               halt-address)
        (!!ms-fresh)
      (x86-fetch-decode-execute x86))))

(define x86-run-halt
  ((halt-address :type (signed-byte   #.*max-linear-address-size*))
   (n            :type (unsigned-byte 59))
   x86)

  :parents (x86-decoder)
  :short "Alternative version of @(tsee x86-run) that uses @(tsee
  x86-fetch-decode-execute-halt) instead of @(tsee x86-fetch-decode-execute)"

  :returns (x86 x86p :hyp (x86p x86))

  (cond ((fault x86) x86)
        ((ms x86) x86)
        ((mbe :logic (zp n) :exec (equal 0 n)) x86)
        (t (let* ((x86 (x86-fetch-decode-execute-halt halt-address x86))
                  (n (the (unsigned-byte 59) (1- n))))
             (x86-run-halt halt-address n x86)))))

;; ----------------------------------------------------------------------
