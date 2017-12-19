(* 
  Proof of correctness of the Clight code generation phase of CertiCoq 

  > Relates values to location in memory (syntactic)
  > Relates expression to statements (syntactic)
  > Relates L7 values (header, payload) to L7 values after GC (syntactic, up to non-function pointer location)
  > Relates L6 states to L7 states according to execution semantics

 *)
From L6 Require Import cps eval
cps_util
List_util
identifiers
tactics.

From L7 Require Import L6_to_Clight.



Require Import Coq.Arith.Arith Coq.NArith.BinNat ExtLib.Data.String ExtLib.Data.List Coq.omega.Omega Coq.Program.Program Coq.micromega.Psatz Coq.Sets.Ensembles Coq.Logic.Decidable Coq.Lists.ListDec Coq.Relations.Relations.

Require Import compcert.common.AST
        compcert.common.Errors
        compcert.lib.Integers
        compcert.cfrontend.Cop
        compcert.cfrontend.Ctypes
        compcert.cfrontend.Clight
        compcert.common.Values
        compcert.common.Globalenvs
        compcert.common.Memory.



 

Definition loc:Type := block * int.
Definition int_size := size_chunk Mint32.
Definition max_args :=  Int.repr 1024%Z.

Notation intTy := (Tint I32 Signed
                        {| attr_volatile := false; attr_alignas := None |}).

Notation uintTy := (Tint I32 Unsigned
                         {| attr_volatile := false; attr_alignas := None |}).

Notation longTy := (Tlong Signed
                        {| attr_volatile := false; attr_alignas := None |}).

Notation ulongTy := (Tlong Unsigned
                        {| attr_volatile := false; attr_alignas := None |}).


(* TODO: move to identifiers *)
Inductive bound_var_val: L6.cps.val -> Ensemble var :=
| Bound_Vconstr :
    forall c vs v x, 
    bound_var_val v x ->
    List.In v vs ->
    bound_var_val (Vconstr c vs) x
| Bound_Vfun:
    forall fds rho x f,
    bound_var_fundefs fds x ->
    bound_var_val (Vfun rho fds f) x.


(**** Representation relation for L6 values, expressions and functions ****)
Section RELATION.

  (* same as L6_to_Clight *)
  Variable (argsIdent : ident).
  Variable (allocIdent : ident).
  Variable (limitIdent : ident).
  Variable (gcIdent : ident).
  Variable (mainIdent : ident).
  Variable (bodyIdent : ident).
  Variable (threadInfIdent : ident).
  Variable (tinfIdent : ident).
  Variable (heapInfIdent : ident).
  Variable (numArgsIdent : ident).  
  Variable (isptrIdent: ident). (* ident for the isPtr external function *)
  Variable (caseIdent:ident).


    Variable cenv:L6.cps.cEnv.
  Variable fenv:L6.cps.fEnv.
  Variable finfo_env: M.t positive. (* map from a function name to its type info *)
  Variable p:program.
  
  
  (* This should be a definition rather than a parameter, computed once and for all from cenv *)
  Variable rep_env: M.t cRep.

  
  Notation threadStructInf := (Tstruct threadInfIdent noattr).
Notation threadInf := (Tpointer threadStructInf noattr).

Notation funTy := (Tfunction (Tcons threadInf Tnil) Tvoid
                            {|
                              cc_vararg := false;
                              cc_unproto := false;
                              cc_structret := false |}).

Notation pfunTy := (Tpointer funTy noattr).

Notation gcTy := (Tfunction (Tcons (Tpointer (Tint I32 Unsigned noattr) noattr) (Tcons threadInf Tnil)) Tvoid
                            {|
                              cc_vararg := false;
                              cc_unproto := false;
                              cc_structret := false |}).

Notation isptrTy := (Tfunction (Tcons (Tint I32 Unsigned noattr) Tnil) (Tint IBool Unsigned noattr)
                               {|
                                 cc_vararg := false;
                                 cc_unproto := false;
                                 cc_structret := false |}).






Notation val := uintTy. (* NOTE: in Clight, SIZEOF_PTR == SIZEOF_INT *)
Notation uval := uintTy.

Notation valPtr := (Tpointer val
                            {| attr_volatile := false; attr_alignas := None |}).

Notation boolTy := (Tint IBool Unsigned noattr).

Notation "'var' x" := (Etempvar x val) (at level 20).
Notation "'ptrVar' x" := (Etempvar x valPtr) (at level 20).

Notation "'bvar' x" := (Etempvar x boolTy) (at level 20).
Notation "'funVar' x" := (Evar x funTy) (at level 20).

Notation allocPtr := (Etempvar allocIdent valPtr).
Notation limitPtr := (Etempvar limitIdent valPtr).
Notation args := (Etempvar argsIdent valPtr).
Notation gc := (Evar gcIdent gcTy).
Notation ptr := (Evar isptrIdent isptrTy).



(* changed tinf to be tempvar and have type Tstruct rather than Tptr Tstruct *)
Notation tinf := (Etempvar tinfIdent threadInf).
Notation tinfd := (Ederef tinf threadStructInf).

Notation heapInf := (Tstruct heapInfIdent noattr).

Definition add (a b : expr) := Ebinop Oadd a b valPtr.
Notation " a '+'' b " := (add a b) (at level 30).

Definition sub (a b: expr) := Ebinop Osub a b valPtr.
Notation " a '-'' b " := (sub a b) (at level 30).

Definition int_eq (a b : expr) := Ebinop Oeq a b type_bool.
Notation " a '='' b " := (int_eq a b) (at level 35).

Definition not (a : expr) := Eunop Onotbool a type_bool.
Notation "'!' a " := (not a) (at level 40).

Notation seq := Ssequence.

Notation " p ';' q " := (seq p q)
                         (at level 100, format " p ';' '//' q ").

Notation " a '::=' b " := (Sset a b) (at level 50).
Notation " a ':::=' b " := (Sassign a b) (at level 50).

Notation "'*' p " := (Ederef p val) (at level 40).

Notation "'&' p " := (Eaddrof p valPtr) (at level 40).

Definition c_int' n t := Econst_int (Int.repr n%Z) t.

Notation c_int := c_int'.

Notation "'while(' a ')' '{' b '}'" :=
  (Swhile a b) (at level 60).

Notation "'call' f " := (Scall None f (tinf :: nil)) (at level 35).

Notation "'[' t ']' e " := (Ecast e t) (at level 34).

Notation "'Field(' t ',' n ')'" :=
  ( *(add ([valPtr] t) (c_int n%Z intTy))) (at level 36). (* what is the type of int being added? *)

Notation "'args[' n ']'" :=
  ( *(add args (c_int n%Z val))) (at level 36).



  (* Any valid mem is disjoint  the global_env *)
  Axiom disjoint_mem: forall m:mem, ~ exists b i z T v v' , (Mem.load T m b z = Some v /\ Genv.find_funct (globalenv p) (Vptr b i) = Some v').
Print Genv.
Print globdef.

 Inductive header_of_rep: cRep -> Z -> Prop :=
 | header_enum: forall t, header_of_rep (enum t) (Z.of_N ((N.shiftl t 1) + 1))
 | header_boxed: forall t a, header_of_rep (boxed t a) (Z.of_N ((N.shiftl a 10) + t)).
  
 
Inductive repr_asgn_fun': list positive -> list N -> statement -> Prop :=
| repr_asgn_nil: repr_asgn_fun' nil nil (Efield tinfd allocIdent valPtr  :::= allocPtr)
| repr_asgn_cons: forall y ys i inf s, repr_asgn_fun' ys inf s ->
                 repr_asgn_fun' (y::ys) (i::inf) (args[ Z.of_N i ] :::= (var y); s).

Inductive repr_asgn_fun: list positive -> list N -> statement -> Prop :=
  |repr_asgn_wrap: forall ys inf s, repr_asgn_fun' ys inf s ->
                   repr_asgn_fun ys inf (argsIdent ::= Efield tinfd argsIdent (Tarray uintTy maxArgs noattr);s).



(* like fromN but for Z, should move to list_util and make a generic one *)
Fixpoint fromZ (z:Z) (m:nat): list Z :=
  match m with
  | 0 => nil
  | S m' => z :: (fromZ (Z.succ z) m')
  end.

