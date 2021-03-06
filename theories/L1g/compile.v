
Require Import Coq.Lists.List.
Require Import Coq.Strings.String.
Require Import Coq.omega.Omega.
Require Import Coq.Bool.Bool.
Require Import Template.Ast Template.kernel.univ.
Require Import Common.Common.

Local Open Scope string_scope.
Local Open Scope bool.
Local Open Scope list.
Set Implicit Arguments.

  
(** A slightly cleaned up notion of object term.
*** The simultaneous definitions of [Terms] and [Defs] make
*** inductions over this type long-winded but straightforward.
*** This version contains type fields.
*** There is a special term constructor for axioms, which
*** should be seen as having a type but no value.
**)
(** Assumptions:
*** there are no nested applicatione and every application has an argument
*** every Fixpoint has at least one function
**)
Inductive Term : Type :=
| TRel       : nat -> Term
| TSort      : Srt -> Term
| TProof     : Term -> Term
| TProd      : name -> Term (* type *) -> Term -> Term
| TLambda    : name -> Term (* type *) -> Term -> Term
| TLetIn     : name ->
               Term (* dfn *) -> Term (* type *) -> Term (* body *) -> Term
| TApp       : Term -> Term (* first arg must exist *) -> Terms -> Term
| TConst     : string -> Term
| TInd       : inductive -> Term
| TConstruct : inductive -> nat (* constructor # *) ->
               nat (* # pars *) -> nat (* # args *) -> Term
                       (* use Defs to code case branches *)
| TCase      : (inductive * nat) (* # of pars *) -> Term (* type *) ->
               Term (* discriminee *) -> Brs (* # args, branch *) -> Term
| TFix       : Defs (* all mutual bodies *)->
               nat (* indx of this body *) -> Term
| TWrong     : string -> Term
with Terms : Type :=
| tnil : Terms
| tcons : Term -> Terms -> Terms
with Brs: Type :=
     | bnil: Brs
     | bcons: nat -> Term -> Brs -> Brs
with Defs : Type :=
| dnil : Defs
| dcons : name -> Term -> Term -> nat -> Defs -> Defs.
Hint Constructors Term Terms Brs Defs.
Scheme Trm_ind' := Induction for Term Sort Prop
  with Trms_ind' := Induction for Terms Sort Prop
  with Brs_ind' := Induction for Brs Sort Prop
  with Defs_ind' := Induction for Defs Sort Prop.
Combined Scheme TrmTrmsBrsDefs_ind
         from Trm_ind', Trms_ind', Brs_ind', Defs_ind'.
Notation prop := (TSort SProp).
Notation set_ := (TSort SSet).
Notation type_ := (TSort SType).
Notation tunit t := (tcons t tnil).
Notation btunit n t := (bcons n t bnil).
Notation dunit nm t m := (dcons nm t m dnil).


(** Printing terms in exceptions for debugging purposes **)
Fixpoint print_template_term (t:term) : string :=
  match t with
    | tRel n => " (" ++ (nat_to_string n) ++ ") "
    | tSort _ => " SRT "
    | tCast _ _ _ => " CAST "
    | tProd _ _ _ => " PROD "
    | tLambda _ _ _ => " LAM "
    | tLetIn _ _ _ _ => " LET "
    | tApp fn args =>
      " (APP" ++ (print_template_term fn) ++ " _ " ++ ") "
    | tConst s us => "[" ++ s ++ "]"
    | tInd i us => ("(IND:" ++ print_inductive i ++ ")")
    | tConstruct i n us =>
      "(CSTR:" ++ print_inductive i ++ ":" ++ (nat_to_string n) ++ ") "
    | tCase n _ mch _ =>
      " (CASE " ++ (nat_to_string (snd n)) ++ " _ " ++
                (print_template_term mch) ++ " _ " ++") "
    | tFix _ n => " (FIX " ++ (nat_to_string n) ++ ") "
    | _ =>  " Wrong "
  end.

(** needed for compiling L1 to L1g **)
Function tappend (ts1 ts2:Terms) : Terms :=
  match ts1 with
    | tnil => ts2
    | tcons t ts => tcons t (tappend ts ts2)
  end.

(** No nested "TProof" ***)
Function mkProof (t:Term) : Term :=
  match t with
    | (TProof u) as x => x
    | u => TProof u
  end.
(***  test **
Eval cbv in mkProof prop.
Eval cbv in mkProof (TProof (TProof (TProof prop))).
 **********)

(************************
Definition pre_checked_term_Term:
  forall n,
  (forall (t:term), WF_term n t = true -> Term) *
  (forall (ts:list term), WF_terms n ts = true -> Terms) *
  (forall (ds:list (def term)), WF_defs n ds = true -> Defs).
Proof.
  induction n; repeat split; try (solve[cbn; intros; discriminate]).
  destruct IHn as [[j1 j2] j3]; intros x hx; destruct x; cbn in hx;
  try discriminate.
  - exact (TRel n0).
  - apply TSort. destruct s; [ exact SProp | exact SSet | exact SType].
  - destruct (andb_true_true _ _ hx) as [k2 k1].
    refine (TCast (j1 _ k2) c (j1 _ k1)).
  - destruct (andb_true_true _ _ hx) as [k1 k2].
    refine (TProd n0 (j1 _ k1) (j1 _ k2)).
  - destruct (andb_true_true _ _ hx) as [k1 k2].
    refine (TLambda n0 (j1 _ k1) (j1 _ k2)).
  - destruct (andb_true_true _ _ hx) as [z1 k3].
    destruct (andb_true_true _ _ z1) as [k1 k2].
    refine (TLetIn n0 (j1 _ k1) (j1 _ k2) (j1 _ k3)).
  - destruct l. discriminate.
    destruct (andb_true_true _ _ hx) as [z1 k4].
    destruct (andb_true_true _ _ z1) as [z2 k3].
    destruct (andb_true_true _ _ z2) as [k1 k2].
    refine (TApp (j1 _ k2) (j1 _ k3) (j2 _ k4)).
  - exact (TConst s).
  - exact (TInd i).
  - exact (TConstruct i n0).
  - destruct (andb_true_true _ _ hx) as [z1 k3].
    destruct (andb_true_true _ _ z1) as [k1 k2].
    refine (TCase (p, map fst l) (j1 _ k1) (j1 _ k2) (j2 _ k3)).
  - refine (TFix (j3 _ hx) n).
  - destruct IHn as [[j1 j2] j3]. destruct ts; intros.
    + exact tnil.
    + cbn in H. destruct (andb_true_true _ _ H) as [k2 k1].
      refine (tcons (j1 _ k2) (j2 _ k1)).
  - destruct IHn as [[j1 j2] j3]. destruct ds; intros.   
    + exact dnil.
    + cbn in H.
      destruct (andb_true_true _ _ H) as [z1 k3].
      destruct (andb_true_true _ _ z1) as [k1 k2].
      refine (dcons (dname _ d) (j1 _ k1) (j1 _ k2) (rarg _ d) (j3 _ k3)).
Defined.

(** following definition only works for _ground_ terms t **)
Definition
  checked_term_Term (t:term) : WF_term (termSize t) t = true -> Term :=
  (fst (fst (pre_checked_term_Term (termSize t)))) t.
****************************)

(** Store strings reversed to make inequality testing faster **
(***  FIX: DEBUGGIBG ONLY  strip off "Coq.Init." ******)
Fixpoint revStr (str accum: string): string :=
  match str with
    | String "C" (String "o" (String "q" (String "."
       (String "I" (String "n" (String "i" (String "t"
        (String "." x)))))))) => x
    | String "T" (String "o" (String "p" (String "." x))) => x
    | y => y
  end.
 (***
  match str with
    | String asci st => revStr st (String asci accum)
    | EmptyString => accum
  end.
***)
Definition revInd (i:inductive): inductive :=
  match i with
    | mkInd nm m => mkInd (revStr nm EmptyString) m
  end.
Definition rev_npars (np: inductive * nat) :=
  match np with
    | (i, n) => (revInd i, n)
  end.
 **************************)

(** operations on Brs and Defs **)
Fixpoint blength (ts:Brs) : nat :=
  match ts with 
    | bnil => 0
    | bcons _ _ ts => S (blength ts)
  end.

(** operations on Defs **)
Fixpoint dlength (ts:Defs) : nat :=
  match ts with 
    | dnil => 0
    | dcons _ _ _ _ ts => S (dlength ts)
  end.

Function dnthBody (n:nat) (l:Defs) {struct l} : option (Term * nat) :=
  match l with
    | dnil => None
    | dcons _ _ x ix t => match n with
                           | 0 => Some (x, ix)
                           | S m => dnthBody m t
                         end
  end.

Function bnth (n:nat) (l:Brs) {struct l} : option (Term * nat) :=
  match l with
    | bnil => None
    | bcons ix x bs => match n with
                           | 0 => Some (x, ix)
                           | S m => bnth m bs
                       end
  end.

Lemma n_lt_0 : forall n, n < 0 -> Term * nat.
Proof.
  intros. omega.
Defined.

Fixpoint
  dnth_lt (ds:Defs) : forall (n:nat), (n < dlength ds) -> Term * nat :=
  match ds return forall n, (n < dlength ds) -> Term * nat with
  | dnil => n_lt_0
  | dcons nm ty bod ri es =>
    fun n =>
      match n return (n < dlength (dcons nm ty bod ri es)) -> Term * nat with
        | 0 => fun _ => (bod, ri)
        | S m => fun H => dnth_lt es (lt_S_n _ _ H)
      end
  end.

(** syntactic control of "TApp": no nested apps, app must have an argument **)
Function mkApp (t:Term) (args:Terms) {struct t} : Term :=
  match t with
    | TApp fn b bs => TApp fn b (tappend bs args)
    | fn => match args with
              | tnil => fn
              | tcons c cs => TApp fn c cs
            end
  end.

(** translate Gregory Malecha's [term] into my [Term] **)
Section datatypeEnv_sec.
  Variable datatypeEnv : environ Term.
  
Section term_Term_sec.
  Variable term_Term: term -> Term.
  Fixpoint terms_Terms (ts:list term) : Terms :=
    match ts with
      | nil => tnil
      | cons r rs => tcons (term_Term r) (terms_Terms rs)
    end.
  (* Fixpoint defs *)
  Fixpoint defs_Defs (ds: list (def term)) : Defs :=
   match ds with
     | nil => dnil
     | cons d ds =>
       dcons (dname _ d) (term_Term (dtype _ d))
             (term_Term (dbody _ d))  (rarg _ d) (defs_Defs ds )
   end.
  (* Case branches *)
  Fixpoint natterms_Brs (nts: list (nat * term)) : Brs :=
    match nts with
     | nil => bnil
     | cons (n,t) ds => bcons n (term_Term t) (natterms_Brs ds)
   end.
               
End term_Term_sec.

(* "prf" arg is true if inside a proof.  This allows to reject
** programs containing axioms that are used outside of proofs
*)
Function term_Term (t:term) : Term :=
  match t with
    | tRel n => TRel n
    | tSort srt =>
      TSort (match srt with 
             | (Level.lProp, false) :: nil => SProp
             | (Level.lSet, false) :: nil => SSet
             | _ => SType  (* throwing away sort info *)
             end)
    | tCast tm _ (tCast _ _ (tSort sProp)) => mkProof (term_Term tm)
    | tCast tm _ ty => term_Term tm
    | tProd nm ty bod => (TProd nm (term_Term ty) (term_Term bod))
    | tLambda nm ty bod => (TLambda nm (term_Term ty) (term_Term bod))
    | tLetIn nm dfn ty bod =>
      (TLetIn nm (term_Term dfn) (term_Term ty) (term_Term bod))
    | tApp fn us => mkApp (term_Term fn) (terms_Terms term_Term us)
    | tConst pth us =>   (* ref to axioms in environ made into [TAx] *)
      match lookup pth datatypeEnv with  (* only lookup ecTyp at this point! *)
      | Some (ecTyp _ _ _) =>
        TWrong ("term_Term:Const inductive or axiom: " ++ pth)
      | _  => TConst pth
      end
    | tInd ind us => TInd ind
    | tConstruct ind m us =>
      match cnstrArity datatypeEnv ind m with
        | Ret (npars, nargs) => TConstruct ind m npars nargs
        | Exc s => TWrong ("term_Term;tConstruct:" ++ s)
      end
    | tCase npars ty mch brs =>
      TCase npars (term_Term ty) (term_Term mch)
            (natterms_Brs term_Term brs)
    | tFix defs m => TFix (defs_Defs term_Term defs) m
    | _ => TWrong "(term_Term:Unknown)"
  end.

End datatypeEnv_sec.
    
(** environments and programs **)
(** given an L0 program, return an L1g environment containing the
*** datatypes of the program: this can be done without a term 
*** translation function
**)
Fixpoint program_Pgm_aux
         (dtEnv: environ Term) (g:global_declarations) (t : term)
         (e:environ Term) : Program Term :=
  match g with
  | nil => {| main := (term_Term dtEnv t); env := e |}
  | ConstantDecl nm cb :: p =>
    let decl :=
        match cb.(cst_body) with
        | Some t => pair nm (ecTrm (term_Term dtEnv t))
        | None => pair nm (ecAx Term)
        end
    in
    program_Pgm_aux dtEnv p t (cons decl e)
  | InductiveDecl nm mib :: p =>
    let Ibs := ibodies_itypPack mib.(ind_bodies) in
    program_Pgm_aux dtEnv p t (cons (pair nm (ecTyp Term mib.(ind_npars) Ibs)) e)
  end.

Definition program_Pgm (dtEnv: environ Term) (p:program) (e:environ Term) : Program Term :=
  let '(gctx, t) := p in
  program_Pgm_aux dtEnv gctx t e.

Definition program_Program (p:program) : Program Term :=
  let dtEnv := program_datatypeEnv (fst p) (nil (A:= (string * envClass Term))) in
  program_Pgm dtEnv p nil.
