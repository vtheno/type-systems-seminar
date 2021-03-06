#lang racket/base

(provide λ-ml/no-bool λ-ml
         ->val
         W inst gen unify ftv
         > types
         solve-constraint generate
         generate*
         types*)

(require redex/reduction-semantics
         racket/set
         "util.rkt")

(caching-enabled? #f)

(define-language λ-ml/no-bool
  (e ::=
     x
     (λ x e)
     (ap e e)
     (let x e e))
  (v ::=
     (λ x e))
  (E ::=
     hole
     (ap E e)
     (ap v E)
     (let x E e))
  (t ::=
     a
     (-> t t))
  (σ ::=
     t
     (all a σ))
  (Γ ::=
     •
     (extend Γ x σ))
  (S ::=
     •
     (extend-subst S a t))
  (C ::=
     ⊤
     (∧ C C)
     (= t t)
     (∃ a C))
  (x y ::= variable-not-otherwise-mentioned)
  (a b ::= variable-not-otherwise-mentioned)
  #:binding-forms
  (λ x e #:refers-to x)
  (let x e_1 e_2 #:refers-to x)
  (all a σ #:refers-to a)
  (∃ a C #:refers-to a))

(define-extended-language λ-ml λ-ml/no-bool
  (e ::=
     ....
     true
     false
     (if e e e))
  (v ::=
     ....
     true
     false)
  (E ::=
     ....
     (if E e e))
  (t ::=
     ....
     bool))

(define ->val
  (reduction-relation
   λ-ml
   #:domain e
   (--> (in-hole E (ap (λ x e) v))
        (in-hole E (substitute e x v))
        β-val)
   (--> (in-hole E (let x v e))
        (in-hole E (substitute e x v))
        let)
   (--> (in-hole E (if true e_1 e_2))
        (in-hole E e_1)
        if-true)
   (--> (in-hole E (if false e_1 e_2))
        (in-hole E e_2)
        if-false)))

(define-metafunction λ-ml
  lookup : Γ x -> σ
  [(lookup (extend Γ x σ) x)
   σ]
  [(lookup (extend Γ y σ) x)
   (lookup Γ x)
   (side-condition (not (equal? (term x) (term y))))])

(define-metafunction λ-ml
  \\ : (a ...) (a ...) -> (a ...)
  [(\\ (a ...) (b ...))
   ,(set-subtract (term (a ...)) (term (b ...)))])

(define-metafunction λ-ml
  ∪ : (a ...) ... -> (a ...)
  [(∪ (a ...) ...)
   ,(apply set-union (term ((a ...) ...)))])

(define-metafunction λ-ml
  ftv : any -> (a ...)
  ; Type variables
  [(ftv a)                       (a)]
  ; Types
  [(ftv (-> t_1 t_2))            (∪ (ftv t_1) (ftv t_2))]
  [(ftv bool)                    ()]
  ; Type schemes
  [(ftv (all a σ))               (\\ (ftv σ) (a))]
  ; Environments
  [(ftv •)                       ()]
  [(ftv (extend Γ x σ))          (∪ (ftv Γ) (ftv σ))]
  ; Substitutions
  [(ftv (extend-subst S a t))    (∪ (ftv S) (ftv t))]
  ; Constraints
  [(ftv ⊤)                       ()]
  [(ftv (∧ C_1 C_2))             (∪ (ftv C_1) (ftv C_2))]
  [(ftv (= t_1 t_2))             (∪ (ftv t_1) (ftv t_2))]
  [(ftv (∃ a C))                 (\\ (ftv C) (a))])

(define-metafunction λ-ml
  apply-subst : S any -> any
  [(apply-subst • any)
   any]
  ; This case should not be necessary by my understanding, but it
  ; avoids a problem.
  [(apply-subst S (extend-subst S_rest a t))
   (extend-subst (apply-subst S S_rest) a (apply-subst S t))]
  [(apply-subst (extend-subst S a t) any)
   (apply-subst S (substitute any a t))])

(define-metafunction λ-ml
  concat-subst : S S -> S
  [(concat-subst S •)
   S]
  [(concat-subst S (extend-subst S_1 a t))
   (extend-subst (concat-subst S S_1) a t)])

(define-metafunction λ-ml
  compose-subst : S S -> S
  [(compose-subst S_1 S_2) (concat-subst S_1 (apply-subst S_1 S_2))])

(define-metafunction λ-ml
  fresh : a any -> a
  [(fresh a any)
   ,(variable-not-in (term any) (term a))])

(define-judgment-form λ-ml
  #:mode (∈ I I)
  #:contract (∈ a (a ...))
  [---- in
   (∈ a (b_i ... a b_j ...))])

(define-judgment-form λ-ml
  #:mode (∉ I I)
  #:contract (∉ a (a ...))
  [(side-condition ,(not (member (term a) (term (b ...)))))
    ---- not-in
   (∉ a (b ...))])

(define-judgment-form λ-ml
  #:mode (not-a-type-variable I)
  #:contract (not-a-type-variable t)
  [(side-condition ,(not (redex-match? λ-ml a (term t))))
    ---- only
   (not-a-type-variable t)])

(define-judgment-form λ-ml
  #:mode (unify I I O)
  #:contract (unify t t S)
  
  [---- var-same
   (unify a a •)]
  
  [(∉ a (ftv t))
   ---- var-left
   (unify a t (extend-subst • a t))]
  
  [(not-a-type-variable t)
   (unify a t S)
   ---- var-right
   (unify t a S)]

  [---- bool
   (unify bool bool •)]
  
  [(unify t_11 t_21 S_1)
   (unify (apply-subst S_1 t_12) (apply-subst S_1 t_22) S_2)
   ---- arr
   (unify (-> t_11 t_12) (-> t_21 t_22) (compose-subst S_2 S_1))])

(define-metafunction λ-ml
  inst : (a ...) σ -> t
  [(inst (a ...) t)
   t]
  [(inst (a ...) (all b σ))
   (inst (a ... b_1) (substitute σ b b_1))
   (where b_1 (fresh b (a ...)))])
  
(define-metafunction λ-ml
  gen : (a ...) t -> σ
  [(gen () t)
   t]
  [(gen (a a_i ...) t)
   (all a (gen (a_i ...) t))])

(define-judgment-form λ-ml
  #:mode (W I I O O)
  #:contract (W Γ e S t)

  [(where t (inst (ftv Γ) (lookup Γ x)))
   ---- var
   (W Γ x • t)]

  [(W Γ e_1 S_1 t_1)
   (W (apply-subst S_1 Γ) e_2 S_2 t_2)
   (where a (fresh β (Γ S_1 S_2 t_1 t_2)))
   (unify (apply-subst S_2 t_1) (-> t_2 a) S_3)
   ---- app
   (W Γ (ap e_1 e_2) (compose-subst S_3 (compose-subst S_2 S_1)) (apply-subst S_3 a))]

  [(where a (fresh α Γ))
   (W (extend Γ x a) e S t)
   ---- abs
   (W Γ (λ x e) S (-> (apply-subst S a) t))]

  [(W Γ e_1 S_1 t_1)
   (where σ (gen (\\ (ftv t_1) (ftv (apply-subst S_1 Γ))) t_1))
   (W (extend (apply-subst S_1 Γ) x σ) e_2 S_2 t_2)
   ---- let
   (W Γ (let x e_1 e_2) (compose-subst S_2 S_1) t_2)]

  [---- true
   (W Γ true • bool)]

  [---- false
   (W Γ false • bool)]

  [(W Γ e_1 S_1 t_1)
   (W (apply-subst S_1 Γ) e_2 S_2 t_2)
   (W (apply-subst (compose-subst S_2 S_1) Γ) e_3 S_3 t_3)
   (unify (apply-subst (compose-subst S_3 S_2) t_1) bool S_4)
   (unify (apply-subst (compose-subst S_4 S_3) t_2) (apply-subst S_4 t_3) S_5)
   (where S (compose-subst S_5 (compose-subst S_4 (compose-subst S_3 (compose-subst S_2 S_1)))))
   ---- if
   (W Γ (if e_1 e_2 e_3) S (apply-subst (compose-subst S_5 S_4) t_3))])

(define-judgment-form λ-ml
  #:mode (> I O)
  #:contract (> σ t)
  [---- mono
   (> t t)]
  [(where/hidden t_1 guess-type)
   (> (substitute σ a t_1) t)
   ---- all
   (> (all a σ) t)])

(define-judgment-form λ-ml
  #:mode (types I I O)
  #:contract (types Γ e t)

  ;; We start with the simply-typed λ calculus (with mono-types):
  [---- var
   (types Γ x (lookup Γ x))]

  [(where/hidden t_1 guess-type)
   (types (extend Γ x t_1) e t_2)
   ---- abs
   (types Γ (λ x e) (-> t_1 t_2))]

  [(types Γ e_1 (-> t_2 t))
   (types Γ e_2 t_2)
   ---- app
   (types Γ (ap e_1 e_2) t)]

  ;; And we add let, still with mono-types:
  [(types Γ e_1 t_1)
   (types (extend Γ x t_1) e_2 t_2)
   ---- let
   (types Γ (let x e_1 e_2) t_2)]

  ;; Polymorphism via copying, incorrect and correct.
  [(types Γ (substitute e_2 x e_1) t_2)
   ---- let-copy/wrong
   (types Γ (let x e_1 e_2) t_2)]

  [(types Γ e_1 t_1)
   (types Γ (substitute e_2 x e_1) t_2)
   ---- let-copy
   (types Γ (let x e_1 e_2) t_2)]
  
  ;; The logical type system uses explicit inst and gen rules that can happen
  ;; anywhere, and let is modified to allow binding a type scheme σ:
  [(types Γ e (all a σ))
   (where/hidden t fake-type)
   ---- inst
   (types Γ e (substitute σ a t))]

  [(types Γ e σ)
   (where a (fresh α Γ))
   ---- gen
   (types Γ e (all a σ))]

  [(types Γ e_1 σ_1)
   (types (extend Γ x σ_1) e_2 σ_2)
   ---- let-poly
   (types Γ (let x e_1 e_2) σ_2)]

  ;; The algorithmic type system combines each of var and inst with another rule
  ;; and discards all of var, inst, let, and gen.
  [(> (lookup Γ x) t)
   ---- var-inst
   (types Γ x t)]

  [(types Γ e_1 t_1)
   (where σ_1 (gen (\\ (ftv t_1) (ftv Γ)) t_1))
   (types (extend Γ x σ_1) e_2 t)
   ---- let-gen
   (types Γ (let x e_1 e_2) t)]

  ;; Here we add bool as a base type.
  [---- true
   (types Γ true bool)]

  [---- false
   (types Γ false bool)]

  [(types Γ e_1 bool)
   (types Γ e_2 t)
   (types Γ e_3 t)
   ---- if
   (types Γ (if e_1 e_2 e_3) t)])

(define-judgment-form λ-ml
  #:mode (solve-constraint I O)
  #:contract (solve-constraint C S)

  [---- true
   (solve-constraint ⊤ •)]

  [(solve-constraint C_1 S_1)
   (solve-constraint (apply-subst S_1 C_2) S_2)
   ---- and
   (solve-constraint (∧ C_1 C_2) (compose-subst S_2 S_1))]

  [(unify t_1 t_2 S)
   ---- equals
   (solve-constraint (= t_1 t_2) S)]

  [(where b (fresh a C))
   (solve-constraint (substitute C a b) S)
   ---- exists
   (solve-constraint (∃ a C) S)])

(define-metafunction λ-ml
  generate : Γ e t -> C

  [(generate Γ x t)
   (= t t_1)
   (where t_1 (inst (ftv Γ) (lookup Γ x)))]

  [(generate Γ (λ x e) t)
   (∃ a (∃ b (∧ (= t (-> a b)) (generate (extend Γ x a) e b))))
   (where a (fresh α (Γ t)))
   (where b (fresh β (Γ t a)))]

  [(generate Γ (ap e_1 e_2) t)
   (∃ a (∧ (generate Γ e_1 (-> a t)) (generate Γ e_2 a)))
   (where a (fresh α (Γ t)))]

  [(generate Γ (let x e_1 e_2) t)
   (generate (extend Γ x σ_1) e_2 t)
   (where a (fresh α Γ))
   (where C_1 (generate Γ e_1 a))
   (judgment-holds (solve-constraint C_1 S))
   (where t_1 (apply-subst S a))
   (where σ_1 (gen (\\ (ftv t_1) (ftv Γ)) t_1))]

  [(generate Γ true t)
   (= t bool)]

  [(generate Γ false t)
   (= t bool)]

  [(generate Γ (if e_1 e_2 e_3) t)
   (∧ (generate Γ e_1 bool) (∧ (generate Γ e_2 t) (generate Γ e_3 t)))])

(define-judgment-form λ-ml
  #:mode (inst* I I O O)
  #:contract (inst* (a ...) σ t (a ...))

  [---- mono
   (inst* (b ...) t t (b ...))]

  [(where b (fresh a (b_0 ...)))
   (inst* (b_0 ... b) (substitute σ a b) t (b_1 ...))
   ---- all
   (inst* (b_0 ...) (all a σ) t (b_1 ...))])

(define-judgment-form λ-ml
  #:mode (generate* I I I O O O)
  #:contract (generate* (a ...) Γ e t C (a ...))

  [(inst* (b_0 ...) (lookup Γ x) t (b_1 ...))
   ---- var
   (generate* (b_0 ...) Γ x t ⊤ (b_1 ...))]

  [(where a (fresh α (b_0 ...)))
   (generate* (b_0 ... a) (extend Γ x a) e t C (b_1 ...))
   ---- abs
   (generate* (b_0 ...) Γ (λ x e) (-> a t) C (b_1 ...))]

  [(generate* (b_0 ...) Γ e_1 t_1 C_1 (b_1 ...))
   (generate* (b_1 ...) Γ e_2 t_2 C_2 (b_2 ...))
   (where a (fresh α (b_2 ...)))
   (where C (∧ (= t_1 (-> t_2 a)) (∧ C_1 C_2)))
   ---- app
   (generate* (b_0 ...) Γ (ap e_1 e_2) a C (b_2 ... a))]

  [(generate* (b_0 ...) Γ e_1 t_1 C_1 (b_1 ...))
   (solve-constraint C_1 S)
   (where σ_1 (gen (\\ (ftv (apply-subst S t_1)) (ftv Γ)) (apply-subst S t_1)))
   (generate* (b_1 ...) (extend Γ x σ_1) e_2 t_2 C_2 (b_2 ...))
   ---- let
   (generate* (b_0 ...) Γ (let x e_1 e_2) t_2 C_2 (b_2 ...))]

  [---- true
   (generate* (b ...) Γ true bool ⊤ (b ...))]

  [---- false
   (generate* (b ...) Γ false bool ⊤ (b ...))]

  [(generate* (b_0 ...) Γ e_1 t_1 C_1 (b_1 ...))
   (generate* (b_1 ...) Γ e_2 t_2 C_2 (b_2 ...))
   (generate* (b_2 ...) Γ e_3 t_3 C_3 (b_3 ...))
   (where C (∧ (= t_1 bool) (∧ (= t_2 t_3) (∧ C_1 (∧ C_2 C_3)))))
   ---- if
   (generate* (b_0 ...) Γ (if e_1 e_2 e_3) t_2 C (b_3 ...))])

(define-judgment-form λ-ml
  #:mode (types* I I O)
  #:contract (types* string e σ)

  [(W • e S t_*)
   (where t (apply-subst S t_*))
   ---- "algo-w"
   (types* "W" e (gen (ftv t) t))]
  
  [(solve-constraint (generate • e α) S)
   (where t (apply-subst S α))
   ---- "check"
   (types* "↓" e (gen (ftv t) t))]
  
  [(generate* () • e t_* C (b ...))
   (solve-constraint C S)
   (where t (apply-subst S t_*))
   ---- "synthesize"
   (types* "↑" e (gen (ftv t) t))])