Fixpoint fromInt (i:int) (m:nat): list int :=
  match m with
  | 0 => nil
  | S m' => i :: (fromInt (Int.add i Int.one) m')
  end.


Theorem fromN_Some: forall x n z l ,
 nthN (fromN l z) n = Some x ->
 x = N.add l n.
Proof.  
  induction n using N.peano_rect; intros; simpl in H.
  - destruct z. simpl in H. inv H.
    simpl in H. inv H. 
    rewrite N.add_0_r. reflexivity.
  - destruct z. simpl in H. inv H.
    simpl in H. (destruct (N.succ n) eqn:Sn). apply N.neq_succ_0 in Sn.  inv Sn.
    assert (n = (N.sub (N.pos p0)  1)).
    rewrite <- Sn. rewrite <- N.pred_sub.
    symmetry. apply N.pred_succ.
    rewrite <- H0 in H.
    apply IHn in H. rewrite <- Sn.
    rewrite N.add_succ_l in H.
    rewrite N.add_succ_r. auto.
Qed. 
    


Definition Forall_in_mem_block {A} : (A -> (block *  int) -> Prop) -> list A -> (block * int) -> int -> Prop :=
  fun P ls loc z =>
    let (b, z0) := loc in
    let ids := fromN 0%N  (length ls) in 
    Forall2 (fun a i => P a (b, Int.add z0 (Int.mul (Int.repr (Z.of_N i)) z))) ls ids.


Theorem Forall_in_mem_block_nthN :
  forall {A P vs b i z v n},
     Forall_in_mem_block P vs  (b, i) z -> 
     @nthN A vs n = Some v ->
     P v (b, Int.add i (Int.mul (Int.repr (Z.of_N n)) z)).
Proof.
  intros. unfold Forall_in_mem_block in H.
  assert (Hf2 := Forall2_nthN _ _ _ _ _ H H0).
  destruct Hf2. destruct H1.
  apply fromN_Some in H1. simpl in H1. subst; assumption.
Qed.  

Inductive Forall_statements_in_seq' {A}: (BinNums.Z  -> A -> statement -> Prop) ->  list A -> statement -> BinNums.Z -> Prop :=
| Fsis_last: forall (R: (BinNums.Z  -> A -> statement -> Prop)) n v s, R n v s -> Forall_statements_in_seq' R [v] s n
| Fsis_cons: forall R v vs s s' n, Forall_statements_in_seq' R vs s' (Z.succ n) ->
                                   R n v s ->  Forall_statements_in_seq' R (v::vs) (s; s') n.

  

(* This is true for R, vs and S iff forall i, R i (nth vs) (nth s)
   > list cannot be empty (o.w. no statement)
   > nth on statement is taken as nth on a list of sequenced statement (;) *)
Definition Forall_statements_in_seq {A}: (BinNums.Z  -> A -> statement -> Prop) ->  list A -> statement -> Prop :=
  fun P vs s =>  Forall_statements_in_seq' P vs s (0%Z).


Inductive var_or_funvar : positive -> expr -> Prop :=
| F_VoF : forall x, 
    (exists def, List.In (x, def) (prog_defs p) ) ->
                var_or_funvar x (funVar x)
| V_VoF : forall x,
    (~ exists def, List.In (x, def) (prog_defs p)) ->
       var_or_funvar x (var x).
    

Inductive is_nth_projection_of_x : positive -> Z -> positive -> statement -> Prop :=
  Make_nth_proj: forall x  n v e,
                          var_or_funvar v  e ->
                          is_nth_projection_of_x x n v (Field(var x, n) :::=  e).


Definition repr_unboxed_L7: N -> Z -> Prop :=
 fun t => fun h => h =  (Z.of_N ((N.shiftl t 1) + 1)).


Definition boxed_header: N -> N -> Z -> Prop :=
  fun t => fun a =>  fun h => h = (Z.of_N ((N.shiftl a 10) + t)).



Inductive repr_asgn_constr: positive -> cTag -> list positive -> statement -> Prop :=
| Rconstr_ass_boxed: forall x (t:cTag) vs s a n h,
    (* boxed x *)   
    M.get t rep_env = Some (boxed n a) ->
    boxed_header n a h -> 
    Forall_statements_in_seq (is_nth_projection_of_x x) vs s -> 
    repr_asgn_constr x t vs (x ::= [val] (allocPtr +' (c_int Z.one val));
                                     allocIdent ::= allocPtr +'
                                           (c_int (Z.of_N (a + 1)) val); Field(var x, -1) :::= c_int h val;  s)
| Rconstr_ass_enum: forall x t n h,
    (* unboxed x *)
    M.get t rep_env  = Some (enum n) ->
    repr_unboxed_L7 n h  ->
    repr_asgn_constr x t nil (x ::= c_int h val).


Inductive repr_switch_L6_L7: positive -> labeled_statements -> labeled_statements -> statement -> Prop :=
| Mk_switch: forall x ls ls',
    repr_switch_L6_L7 x ls ls'
                      (isPtr isptrIdent caseIdent x;
                         Sifthenelse
                           (var caseIdent)
                           (Sswitch (Ebinop Oand (Field(var x, -1)) (Econst_int (Int.repr 255) val) val) ls)
                           (
                             Sswitch (Ebinop Oshr (var x) (Econst_int (Int.repr 1) val) val)
                                     ls')).
About LScons.



Print state.
(* relate a L6.exp -| cEnv, fEnv to a series of statements in a clight program (passed as parameter) -- syntactic relation that shows the right instructions have been generated for functions body. There should not be function definitions (Efun), or primitive operations (they are not supported by our backend) in this 
TODO: maybe this should be related to a state instead? 
*)
Inductive repr_expr_L6_L7: L6.cps.exp -> statement -> Prop :=
| Rconstr_e:
    forall x t vs  s s' e, 
    repr_asgn_constr x t vs s -> 
    repr_expr_L6_L7 e  s' ->
    repr_expr_L6_L7 (Econstr x t vs e)  (s; s')    
| Rproj_e: forall x t n v e  s,
    repr_expr_L6_L7 e  s ->
    repr_expr_L6_L7 (Eproj x t n v e)  (x ::= Field(var v, Z.of_N n) ; s)
| R_app_e: forall f inf ys t s,
    (* 1 - assign vs to the right args acording to fenv(f)*)
    M.get f fenv = Some inf ->
    repr_asgn_fun ys (snd inf) s -> 
    (* 2 - call f *)
    repr_expr_L6_L7 (Eapp f t ys)  (s; call ([pfunTy]funVar f))

| R_halt_e: forall v ,
    (* halt v <-> end with v in args[1] *)
    repr_expr_L6_L7 (Ehalt v)  (args[Z.of_nat 1 ] :::= (var v) ; Sreturn None)
| Rcase_e: forall v cl ls ls' s ,
    (* 1 - branches matches the lists of two lists of labeled statements *)
    repr_branches_L6_L7 cl ls ls' -> 
    (* 2 - switch-header matches  *)
    repr_switch_L6_L7 v ls ls' s ->
    repr_expr_L6_L7  (Ecase v cl)  s
                     (* default case for last boxed and unboxed constructor *)
with repr_branches_L6_L7: list (cTag * exp) -> labeled_statements -> labeled_statements -> Prop :=
     | Rempty_br : repr_branches_L6_L7 nil LSnil LSnil
     | Runboxed_default_br: forall t e cl ls n s, repr_branches_L6_L7 cl ls LSnil ->
                            M.get t rep_env  = Some (enum n) ->
                            repr_branches_L6_L7 ((t, e) ::cl) ls (LScons None s LSnil)
     | Runboxed_br: forall cl ls lsa' lsb' lsc' t n tag e s, repr_branches_L6_L7 cl ls (LScons lsa' lsb' lsc') ->
                                                repr_expr_L6_L7 e s ->
                                                M.get t rep_env  = Some (enum n) ->
                                                repr_unboxed_L7 n tag ->
                                                repr_branches_L6_L7 ((t, e) ::cl) ls (LScons (Some (Z.shiftr tag 1)) (Ssequence s Sbreak) (LScons lsa' lsb' lsc'))
     | Rboxed_default_br : forall cl  ls' t a n e s, repr_branches_L6_L7 cl LSnil ls' ->
                                           repr_expr_L6_L7 e s ->
                                           M.get t rep_env = Some (boxed n a) ->
                                           repr_branches_L6_L7 ((t, e)::cl) (LScons None s  LSnil) ls'
     | Rboxed_br : forall cl lsa lsb lsc ls' t a n tag e s, repr_branches_L6_L7 cl (LScons lsa lsb lsc) ls' ->
                                           repr_expr_L6_L7 e s ->
                                           M.get t rep_env = Some (boxed n a) ->
                                           boxed_header n a tag ->
                                           repr_branches_L6_L7 ((t, e)::cl) (LScons (Some (Z.land tag 255)) (Ssequence s Sbreak)  (LScons lsa lsb lsc)) ls'.

                    



Definition gc_vars := ((allocIdent, valPtr)::(limitIdent, valPtr)::(argsIdent, valPtr)::(caseIdent, val) ::nil).

Definition gc_set := (allocIdent ::= Efield tinfd allocIdent valPtr ;
                                                    limitIdent ::= Efield tinfd limitIdent valPtr ;
                                                    argsIdent ::= Efield tinfd argsIdent (Tarray uintTy maxArgs noattr)).


Definition gc_test (gcArrIdent:positive) (l:N) := (reserve allocIdent limitIdent gcIdent threadInfIdent tinfIdent gcArrIdent
                                                            (Z.of_N (l + 2))).

Inductive right_param_asgn: list positive -> list N -> statement -> Prop :=
| asgn_nil: right_param_asgn nil nil Sskip
| asgn_cons: forall v vs n ns s,  right_param_asgn vs ns s -> right_param_asgn (v::vs) (n::ns) ((v ::=args[Z.of_N n]);s).


(* IMPORTANT: this is deprecated, use repr_val_L_L6_L7 instead *)
 (* relate a  L6.val -| cEnv, fEnv to an address in a Clight memory  *)
 (* not sure the int and the enum case will ever happen *)
 Inductive repr_val_ptr_L6_L7: L6.cps.val -> mem -> (block *  int) ->   Prop :=

| RPint_v : forall n m b  h i,
    Mem.load Mint32 m b (Int.unsigned i) = Some (Vint h) ->
    repr_unboxed_L7 (Z.to_N n) (Int.unsigned h) ->
    repr_val_ptr_L6_L7 (cps.Vint  n) m (b, i)
| RPconstr_enum_v: forall t n m b i h,
    M.get t rep_env = Some (enum n) ->
    Mem.load Mint32 m b (Int.unsigned i) = Some (Vint h) ->
    repr_unboxed_L7 n (Int.unsigned h) ->
    repr_val_ptr_L6_L7 (cps.Vconstr t nil) m (b, i)
| RPconstr_boxed_v :
    forall t vs m b i h a n,
      M.get t rep_env = Some (boxed n a) ->
      (* 1) well-formedness of the header block *)
      Mem.load Mint32 m b (Int.unsigned (Int.sub i Int.one)) = Some (Vint h) ->
      boxed_header n a  (Int.unsigned h) ->
      (* 2) all the fields are also well-represented *)
      Forall_in_mem_block (fun v loc  =>
                             let (b, i) := loc in 
                             exists v7, Mem.load Mint32 m b (Int.unsigned  i) = Some v7  /\ 
                             repr_val_L6_L7 v m v7) vs (b, i) (Int.repr (sizeof (M.empty composite) uintTy)) ->      
    repr_val_ptr_L6_L7 (cps.Vconstr t vs) m (b, i)
| RPfun_v :
    forall  vars fds f m b i  F t vs e asgn body l locs finfo,
      find_def f fds = Some (t, vs, e) ->
      M.get t fenv = Some (l, locs) ->
      M.get f finfo_env = Some finfo -> (* TODO: check this *)
      (* b points to an internal function in the heap [and i is 0] *)
      Genv.find_funct (globalenv p) (Vptr b i) = Some (Internal F) ->
      (* F should have the shape that we expect for functions generated by our compiler, 
       > see translate_fundefs i.e.
        - returns a Tvoid *)
      fn_return F = Tvoid ->
      (*
       - calling convention?  
        - only param is the threadinfo (tinfIdent of type threadInf) *)
       fn_params F = ((tinfIdent, threadInf)::nil) ->
      (*
        - all the vars match + the 3 gc vars *)       
       fn_vars F = List.app vars gc_vars ->
       Forall2 (fun x xt =>  xt = (x, val))  vs vars  ->
       (* - no temps *)
       fn_temps F = nil ->
       (*
        - function header: threadInfo, gc check, load parameters,  then body equivalent to e (related according to repr_exp_L6_L7)
        *)
              fn_body F = Ssequence gc_set (Ssequence (gc_test finfo l)
                                               (Ssequence asgn body)) ->              
       right_param_asgn vs locs asgn ->
       repr_expr_L6_L7 e body ->
    repr_val_ptr_L6_L7 (cps.Vfun (M.empty cps.val) fds f) m (b, i)
(* like repr_val but not defered (i.e. positive is in tempval 
  if local_env is really holding blocks to lookup in memory, then should rework this *)
with repr_val_L6_L7:  L6.cps.val -> mem -> Values.val -> Prop :=
| Rint_v: forall z r m,
    repr_unboxed_L7 (Z.to_N z) (Int.unsigned r) ->
    repr_val_L6_L7 (L6.cps.Vint z) m (Vint r)
| Rconstr_unboxed_v:
    forall t arr n m,
      M.get t rep_env = Some (enum arr) ->
      repr_unboxed_L7 arr (Int.unsigned n) ->
      repr_val_L6_L7 (L6.cps.Vconstr t nil) m (Vint n)
| Rconstr_boxed_v: forall t vs arr a b i m,
    (* t is a boxed constructor, n ends with 0 and represents 
      a pointer to repr_val_ptr of (t, vs)  *)
    M.get t rep_env = Some (boxed arr a) ->
    repr_val_ptr_L6_L7 (L6.cps.Vconstr t vs) m (b, i) ->
    (* todo: this might actually be a Vint that needs to be interpreted as a pointer *)
    repr_val_L6_L7 (L6.cps.Vconstr t vs) m (Vptr b i)
| Rfunction_v: forall fds f m b i, 
    repr_val_ptr_L6_L7 (cps.Vfun (M.empty cps.val) fds f) m (b, i) ->
    repr_val_L6_L7 (cps.Vfun (M.empty cps.val) fds f) m (Vptr b i)
.



Definition locProp := block -> Z -> Prop.



Inductive repr_val_L_L6_L7:  L6.cps.val -> mem -> locProp -> Values.val -> Prop :=
| RSint_v: forall L z r m,
    repr_unboxed_L7 (Z.to_N z) (Int.unsigned r) ->
    repr_val_L_L6_L7 (L6.cps.Vint z) m L (Vint r)
| RSconstr_unboxed_v:
    forall t arr n m L,
      M.get t rep_env = Some (enum arr) ->
      repr_unboxed_L7 arr (Int.unsigned n) ->
      repr_val_L_L6_L7 (L6.cps.Vconstr t nil) m L (Vint n)
| RSconstr_boxed_v: forall (L:block -> Z -> Prop) t vs arr a b i m h,
    (* t is a boxed constructor, n ends with 0 and represents 
      a pointer to repr_val_ptr of (t, vs)  *)
    M.get t rep_env = Some (boxed arr a) ->
    (forall j : Z, (Int.unsigned (Int.sub i (Int.repr int_size)) <= j <
   Int.unsigned (Int.sub i (Int.repr int_size)) + size_chunk Mint32)%Z  -> L b j%Z) ->
    (* 1) well-formedness of the header block *)

    Mem.load Mint32 m b (Int.unsigned (Int.sub i (Int.repr int_size))) = Some (Vint h) ->
    boxed_header a arr  (Int.unsigned h) ->
    (* 2) all the fields are also well-represented *)
    repr_val_ptr_list_L_L6_L7 vs m L b i ->
    repr_val_L_L6_L7 (L6.cps.Vconstr t vs) m L (Vptr b i)
| RSfunction_v: 
    forall (L:block -> Z -> Prop)  vars fds f m b i  F t vs e asgn body l locs finfo,
      find_def f fds = Some (t, vs, e) ->
      M.get t fenv = Some (l, locs) ->
      M.get f finfo_env = Some finfo -> (* TODO: check this *)
      (* b points to an internal function in the heap [and i is 0] *)
      Genv.find_funct (globalenv p) (Vptr b i) = Some (Internal F) ->
      (* F should have the shape that we expect for functions generated by our compiler, 
       > see translate_fundefs i.e.
        - returns a Tvoid *)
      fn_return F = Tvoid ->
      (*
       - calling convention?  
        - only param is the threadinfo (tinfIdent of type threadInf) *)
      fn_params F = ((tinfIdent, threadInf)::nil) ->
       (*
        - all the vars match + the 3 gc vars *)       
       fn_vars F = List.app vars gc_vars ->
       Forall2 (fun x xt =>  xt = (x, val))  vs vars  ->
       (* - no temps *)
       fn_temps F = nil ->
       (*
        - function header: threadInfo, gc check, load parameters,  then body equivalent to e (related according to repr_exp_L6_L7)
        *)
       fn_body F = Ssequence gc_set (Ssequence (gc_test finfo l)
                                                      (Ssequence asgn body)) ->              
              right_param_asgn vs locs asgn ->
       repr_expr_L6_L7 e body ->
    repr_val_L_L6_L7 (cps.Vfun (M.empty cps.val) fds f) m L (Vptr b i) 
with repr_val_ptr_list_L_L6_L7: (list L6.cps.val) -> mem -> locProp -> block -> int -> Prop := 
     | RSnil_l:
         forall m L b i,
           repr_val_ptr_list_L_L6_L7 nil m L b i
     | RScons_l:
         forall v vs m (L:block -> Z -> Prop) b i v7,
           (forall j : Z, ((Int.unsigned i) <= j < (Int.unsigned i) + int_size)%Z -> L b j) ->
           Mem.load Mint32 m b (Int.unsigned  i) = Some v7 ->
           repr_val_L_L6_L7 v m L v7 -> 
           repr_val_ptr_list_L_L6_L7 vs m L b (Int.add i (Int.repr int_size)) ->
           repr_val_ptr_list_L_L6_L7 (v::vs) m L b i.

Scheme repr_val_ind' := Minimality for repr_val_L_L6_L7 Sort Prop
  with repr_val_list_ind' := Minimality for repr_val_ptr_list_L_L6_L7 Sort Prop.
 (* Combined Scheme repr_val_L_L6_L7_mutind from repr_val_L_L6_L7_ind, repr_val_ptr_list_L_L6_L7_ind. *)

Theorem nthN_pos_pred: 
  forall {A} (a:A) vs v6 p0,
  nthN (a :: vs) (N.pos p0) = Some v6 ->
  nthN vs (N.pred (N.pos p0)) = Some v6.
Proof.
  intros. destruct p0; auto.
Qed.


Theorem Z_mul_4:
  forall p,
   Z.pos p~0~0 = (4 * Z.pos p)%Z.
Proof.
  intro.
  replace ((xO (xO p0))) with (Zpower.shift 2%Z p0) by reflexivity.
  rewrite Zpower.shift_equiv; auto. omega.
Qed.


Theorem repr_val_ptr_list_L_nth:
  forall {m L  v6 vs n b i},
 repr_val_ptr_list_L_L6_L7 vs m L b i -> 
 nthN vs n = Some v6 ->
 exists v7, Mem.load Mint32 m b (Int.unsigned (Int.add i (Int.mul (Int.repr (Z.of_N n)) (Int.repr int_size))))  = Some v7 /\
 repr_val_L_L6_L7 v6 m L v7.
Proof.  
  induction vs; intros. inversion H0.
  destruct n.
  - simpl. inv H0.
    inv H.
    rewrite Int.add_zero. 
    exists v7; auto.
  - simpl.
    inv H.
    apply nthN_pos_pred in H0.
    specialize (IHvs _ _ _ H10 H0).
    destruct IHvs. destruct H.
    exists x; split; auto.
    replace (Int.unsigned
           (Int.add (Int.add i (Int.repr int_size))
              (Int.mul (Int.repr (Z.of_N (N.pred (N.pos p0))))
                       (Int.repr int_size)))) with
        (Int.unsigned
           (Int.add i (Int.mul (Int.repr (Z.pos p0)) (Int.repr int_size)))) in H.
    auto.
    rewrite Int.add_assoc.
    unfold Int.mul.
    unfold Int.add.
    erewrite  Int.eqm_samerepr.
    reflexivity.
    apply Int.eqm_add.
    apply Int.eqm_refl.
    eapply Int.eqm_trans.
    apply Int.eqm_unsigned_repr_l.
    Focus 2.    
    apply Int.eqm_unsigned_repr_r.
    apply Int.eqm_refl.
    rewrite Z.add_comm.
    admit.
Admitted.    


(* Theorem repr_val_ptr_list_L_nth:
  forall {m L  v6 vs n b i},
 repr_val_ptr_list_L_L6_L7 vs m L b i -> 
 nthN vs n = Some v6 ->
 exists v7, Mem.load Mint32 m b (Int.unsigned (Int.add i  (Int.repr (int_size * (Z.of_N n))%Z)))  = Some v7 /\
 repr_val_L_L6_L7 v6 m L v7.
Proof.
  induction vs; intros. inversion H0.
  destruct n.
  - simpl. inv H0.
    inv H.
    rewrite Int.add_zero. 
    exists v7; auto.
  - simpl.
    inv H.
    apply nthN_pos_pred in H0.
    specialize (IHvs _ _ _ H10 H0).
    destruct IHvs. destruct H.
    exists x; split; auto.
    replace (Int.add (Int.add i (Int.repr int_size))
                     (Int.repr (int_size * Z.of_N (N.pred (N.pos p0))))) with
        (Int.add i (Int.repr (Z.pos p0~0~0))) in H.
    auto.
    rewrite Int.add_assoc.
    replace (Int.repr (Z.pos p0~0~0)) with
                (Int.add (Int.repr int_size)
       (Int.repr (int_size * Z.of_N (N.pred (N.pos p0))))). 
    auto.
    rewrite Int.add_unsigned.
    apply Int.eqm_samerepr.
    rewrite Int.unsigned_repr.
    rewrite Z_mul_4.
    admit.
    unfold int_size. simpl. unfold Int.max_unsigned. simpl. omega. 
Admitted. *)
  
Theorem repr_val_L_unchanged:
  forall v6 m L v7, 
  repr_val_L_L6_L7 v6 m L v7 ->
  forall m', Mem.unchanged_on L m m' ->
  repr_val_L_L6_L7 v6 m' L v7.
Proof.
  apply (repr_val_ind' (fun v m L v7 => forall m', Mem.unchanged_on L m m' -> repr_val_L_L6_L7 v m' L v7)
                       (fun vs m L b i => forall m', Mem.unchanged_on L m m' -> repr_val_ptr_list_L_L6_L7 vs m' L b i)); intros; try (now econstructor; eauto).
  - specialize (H4 _ H5). 
    econstructor; eauto.
    eapply Mem.load_unchanged_on; eauto.  
  - econstructor; eauto.
    eapply Mem.load_unchanged_on; eauto.
Qed.

      
(* 
Returns True if the pointer Vptr q_b q_ofs is reachable by crawling v7 
Assumes correct memory layout (i.e. repr_val_L6_L7 v6 m v7)
 *)
Fixpoint reachable_val_L7 (v6:L6.cps.val) (m:mem) (v7:Values.val) (q_b:block) (q_ofs:int): Prop :=
  match v6, v7 with
  | L6.cps.Vint z, Vint r => False
  | L6.cps.Vconstr t vs, Vptr b i =>
    (fst (List.fold_left (fun curr v =>
                            let '(p, (p_b, p_ofs)) := curr in
                            (match Val.cmpu_bool (Mem.valid_pointer m) Ceq (Vptr p_b p_ofs) (Vptr q_b q_ofs) with
                             | Some true => (True, (p_b, (Int.add p_ofs (Int.repr (sizeof (M.empty composite) uintTy)))))
                             | _ => 
                               (match Mem.load Mint32 m p_b (Int.unsigned p_ofs) with
                                | Some v7 => 
                                  (reachable_val_L7 v m v7 q_b q_ofs, (p_b, (Int.add p_ofs (Int.repr (sizeof (M.empty composite) uintTy)))))
                                | _ => curr
                                end)
                             end))                        
                        vs (False, (b,i))))
  | (L6.cps.Vfun rho fds f), Vptr b i => False
  | _, _ => False
  end.


                                                                       

Theorem repr_val_load_result: forall v6 m v7,
    repr_val_L6_L7 v6 m (Val.load_result Mint32 v7)
                   <->
  repr_val_L6_L7 v6 m v7.
Proof.
  intros.
  destruct v7; split; intro H; inv H; simpl in *; econstructor; eauto.
Qed.  

Theorem repr_val_L_load_result: forall v6 m v7 L,
    repr_val_L_L6_L7 v6 m L (Val.load_result Mint32 v7)
                   <->
  repr_val_L_L6_L7 v6 m L v7.
Proof.
  intros.
  destruct v7; split; intro H; inv H; simpl in *; econstructor; eauto.
Qed.  


(* the memory blocks in the sequence (b, i), (b, i+off) ... (b, i+((n-1)*off)) are pairwise related with the sequence (b', i'), (b', i'+off) ... (b', i'+(n-1*off))  *)
Inductive For_N_blocks (P:(block * int) -> (block * int) -> Prop) (loc:block * int) (loc':block * int) (off: int) :  nat -> Prop :=
| FNb_O: For_N_blocks P loc loc' off 0
| FNb_S: forall n,
    P (fst loc, Int.add (snd loc) (Int.mul off (Int.repr (Z.of_nat n)))) (fst loc', Int.add (snd loc') (Int.mul off (Int.repr (Z.of_nat n)))) ->
    For_N_blocks P  loc loc' off n -> 
    For_N_blocks P loc  loc' off (S n). 


(* Related (deep copy) vals that may have been moved by the GC, in such way that they can be used in place of the other in repr_val_ptr_L6_L7 
 *)
Inductive related_boxed_L7: mem -> (block *  int) -> mem -> (block *  int) -> Prop :=
| SV_constr_boxed :
    forall m m' b i b' i' h h' n a,
    (* same tag *)
      Mem.load Mint32 m b (Int.unsigned (Int.sub i Int.one)) = Some (Vint h) ->
      boxed_header n a  (Int.unsigned h) ->
      Mem.load Mint32 m' b' (Int.unsigned (Int.sub i' Int.one)) = Some (Vint h') ->
      boxed_header n a  (Int.unsigned h') ->      
      (* each of the a (arrity) fields are either same int shifted+1, same function or pointers (0-ended) related according to same_boxed *)
      For_N_blocks (fun loc loc' => related_boxed_or_same_val_L7 m loc m' loc') (b,i) (b', i') (Int.repr (sizeof (M.empty composite) uintTy)) (N.to_nat a) -> 
      related_boxed_L7 m (b,i) m' (b', i')
with related_boxed_or_same_val_L7: mem -> (block *  int) -> mem -> (block *  int) -> Prop :=
     | RBSI_fun :
         (* same fun *)
         forall m m' b i b' i' F,
           b = b' /\ i = i' ->
           Genv.find_funct (globalenv p) (Vptr b i) = Some (Internal F) ->
           related_boxed_or_same_val_L7 m (b,i) m' (b', i')                                   
     | RBSI_int :
         (* same int/unboxed constructor *)
         forall m b i n m' b' i' h,
           Mem.load Mint32 m b (Int.unsigned i) = Some (Vint h) ->
           Mem.load Mint32 m' b' (Int.unsigned i') = Some (Vint h) ->
           repr_unboxed_L7 n (Int.unsigned h) ->
           related_boxed_or_same_val_L7 m (b,i) m' (b', i')
     | RBSI_pointer:
         forall m b i  m' b' i' b1 i1 b2 i2,
         Mem.load Mint32 m b (Int.unsigned i) = Some (Vptr b1 i1) ->
         Mem.load Mint32 m' b' (Int.unsigned i') = Some (Vptr b2 i2) ->
         (* TODO: may be Vint h and h' that needs to be interpreted as pointers inside m *)
         (* TODO: make sure that *)
         related_boxed_L7 m (b1, i1) m' (b2,i2) ->
         related_boxed_or_same_val_L7 m (b,i) m' (b', i').


(* deprecated
Theorem repr_same_boxed_L6_L7 :
  forall v, (forall m m' b i b' i',
                related_boxed_L7 m (b,i) m' (b', i') ->
                repr_val_ptr_L6_L7 v m (b, i) -> 
                repr_val_ptr_L6_L7 v m' (b', i'))
with repr_same_val_L6_L7: forall v, (forall m m' b i b' i',
                related_boxed_or_same_val_L7 m (b,i) m' (b', i') ->
                repr_val_ptr_L6_L7 v m (b, i) -> 
                repr_val_ptr_L6_L7 v m' (b', i'))
. 
Proof.  
  {
    induction v; intros; inversion H; subst.
    -  admit.
    - (* Impossible because b is in m but H0 *) admit.
    - inv H0. admit.
  }    
  {
    induction v; intros.
    - admit.
    - admit.
    - admit.
  }
Admitted. *)
  
(* this is just a sketch, ignore for now *)
Theorem repr_same_boxed_L_L6_L7 :
  forall v m  L v7 ,
    repr_val_L_L6_L7 v m L v7 ->
    forall  m' b i b' i', v7 = (Vptr b i) ->
                related_boxed_L7 m (b,i) m' (b', i') ->
                exists L', repr_val_L_L6_L7 v m' L' (Vptr b' i')
.
Proof.  
  apply (repr_val_ind' (fun v m L v7 =>  forall  m' b i b' i', v7 = (Vptr b i) ->
                                                               related_boxed_L7 m (b,i) m' (b', i') ->
                                                               exists L', repr_val_L_L6_L7 v m' L' (Vptr b' i'))
                       (fun vs m L b i => forall m' b' i', 
                            related_boxed_L7 m (b,i) m' (b', i') ->
                            exists L', repr_val_ptr_list_L_L6_L7 vs m' L' b' i')); intros.
  - inv H0.
  - inv H1.
  - inv H5.
    admit.
  - inv H11.
    admit.
  - exists (fun b z => False). constructor.
  - admit.    
Admitted.
  



(* this is false, missing the boxed case which is off-shifted 
Theorem repr_val_ptr_load :
  forall v6 m b i,
    repr_val_ptr_L6_L7 v6 m (b, i) ->
    (exists v7, Mem.load Mint32 m b (Int.unsigned i)  = Some v7 /\ repr_val_L6_L7 v6 m v7)
             \/ exists F, Genv.find_funct (globalenv p) (Vptr b i) = Some (Internal F). *)


(* TODO: write this to ensure that the GC nevers runs out of space in the middle of a function*)
Definition correct_alloc: exp -> int -> Prop := fun e i => i =  Int.repr (Z.of_nat (max_allocs e )).



(* see make_fundef_info, this is w.r.t. some fenv, another prop should assert the fenv is correct w.r.t. all functions *)
Inductive correct_fundef_info: positive -> fTag -> list positive -> exp -> ident -> Prop :=
  c_funinfo: forall f t vs e tag n l b finfo fi_0 fi_1 fi_rest,
    (* the tag for f points to a record r *)
    M.get f fenv =  Some (n, l) ->
    n = N.of_nat (length l) ->
    (* id points to an array in global memory *)
    Genv.find_symbol (globalenv p) tag = Some b ->
    Genv.find_var_info (globalenv p) b = Some finfo ->
    
    (* the record has the right information w.r.t. vs and r 
       fi[0] = alloc(e)
       fi[1] = number of roots
       |fi| = 2+fi[1] *)
    gvar_init finfo = ((Init_int32 fi_0)::(Init_int32 fi_1)::fi_rest) ->
    correct_alloc e fi_0 ->
    fi_1 = Int.repr (Z.of_N n) ->
    n = N.of_nat (length fi_rest) -> 
    correct_fundef_info f t vs e tag. 


(* P is true of every fundefs in a bundle *)
(* TODO: move this to cps_util *)
Inductive Forall_fundefs: (L6.cps.var -> fTag -> list L6.cps.var -> exp -> Prop) -> fundefs -> Prop :=
| Ff_cons : forall (P:(L6.cps.var -> fTag -> list L6.cps.var -> exp -> Prop)) f t vs e fds,
         P f t vs e -> 
         Forall_fundefs P fds ->
         Forall_fundefs P (Fcons f t vs e fds)         
| Ff_nil: forall P, Forall_fundefs P Fnil.


Theorem Forall_fundefs_In:
  forall P f t vs e fds,
  Forall_fundefs P fds ->
  fun_in_fundefs fds (f,t,vs,e) ->
  P f t vs e.
Proof.
  induction fds; intros.
  - inv H; inv H0; subst.
    + inv H; auto.
    +  apply IHfds; auto.
  - inv H0.
Qed.
(* END TODO move *)


(* 1) finfo_env has the correct finfo
   2) fenv is consistent with the info
   3) global env holds a correct L7 representation of the function *)
Definition correct_environments_for_function:
  genv -> fEnv -> M.t positive -> mem -> fundefs ->  L6.cps.var ->
  fTag -> list L6.cps.var -> exp ->  Prop
  := fun ge fenv finfo_env m fds f t vs e =>
       exists l locs finfo b, 
         (*1*)
         M.get f finfo_env = Some finfo /\
         correct_fundef_info f t vs e finfo /\
         (*2*)
         M.get t fenv = Some (l, locs) /\
         l = N.of_nat (length vs) /\
         (* may want to check that locs are distinct and same as in finfo? *)
         (*3*)
         Genv.find_symbol (globalenv p) f = Some b /\
         repr_val_ptr_L6_L7 (cps.Vfun (M.empty cps.val) fds f) m (b, Int.zero).

(* relates the top level bundle of function fds to a map of fundef_info and a global environment with related functions *) 
Definition correct_environments_for_functions: fundefs -> genv -> fEnv -> M.t positive -> mem ->  Prop := fun fds ge fenv finfo_env m =>
                                                                                                            Forall_fundefs (correct_environments_for_function ge fenv finfo_env m fds) fds.

(* true if alloc, limit or args *)
Definition is_protected_loc lenv b ofs : Prop  :=
  M.get allocIdent lenv = Some (Vptr b ofs)
  \/
  M.get limitIdent lenv = Some (Vptr b ofs)
  \/
  (exists args_ofs i, M.get argsIdent lenv = Some (Vptr b args_ofs) /\
   Int.ltu i max_args = true /\
  Int.eq (Int.add args_ofs (Int.mul (Int.repr (sizeof (M.empty composite) uintTy)) i))  ofs = true ).

Definition is_protected_id id  : Prop :=
  id = allocIdent \/ id = limitIdent \/ id = argsIdent.


Definition protected_id_not_bound (rho:L6.eval.env) (e:exp) : Prop :=
  (forall x y v, M.get x rho = Some v ->
                 is_protected_id y ->
                 ~ (x = y \/ bound_var_val v y) )/\
  (forall y, is_protected_id y ->
             ~ bound_var e y).


Inductive empty_cont: cont -> Prop :=
| Kempty_stop: empty_cont Kstop
| Kempty_switch: forall k, empty_cont k ->
                           empty_cont (Kswitch k)
| Kempty_sbreak: forall k, empty_cont k ->
                           empty_cont (Kseq Sbreak k)
| Kempty_sskip: forall k, empty_cont k ->
                           empty_cont (Kseq Sskip k)
.
                                      
Definition protected_non_reachable_val_L7 v6 m v7 (lenv:temp_env) : Prop :=
      exists alloc_b alloc_ofs limit_b limit_ofs args_b args_ofs,
        M.get allocIdent lenv = Some (Vptr alloc_b alloc_ofs) /\
        ~reachable_val_L7 v6 m v7 alloc_b alloc_ofs /\
        M.get limitIdent lenv = Some (Vptr limit_b limit_ofs) /\
        ~reachable_val_L7 v6 m v7 limit_b limit_ofs /\
        M.get argsIdent lenv = Some (Vptr args_b args_ofs) /\
        (forall i,
            Int.ltu i max_args = true ->                   
            ~reachable_val_L7 v6 m v7 args_b (Int.add args_ofs (Int.mul (Int.repr (sizeof (M.empty composite) uintTy)) i))).



Definition protected_not_in_L (lenv:temp_env) (L:block -> Z -> Prop): Prop :=
  exists alloc_b alloc_ofs limit_b limit_ofs args_b args_ofs,
    M.get allocIdent lenv = Some (Vptr alloc_b alloc_ofs) /\
    (forall j : Z, ((Int.unsigned alloc_ofs) <= j <
                    Int.unsigned alloc_ofs + size_chunk Mint32)%Z  ->
                   ~ L alloc_b j) /\
    M.get limitIdent lenv = Some (Vptr limit_b limit_ofs) /\
        (forall j : Z, ((Int.unsigned limit_ofs) <= j <
                    Int.unsigned limit_ofs + size_chunk Mint32)%Z  ->
                   ~ L limit_b j) /\
          M.get argsIdent lenv = Some (Vptr args_b args_ofs) /\
          (forall z j: Z,
              (0 <= z < Int.unsigned max_args)%Z -> 
              ((Int.unsigned  (Int.add args_ofs (Int.mul (Int.repr int_size) (Int.repr z))))
               <= j <
               (Int.unsigned (Int.add args_ofs (Int.mul (Int.repr int_size) (Int.repr z)))) +  int_size)%Z ->

                       ~ L args_b j).


Theorem protected_not_in_L_set:
  forall lenv L x v,
  protected_not_in_L lenv L ->
  ~ is_protected_id x ->
  protected_not_in_L (M.set x v lenv) L.
Proof.
  intros.
  destruct H.
  destructAll.
  exists x0, x1, x2, x3, x4, x5.
  repeat split;auto.
  - destruct (var_dec allocIdent x).
    + exfalso; apply H0.
      unfold is_protected_id.
      auto.
    +  rewrite M.gso by auto. auto.
  - destruct (var_dec limitIdent x).
    + exfalso; apply H0.
      unfold is_protected_id.
      auto.
    +  rewrite M.gso by auto. auto.
  - destruct (var_dec argsIdent x).
    + exfalso; apply H0.
      unfold is_protected_id.
      auto.
    +  rewrite M.gso by auto. auto.
Qed.
       
(* relates a L6 evaluation environment to a Clight memory up to the free variables in e *)
(* If x is a free variable of e, then it might be in the generated code:
   1) a function (may want to handle this separately as they won't get moved by the GC) in the global environment, evaluates to a location related to f by repr_val_ptr_L6_L7
   2) a local variable in le related to (rho x) according to repr_val_L6_L7 -- this happens when e.g. x := proj m, or after function initialization

All the values are in a space L which is disjoint form protected space

Note that parameters are heap allocated, and at function entry "free variables" are held in args and related according to repr_val_ptr_L6_L7
 
Now also makes sure none of the protected portion are reachable by the v7

 *)

    Definition rel_mem_L6_L7: exp -> L6.eval.env -> mem -> temp_env -> Prop :=
      fun e rho m le =>
        exists L, protected_not_in_L le L /\
        forall x, occurs_free e x ->
                  exists v6, M.get x rho = Some v6 /\
                             exists v7, M.get x le = Some v7 /\ repr_val_L_L6_L7 v6 m L v7.

(*
Theorem rel_mem_update_protected:
  forall e rho m le b ofs v m',
    rel_mem_L6_L7 e rho m le ->
    Mem.store Mint32 m b ofs v = Some m' ->
    is_protected_loc le b (Int.repr ofs) -> 
    rel_mem_L6_L7 e rho m' le.  *)
    
 Fixpoint mem_of_state (s:state) : mem :=
  match s with
  | State f s k e le m => m
  | Callstate f vs k m => m
  | Returnstate x k m =>  m
  end.



(* [pure] step with no built-in, i.e. trace is always E0 *)
Definition traceless_step2:  genv -> state -> state -> Prop := fun ge s s' => step2 ge s nil s'. 

Definition m_tstep2 (ge:genv):=  clos_trans state (traceless_step2 ge).






End RELATION.



Section THEOREM.



  (* same as L6_to_Clight *)
  Variable (argsIdent : ident).
  Variable (allocIdent : ident).
  Variable (limitIdent : ident).
  Variable (gcIdent : ident).
  Variable (mainIdent : ident).
  Variable (bodyIdent : ident).
  Variable (threadInfIdent : ident).
  Variable (tinfIdent : ident).
  Variable (heapInfIdent : ident).
  Variable (numArgsIdent : ident).  
  Variable (isptrIdent: ident). (* ident for the isPtr external function *)
  Variable (caseIdent:ident).


(*
    Variable cenv:L6.cps.cEnv.
  Variable fenv:L6.cps.fEnv.
  Variable finfo_env: M.t positive. (* map from a function name to its type info *)
  Variable p:program.
  
  
  (* This should be a definition rather than a parameter, computed once and for all from cenv *)
  Variable rep_env: M.t cRep.
*)


  (* TODO: move this to cps_util *)
  Definition Forall_constructors_in_e (P: var -> cTag -> list var -> Prop) (e:exp) := 
    forall x t  ys e',
      subterm_e (Econstr x t ys e') e -> P x t ys.
      

  Definition Forall_projections_in_e (P: var -> cTag -> N -> var -> Prop) (e:exp) :=
    forall x t n v e',
      subterm_e (Eproj x t n v e') e -> P x t n v.
  
  (* Note: the fundefs in P is the whole bundle, not the rest of the list *)
  Definition Forall_functions_in_e (P: var -> fTag -> list var -> exp ->  fundefs -> Prop) (e:exp) :=
    forall fds e' f t xs e'',  subterm_e (Efun fds e') e ->
                               fun_in_fundefs fds (f, t, xs, e'') ->
                               P f t xs e'' fds.


  Theorem Forall_constructors_subterm:
    forall P e e' ,
    Forall_constructors_in_e P e ->
    subterm_e e' e ->
    Forall_constructors_in_e P e'. 
  Proof.
    intros. intro; intros.
    eapply H. eapply t_trans; eauto.
  Qed.

  
  (* END TODO move *)

  (* all constructors in the exp are applied to the right number of arguments *)
  Definition correct_cenv_of_exp: L6.cps.cEnv -> exp -> Prop :=
    fun cenv e =>
      Forall_constructors_in_e (fun x t ys =>
                                  match (M.get t cenv) with
                                  | Some (name, it, a, n) =>
                                    N.of_nat (length ys) = a
                                  | None => False
                                  end) e.
  
  Definition correct_ienv_of_cenv: L6.cps.cEnv -> iEnv -> Prop :=
    fun cenv ienv =>
      forall x, forall i n t name, M.get x cenv = Some (name, i, n, t) ->
                                   exists cl, M.get i ienv = Some cl /\ List.In (x, n) cl /\ ~ (exists n', List.In (x, n') cl).
  

  Inductive correct_crep (cenv:cEnv) (ienv:iEnv) : cTag -> cRep -> Prop :=
  | rep_enum :
      forall c name it n' n cl,
        M.get c cenv = Some (name, it, 0%N, n') ->
        M.get it ienv = Some cl ->
        getEnumOrdinal c cl = Some n ->
      correct_crep cenv ienv c (enum n)
  | rep_boxed:
      forall c name it a n' n cl,
        M.get c cenv = Some (name, it, (Npos a), n') ->
        M.get it ienv = Some cl ->
        getBoxedOrdinal c cl = Some n ->
      correct_crep cenv ienv c (boxed n (Npos a)).

  (* also need to go the other way around: if in crep, then in cenv*) 
  Definition correct_crep_of_env: L6.cps.cEnv -> iEnv -> M.t cRep -> Prop :=
    fun cenv ienv crep_env =>
      (forall c name it a n,
        M.get c cenv = Some (name, it, a, n) ->
        exists crep, M.get c crep_env = Some crep /\
                     correct_crep cenv ienv c crep) /\
      (forall c crep, M.get c crep_env = Some crep ->
                     correct_crep cenv ienv c crep).


  Definition correct_envs: cEnv -> iEnv -> M.t cRep -> exp -> Prop :=
    fun cenv ienv crep_env e =>
      correct_ienv_of_cenv cenv ienv /\
      correct_cenv_of_exp cenv e /\
      correct_crep_of_env cenv ienv crep_env. 

  (* 
   correct_tinfo alloc_id limit_id args_id alloc_max le m
  > alloc and limit are respectively valid and weak-valid pointers in memory, alloc is at least alloc_max before limit_id
  > args points to an array of size max_args in memory before alloc 

limit might be on the edge of current memory so weak_valid, alloc and args are pointing in mem. the int is the max number of blocks allocated by the function 
 

   *)



Definition correct_tinfo: positive -> positive -> positive -> int -> temp_env ->  mem -> Prop :=
  fun alloc_p limit_p args_p max lenv m =>
    exists alloc_b alloc_ofs limit_b limit_ofs args_b args_ofs,
      M.get alloc_p lenv = Some (Vptr alloc_b alloc_ofs) /\
      Mem.valid_pointer m alloc_b (Int.unsigned alloc_ofs) = true /\
      M.get limit_p lenv = Some (Vptr limit_b limit_ofs) /\
      Mem.weak_valid_pointer m limit_b (Int.unsigned limit_ofs) = true /\
      Val.cmpu_bool (Mem.weak_valid_pointer m) Cle (Vptr alloc_b (Int.add alloc_ofs max)) (Vptr limit_b  limit_ofs) = Some true /\
      M.get args_p lenv = Some (Vptr args_b args_ofs) /\
      Val.cmpu_bool (Mem.valid_pointer m) Clt (Vptr args_b args_ofs) (Vptr alloc_b alloc_ofs) = Some true /\
      (forall i, Int.ltu i max_args = true -> Mem.valid_access m Mint32 args_b (Int.unsigned (Int.add args_ofs (Int.mul (Int.repr (sizeof (M.empty composite) uintTy)) i))) Writable ).


(* given a program (which at top level is the certicoq translation of e... 
TODO: alloc is always fresh
TODO: add disjunct for basecase (Returnstate) 
TODO: additional constraints on the environment(s), top level statement, f k etc...
TODO: make rel_state_L6_L7 englobing expr and mem *)


Definition repr_expr_L6_L7_id := repr_expr_L6_L7 argsIdent allocIdent threadInfIdent tinfIdent
     isptrIdent caseIdent.


Definition rel_mem_L6_L7_id := rel_mem_L6_L7 argsIdent allocIdent limitIdent gcIdent threadInfIdent tinfIdent
   isptrIdent caseIdent.


Definition repr_val_L_L6_L7_id := repr_val_L_L6_L7 argsIdent allocIdent limitIdent gcIdent threadInfIdent tinfIdent isptrIdent caseIdent.


Definition protected_id_not_bound_id := protected_id_not_bound argsIdent allocIdent limitIdent.


(* ident[n] contains either a Vint representing an enum or an integer OR a pointer to a function or the boxed representation of v *)
Inductive nth_arg_rel_L6_L7 (fenv:fEnv) (finfo_env:M.t positive) (p:program) (rep_env: M.t cRep) : L6.eval.env -> positive -> temp_env -> mem -> Z -> Prop :=
| is_in_and_rel:
    forall lenv args_b args_ofs rho m n x L6v L7v L,
       protected_not_in_L argsIdent allocIdent limitIdent lenv L -> 
      (* get the value rho(x)*)
      M.get x rho = Some L6v -> 
      (* get Vargs pointer and load the value from it *)
      M.get argsIdent lenv = Some (Vptr args_b args_ofs) ->
      Mem.load Mint32 m args_b (Int.unsigned (Int.add args_ofs  (Int.mul
                   (Int.repr (sizeof (M.empty composite) uintTy))
                   (Int.repr n)))) = Some L7v ->
      (* relate both val *)
      repr_val_L_L6_L7_id fenv finfo_env p rep_env L6v m L L7v ->
          nth_arg_rel_L6_L7 fenv finfo_env p rep_env rho x lenv m n.





  
Theorem repr_L6_L7_are_related:
  forall cenv fenv finfo_env crep_env p  s rho f stm k e ienv lenv m max_alloc, 
    s = State f stm k empty_env lenv m ->
    correct_envs cenv ienv crep_env e ->
    protected_id_not_bound_id rho e -> 
    correct_tinfo allocIdent limitIdent argsIdent max_alloc lenv m ->
    repr_expr_L6_L7_id fenv p crep_env e stm ->
    rel_mem_L6_L7_id fenv finfo_env p crep_env e  rho m lenv ->
    (* if e is Halt,can step to a Returnstate where rho(v) is represented in args[1]  
       if e steps to e' then s can be stepped to some s' related to e' *)    
    (forall rho' e', L6.eval.step (M.empty _) cenv (rho, e) (rho', e') ->
     exists  f' stm' k' e' lenv' m', m_tstep2 (globalenv p) s (State f' stm' k' empty_env lenv' m') /\ repr_expr_L6_L7_id fenv p crep_env e' stm' /\ rel_mem_L6_L7_id fenv finfo_env p crep_env e' rho' m' lenv' /\ protected_id_not_bound_id rho' e')
    /\ 
    (forall v,  e = Ehalt v ->      exists m' k' lenv', m_tstep2 (globalenv p) s (Returnstate Vundef k' m') /\   nth_arg_rel_L6_L7 fenv finfo_env p crep_env rho v lenv' m' 1).
Proof.
  intros cenv fenv finfo_env crep_env p  s rho f stm k e ienv lenv m max_alloc H H0 Hidp H1 H2 H3. split. intros.   
  destruct e; inv H4; inv H2.
  
  - (* Econstr *)
    
    
    eexists. exists s', k, e'.  do 2 eexists. split.

    (* The new memory should be such that
    M.get lenv' x = Some v7 /\  repr_val_L6_L7 (Vconstr t vs) m' v7.  

    with lenv' = M.set x v7 lenv and 
          m' = 
*)
    
    eapply t_trans.
    apply t_step. constructor.
    admit.
    split. auto.
    split. admit.
    { destruct Hidp. split; intros.
      - intro. destruct (var_dec x v).
        + subst. rewrite M.gss in H4. inv H4.
          inv H7.
          * specialize (H2 _ H5). apply H2. constructor.
          * inv H4.
            assert (Hli := getlist_In_val _ _ _ _ H6 H13).
            destructAll.
            eapply H; eauto.
        + rewrite M.gso in H4; auto.
          eapply H; eauto.
      - intro.
        eapply H2; eauto.
    }        
  - (* Ecase *)    
    admit.
  - (* Eproj *)
    
    (* > representation in memory of the Vconstr *)
    assert (Hv0 : occurs_free (Eproj v c n v0 e') v0) by constructor. 
    destruct H3 as [L Hc]. destruct Hc as [Hp H3].
    apply H3 in Hv0. destruct Hv0 as [v6 Hv0]. destruct Hv0 as [Hv0rho Htemp]. rewrite H7 in Hv0rho. inv Hv0rho. destruct Htemp as [v7 Htemp]. destruct Htemp as [Hv0lenv Hv0repr].
    inversion Hv0repr; subst.
    (* impossible, if taking proj, then vs is not empty so c is boxed *) 
    { exfalso.
      unfold correct_envs in H0. destruct H0. destruct H0.
      unfold correct_crep_of_env in H2. destruct H2. apply H5 in H4. inv H4.
      inversion H14.
    }
    (* get the value on the nth of vs in memory *)

    
    assert (Hvn := repr_val_ptr_list_L_nth argsIdent allocIdent limitIdent gcIdent mainIdent bodyIdent  threadInfIdent tinfIdent heapInfIdent numArgsIdent isptrIdent caseIdent  cenv _ _ _ _ H13 H14).
    destruct Hvn as [v7 [Hv7_l Hv7_rep]]. 


    (* > done A *)

    do 7 eexists.
    eapply t_trans.
    apply t_step. constructor.
    eapply t_trans.
    apply t_step. constructor.
    {
      eapply eval_Elvalue.
      apply eval_Ederef. econstructor. econstructor. constructor. apply Hv0lenv.
      compute. reflexivity.
      constructor.
      simpl. unfold sem_add. simpl. reflexivity.
      simpl.
      eapply deref_loc_value. constructor.
      unfold Mem.loadv. 
      rewrite Int.mul_commut.
      apply Hv7_l.
      }
    constructor. constructor.
    split. eauto.
    split.
    exists L.
    split.
    {  (* nothing in rho (or in v6) can shadow protected *)
      apply protected_not_in_L_set.
      auto.
      intro.
      destruct Hidp as [Hidp1 Hidp2].
      apply Hidp2 with (y := v); auto.
    } 
    intro. intro. destruct (var_dec x v).
    * subst. exists v1. split. rewrite M.gss; auto.
      eexists; split. rewrite M.gss; auto.
      auto. 
    * assert (occurs_free (Eproj v c n v0 e') x).
      constructor; auto.
      apply H3 in H2.
      destruct H2 as [v6 [Hv6 [v7' [Hv7' Hv7'_rep]]]].
      exists v6. split. rewrite M.gso by auto. auto.
      exists v7'. split.  rewrite M.gso by auto. eauto.
      auto.
    * destruct Hidp as [Hidp1 Hidp2].
      {
        split; intros.
        - destruct (var_dec x v).
          + subst; rewrite M.gss in H. inv H.
            intro. inv H.
            * (* v = y *)
              eapply Hidp2; eauto. 
            * (* bound_var_val v2 y *)
              eapply Hidp1. apply H7. apply H2. right.
              econstructor. apply H9.
              eapply nthN_In; eauto.
          + rewrite M.gso in H by auto.
            eapply Hidp1; eauto. 
        - intro; eapply Hidp2.
          apply H. 
          apply Bound_Eproj2; auto.
      } 
  - (* Eapp *)
    admit.
  - (* Ehalt *)
    intros. subst.
    inv H2.
    (* find out what v looks like in memory *)
    assert (occurs_free (Ehalt v) v) by constructor.
    destruct H3 as [L [HL_pro Hmem]]. 
    apply Hmem in H.
    destruct H. destruct H. destruct H2. destruct H2.
    

    unfold correct_tinfo in H1.
    destructAll.    
    assert (Int.lt Int.one max_args = true).    unfold Int.lt.
    apply Coqlib.zlt_true. unfold max_args. rewrite Int.signed_repr.
    rewrite Int.signed_eq_unsigned.
    rewrite Int.unsigned_one. compute. reflexivity.
    unfold Int.max_signed;  unfold Int.half_modulus; unfold Int.modulus;  simpl.
    rewrite Int.unsigned_one.  omega.
    unfold Int.min_signed; unfold Int.max_signed;  unfold Int.half_modulus; unfold Int.modulus;  simpl. omega. 
    apply H10 in H11.
    assert (Hvv  :=  Mem.valid_access_store _ _ _ _ x0 H11). 
    inv Hvv.
    (* done *)
     
    do 2 eexists. exists lenv.
    split. 
    eapply t_trans.
    apply t_step. constructor.
    eapply t_trans.
    apply t_step. eapply step_assign with (v := x0) (m' := x7).  
    { 
      constructor.
      econstructor. constructor; eauto.
      constructor. simpl. unfold sem_add. simpl. reflexivity.      
    }
    constructor. eauto.    
    simpl. unfold sem_cast. simpl. 
    inv H3; reflexivity.
    econstructor. simpl. reflexivity.
    simpl. simpl in H12. apply H12.
    eapply t_trans; constructor; constructor. 
    simpl. reflexivity.
    {
      econstructor; eauto.
      apply Mem.load_store_same in H12; eauto.
      apply repr_val_L_load_result.
      (* need to know that args_ptr is disjoint from the portion of memory that concerns 
repr_val *)
      eapply repr_val_L_unchanged; eauto.
      eapply Mem.store_unchanged_on; eauto.
      intros.
      destruct HL_pro. destructAll.
      rewrite H8 in H19. inv H19.
      apply H20 with (z := 1%Z).
      unfold max_args.  
      rewrite Int.mul_one in *.
      split; auto.
      omega.
      rewrite Int.unsigned_repr.
      omega.
      unfold Int.max_unsigned; simpl. omega.
      auto.
    }      
Admitted.



(* Top level theorem on the L6_to_Clight translation *)
Theorem top_repr_L6_L7_are_related:
  