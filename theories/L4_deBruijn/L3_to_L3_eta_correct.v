(** Intermediate L3_eta language.

  Enforce eta-expanded branches in match, so that the following L3-L4 phase
  can strip them correctly. *)

Require Import Coq.Arith.Arith Coq.NArith.BinNat Coq.Strings.String Coq.Lists.List
        Coq.omega.Omega Coq.Program.Program Coq.micromega.Psatz.
Require Export Common.Common.  (* shared namespace *)
Open Scope N_scope.
Opaque N.add.
Opaque N.sub.
Require Import L4.expression.
Require Import L3_to_L3_eta.

Require Import L3.term L3.program L3.compile L3.wcbvEval.
Require L3_eta_crct.
Module L3C := L3_eta_crct.

Lemma Lookup_trans_env e nm t : LookupDfn nm e t -> LookupDfn nm (transEnv e) (trans t).
Proof.
  red. intros H. red in H.
  dependent induction H. simpl. constructor.
  constructor; auto.
Qed.

Lemma wcbvEval_pres_Crct e t t' :
  crctTerm e 0 t -> WcbvEval e t t' -> crctTerm e 0 t'.
Proof.
  intros.
  destruct (WcbvEval_pres_Crct e).
  now apply (H1 t).
Qed.

Lemma Crct_invrt_Case e n ann mch brs :
  crctTerm e n (TCase ann mch brs) ->
  crctTerm e n mch /\ crctBs e n brs /\
  crctAnnot e ann brs /\
  (forall i t, bnth i brs = Some t -> crctTerm e n (fst t)).
Proof.
  intros.
  apply Crct_invrt_Case in H. intuition. clear H2.
  revert H i t H1.
  induction 1; simpl; intros; try discriminate.
  destruct i. injection H2 as <-; auto.
  eapply IHcrctBs; eauto.
Qed.

Lemma L3C_Crct_invrt_Case e n ann mch brs :
  L3C.crctTerm e n (TCase ann mch brs) ->
  L3C.crctTerm e n mch /\ L3C.crctBs e n brs /\
  crctAnnot e ann brs /\
  (forall i t, bnth i brs = Some t ->
               is_n_lambda (snd t) (fst t) = true /\
               L3C.crctTerm e n (fst t)).
Proof.
  intros.
  apply L3C.Crct_invrt_Case in H.
  destruct H as (H&H'&H'').
  split; [ | split]; auto. split; auto.
  clear H H''.
  induction H'; simpl; intros; try discriminate.
  destruct i. injection H1 as <-; auto.
  eapply IHH'; eauto.
Qed.

Lemma L3C_Crct_construct {e : environ Term} {i n args} : L3C.crctEnv e ->
  L3C.crctTerm e 0 (TConstruct i n args) ->
  cnstrArity e i n = Ret (0%nat, tlength args).
Proof.
  intros.
  destruct i.
  apply L3C.Crct_invrt_Construct in H0 as (crctArgs&itypk&Hlook&ip&Hip&ctr&Hctr&Hargs).
  unfold cnstrArity.
  destruct Hlook as [Hlook Hne].
  apply Lookup_lookup in Hlook.
  unfold lookupTyp. rewrite Hlook. destruct itypk. elim Hne; reflexivity.
  rewrite Hip, Hctr. unfold ret. repeat f_equal. assumption.
Qed.

Lemma Crct_construct {e : environ Term} {i n args} :
  crctEnv e ->
  crctTerm e 0 (TConstruct i n args) ->
  cnstrArity e i n = Ret (0%nat, tlength args).
Proof.
  intros.
  destruct i.
  apply Crct_invrt_Construct in H0 as (crctArgs&itypk&Hlook&ip&Hip&ctr&Hctr&Hargs).
  unfold cnstrArity.
  destruct Hlook as [Hlook Hne].
  apply Lookup_lookup in Hlook.
  unfold lookupTyp. rewrite Hlook. destruct itypk. elim Hne; reflexivity.
  rewrite Hip, Hctr. unfold ret. repeat f_equal. assumption.
Qed.

Lemma bnth_trans n t i brs :
  bnth n brs = Some t -> exists t',
    bnth n (trans_brs i brs) = Some t' /\
    fst t' = eta_expand (snd t) (trans (fst t)).
Proof.
  revert n t i; induction brs; intros *.
  simpl; intros. discriminate.
  
  simpl. destruct n0. simpl.
  intros [= <-].
  eexists; split; eauto.
  simpl.
  
  intros. now eapply IHbrs.
Qed.
      
Arguments raise : simpl never.
Arguments String.append : simpl never.

Lemma match_annot_n {cnstrs brs n c t} :
  match_annot cnstrs brs ->
  exnNth cnstrs n = Ret c ->
  bnth n brs = Some t -> CnstrArity c = snd t.
Proof.
  intros H; revert n c t; induction H; intros; simpl; auto.
  - discriminate.
  - destruct n. injection H1; intros ->. injection H2; intros <-.
    simpl; auto.

    simpl in H1, H2.
    now specialize (IHmatch_annot _ _ _ H1 H2).
Qed.

Lemma WcbvEval_mkApp_einv {e f a s} : WcbvEval e (mkApp f a) s ->
                                      exists s', WcbvEval e f s'.
Proof.
  revert f; induction a; simpl; intros.
  - exists s. intuition. 
  - specialize (IHa (TApp f t) H).
    destruct IHa. inv H0.
    * now exists (TLambda nm bod).
    * now exists (TFix dts m).
    * now exists TProof.
Qed.

Lemma WcbvEval_is_n_lam e n t t' : is_n_lambda n t = true -> WcbvEval e t t' -> is_n_lambda n t' = true.
Proof.
  induction n; simpl; intros Hlam; auto.
  
  destruct t; try discriminate.
  intros. inv H.
  auto.
Qed.

Lemma wcbvEval_no_step e s t : WcbvEval e s t -> WcbvEval e t t.
Proof.
  apply WcbvEval_no_further.
Qed.
Hint Resolve wcbvEval_no_step.

Lemma WcbvEval_mkApp_inner e f s' a s :
  (WcbvEval e f s' ->
   WcbvEval e (mkApp s' a) s -> WcbvEval e (mkApp f a) s) /\
  (WcbvEval e f s' ->
   WcbvEval e (mkApp f a) s -> WcbvEval e (mkApp s' a) s).
  
Proof.
  revert f s' s; induction a; intros *; split; intros evf evapp; simpl in *.
  - pose (wcbvEval_no_step _ _ _ evf). rewrite <- (WcbvEval_single_valued w evapp). eauto.
  - rewrite <- (WcbvEval_single_valued evf evapp). eauto.
    
  - simpl in *.
    destruct (WcbvEval_mkApp_einv evapp) as [s'' evs''].
    assert(WcbvEval e (TApp f t) s'').
    { pose (wcbvEval_no_step _ _ _ evf). inv evs''. 
      pose proof (WcbvEval_single_valued w H1). subst s'.
      econstructor; eauto.
      pose proof (WcbvEval_single_valued w H1). subst s'.
      eapply wAppFix; eauto.
      pose proof (WcbvEval_single_valued w H1). subst s'.
      eapply wAppProof; eauto. }
    eapply (proj1 (IHa (TApp f t) s'' s)); eauto.
    eapply (proj2 (IHa (TApp s' t) s'' s)); eauto.

  - simpl in *.
    destruct (WcbvEval_mkApp_einv evapp) as [s'' evs''].
    assert(WcbvEval e (TApp s' t) s'').
    { inv evs''. 
      pose proof (WcbvEval_single_valued evf H1). subst s'.
      econstructor; eauto.
      pose proof (WcbvEval_single_valued evf H1). subst s'.
      eapply wAppFix; eauto.
      pose proof (WcbvEval_single_valued evf H1). subst s'.
      eapply wAppProof; eauto. }
    eapply (proj1 (IHa _ _ s)). eauto.
    eapply (proj2 (IHa _ _ s)). eapply evs''. apply evapp.
Qed.

Lemma instantiate_eta t k n u : WFTrm t 0 -> instantiate t k (eta_expand n u) =
                                            eta_expand n (instantiate t k u).
Proof.
  revert k u; induction n; intros. simpl. auto.
  simpl. rewrite instantiate_TLambda.
  f_equal. rewrite IHn; auto.
  f_equal. rewrite instantiate_TApp_commute.
  f_equal. rewrite <- (proj1 (instantiate_lift _)); auto. 
  lia.
Qed.
  
Lemma wcbvEval_eta e t s n : WcbvEval e t s -> exists s', WcbvEval e (eta_expand n t) s'.
Proof.
  induction n; intros.
  simpl.
  - now exists s.
  - simpl. eexists. constructor.
Qed.

Lemma is_n_lambda_eta n t : is_n_lambda n (eta_expand n t) = true.
Proof.
  revert t; induction n; intros; trivial.
  simpl. now rewrite IHn.
Qed.

Lemma is_n_lambda_lift n t : is_n_lambda n t = true -> forall k, is_n_lambda n (lift k t) = true.
Proof.
  revert t; induction n; intros; trivial.
  destruct t; simpl in *; try discriminate.
  simpl. now apply IHn.
Qed.

Lemma eval_app_terms e f args s :
  WFTrms args 0 -> WcbvEvals e args args ->
  WcbvEval e (mkApp f args) s ->
  WcbvEval e (mkApp (eta_expand (tlength args) f) args) s.
Proof.
  intros wfargs nosteps.
  revert e f s wfargs nosteps; induction args; intros.
  { simpl; trivial. }
  simpl in *; pose proof (WcbvEval_mkApp_einv H).
  destruct H0 as [s' evft].
  destruct (wcbvEval_eta _ _ _ (tlength args) evft).

  eapply WcbvEval_mkApp_inner with (s':=x). 
  - eapply wAppLam with (a1':=t). constructor.
    now inv nosteps.
    unfold whBetaStep.
    rewrite instantiate_eta.
    rewrite instantiate_TApp_commute.
    cbn. rewrite (proj1 (instantiate_noLift t)).
    exact H0. now inv wfargs.
  - eapply (proj2 (WcbvEval_mkApp_inner _ _ _ _ _)). eauto.
    eapply IHargs. now inv wfargs. now inv nosteps. eauto.
Qed. 

Lemma trans_terms_pres_tlength a : tlength a = tlength (trans_terms a).
Proof. induction a; trivial. simpl. now rewrite IHa. Qed.

Lemma lifts_preserves_tlength n a : tlength a = tlength (lifts n a).
Proof. induction a; trivial. simpl. now rewrite IHa. Qed.

Lemma liftds_preserves_dlength n a : dlength a = dlength (liftDs n a).
Proof. induction a; trivial. simpl. now rewrite IHa. Qed.

Lemma liftbs_preserves_blength n a : blength a = blength (liftBs n a).
Proof. induction a; trivial. simpl. now rewrite IHa. Qed.

Lemma trans_mkApp t u : trans (mkApp t u) = mkApp (trans t) (trans_terms u).
Proof.
  revert t; induction u; trivial.
  simpl. intros. now rewrite IHu. 
Qed.

Lemma trans_fixes_pres_dlength f : dlength (trans_fixes f) = dlength f.
Proof. induction f; simpl; auto. Qed.

Lemma instantiate_hom :
  (forall bod arg n, WFTrm (trans arg) 0 ->
      trans (instantiate arg n bod) =
      instantiate (trans arg) n (trans bod)) /\
  (forall bods arg n, WFTrm (trans arg) 0 ->
     trans_terms (instantiates arg n bods) =
     instantiates (trans arg) n (trans_terms bods)) /\
  (forall bods arg n, WFTrm (trans arg) 0 -> forall i,
     trans_brs i (instantiateBrs arg n bods) =
     instantiateBrs (trans arg) n (trans_brs i bods)) /\
  (forall ds arg n, WFTrm (trans arg) 0 ->
          trans_fixes (instantiateDefs arg n ds) =
     instantiateDefs (trans arg) n (trans_fixes ds)).
Proof.
  apply TrmTrmsBrsDefs_ind; intros; try (cbn; easy);
  try (cbn; rewrite H; easy).
  - cbn. destruct (lt_eq_lt_dec n0 n); cbn.
    + destruct s.
      * rewrite (proj1 (nat_compare_lt n0 n)); try omega. reflexivity.
      * subst. rewrite (proj2 (nat_compare_eq_iff _ _)); trivial. 
    + rewrite (proj1 (nat_compare_gt n0 n)); try intro; trivial.
  - cbn. now rewrite H, H0.
  - cbn. now rewrite H, H0.
  - rewrite instantiate_TConstruct. simpl. now rewrite H.
  - rewrite instantiate_TCase. simpl. now rewrite H, H0.
  - rewrite !instantiate_TFix; simpl. rewrite H; try easy.
    rewrite !instantiate_TFix; simpl. 
    now rewrite trans_fixes_pres_dlength. 
  - repeat (rewrite !instantiates_tcons; simpl). now rewrite <- H, H0.
  - repeat (rewrite !instantiateBs_bcons; simpl). f_equal.
    rewrite H by easy. rewrite instantiate_eta; auto.
    now apply H0.
  - repeat (rewrite !instantiateDs_dcons; simpl); now rewrite H, H0. 
Qed.

Lemma trans_instantiate_any  a k :
  WFTrm (trans a) 0 ->
  forall b, trans (L3.term.instantiate a k b) =
            instantiate (trans a) k (trans b).
Proof.
  intros. destruct instantiate_hom. now apply H0.
Qed.

Lemma trans_instantiate_fix x ds arg :
  WFTrmDs (trans_fixes ds) (dlength ds) ->
  pre_whFixStep (trans x) (trans_fixes ds) (trans arg) =
  trans (pre_whFixStep x ds arg).
Proof.
  simpl. unfold pre_whFixStep. f_equal.
  revert x.
  set(foo:= TFix (trans_fixes ds)).
  set(bar:= TFix ds).
  rewrite trans_fixes_pres_dlength. induction (list_to_zero (dlength ds)).
  simpl. reflexivity.
  simpl. intros.
  subst foo. rewrite <- (trans_instantiate_any (TFix ds a)).
  rewrite IHl. f_equal. auto. simpl. constructor.
  rewrite trans_fixes_pres_dlength. apply H.
Qed.

Lemma Lookup_hom:
  forall p (s:string) ec,
    Lookup s p ec -> Lookup s (transEnv p) (transEC ec).
Proof.
  induction 1; destruct t.
  - cbn. apply LHit.
  - cbn. apply LHit.
  - cbn. apply LMiss; assumption. 
  - cbn. apply LMiss; assumption. 
Qed.

Ltac eeasy := eauto 3; easy.

Lemma transEnv_pres_fresh e nm : fresh nm e -> fresh nm (transEnv e).
Proof.
  induction 1; constructor; auto.
Qed.

Lemma Crct_lift :
  (forall p n t, L3C.crctTerm p n t -> forall k,
                 L3C.crctTerm p (S n) (lift k t)) /\
  (forall p n ts, L3C.crctTerms p n ts -> forall k, L3C.crctTerms p (S n) (lifts k ts)) /\
  (forall p n bs, L3C.crctBs p n bs -> forall k, L3C.crctBs p (S n) (liftBs k bs)) /\
  (forall p n ds, L3C.crctDs p n ds -> forall k, L3C.crctDs p (S n) (liftDs k ds)) /\
  (forall e, L3C.crctEnv e -> True).
Proof.
  apply L3C.crctCrctsCrctBsDsEnv_ind; intros; simpl lift; auto; try solve [econstructor; eauto 2].
  - constructor. auto.
    destruct (Nat.compare_spec m k); subst; omega.
  - econstructor; try rewrite <- lifts_preserves_tlength; eauto. 
  - econstructor; eauto.
    destruct i; destruct H3 as [ityp [pack H3]]. red. intuition. do 2 eexists; intuition eauto.
    revert H6; clear. induction 1; constructor; eauto.
  - econstructor; eauto; rewrite <- liftds_preserves_dlength; eauto.
  - simpl liftBs. econstructor; eauto. now apply is_n_lambda_lift.
  - simpl. constructor; auto.
    destruct H3 as (na & body & ->). exists na; eexists; reflexivity.
  - simpl. constructor; auto.
    destruct H1 as (na & body & ->). exists na; eexists; reflexivity.
Qed.    

Lemma crctTerm_eta e n t : L3C.crctTerm e n t ->
                            forall m, L3C.crctTerm e n (eta_expand m t).
Proof.
  intros.
  revert n t H.
  induction m; intros; trivial.

  simpl eta_expand. constructor.
  eapply IHm. constructor. eapply (proj1 Crct_lift e n t H 0%nat).
  constructor; eauto with arith. now eapply L3C.Crct_CrctEnv in H.
Qed.

Lemma trans_pres_Crct :
  (forall p n t, crctTerm p n t -> L3C.crctTerm (transEnv p) n (trans t)) /\
  (forall p n ts, crctTerms p n ts ->
                  L3C.crctTerms (transEnv p) n (trans_terms ts)) /\
  (forall p n bs, crctBs p n bs -> forall i, L3C.crctBs (transEnv p) n (trans_brs i bs)) /\
  (forall p n (ds:Defs), crctDs p n ds -> L3C.crctDs (transEnv p) n (trans_fixes ds)) /\
  (forall p, crctEnv p -> L3C.crctEnv (transEnv p)).
Proof.
  apply crctCrctsCrctBsDsEnv_ind; intros; simpl; try solve [econstructor; eauto].

  - apply Lookup_hom in H1. econstructor; eauto. 
  - red in H. destruct H. apply Lookup_hom in H.
    econstructor; try split; try eeasy.
    now rewrite <- trans_terms_pres_tlength.
  - econstructor; eauto. destruct i.
    red in H3.
    destruct H3 as (pack&ityp&Hlook&Hip&Hann).
    exists pack, ityp. intuition try eeasy.
    destruct Hlook. split; auto. now apply Lookup_hom in H3. 
    revert Hann. clear; induction 1; simpl; constructor; auto.
  - econstructor; rewrite trans_fixes_pres_dlength; eauto.
  - econstructor; auto.
    clear -H0. induction m.
    simpl. apply H0.
    now eapply crctTerm_eta.
    apply is_n_lambda_eta.
  - econstructor; eauto.
    destruct H3 as (na & body & ->).
    exists na. eexists; simpl; eauto.
  - econstructor; eauto.
    destruct H1 as (na & body & ->).
    exists na. eexists; simpl; eauto.
  - econstructor; eauto. 
    now apply transEnv_pres_fresh.
  - econstructor; eauto. 
    now apply transEnv_pres_fresh.
Qed.
    
Lemma whCase_step e i n args brs cs s :
  crctEnv e -> crctBs e 0 brs -> crctAnnot e i brs -> crctTerms e 0 args ->
  cnstrArity e i n = Ret (0%nat, tlength args) ->
  whCaseStep n args brs = Some cs -> WcbvEval e cs s ->
  WcbvEvals (transEnv e) (trans_terms args) (trans_terms args) ->
  WcbvEval (transEnv e) (trans cs) (trans s) ->
  exists cs',
    whCaseStep n (trans_terms args) (trans_brs i brs) =
    Some cs' /\ WcbvEval (transEnv e) cs' (trans s).
Proof.
  intros crcte crctds crctann crctargs crctar Hcase Hev evargs IHev.
  unfold whCaseStep in Hcase.
  revert Hcase; case_eq (bnth n brs). intros [t arg] Hdn [= <-].
  unfold whCaseStep.
  
  unfold dnthBody in Hdn. case_eq (bnth n brs). intros. rewrite H in Hdn.
  destruct (bnth_trans _ _ i _ H) as [cs' [Hnth Heq]].
  unfold dnthBody. rewrite Hnth. destruct cs'. simpl in *.
  eexists; split; eauto.
  
  destruct p. simpl in *.
  injection Hdn. intros -> ->.
  assert(tlength args = arg).
  { unfold crctAnnot in *. destruct i as [nm ndx].
    destruct crctann as [pack [ityp [Hlook [Hind Hann]]]].
    unfold cnstrArity in crctar. red in Hlook. destruct Hlook as [Hlook none].
    apply Lookup_lookup in Hlook. unfold lookupTyp in *. rewrite Hlook in crctar.
    destruct pack; try discriminate. rewrite Hind in crctar.
    unfold getCnstr in crctar. case_eq (exnNth (itypCnstrs ityp) n).
    intros. rewrite H0 in crctar. discriminate.
    intros; rewrite H0 in crctar.
    injection crctar. intros.
    assert (me:=match_annot_n Hann H0 H). simpl in me. congruence. }
  clear Hnth H .

  clear crctar Hdn.
  subst t0. simpl in *. rewrite <- H0.
  rewrite (trans_terms_pres_tlength args).
  eapply eval_app_terms.
  eapply (proj1 (proj2 L3C.Crct_WFTrm)).
  (* trans preserves crct *)
  apply trans_pres_Crct. eassumption.
  apply evargs.
  now rewrite trans_mkApp in IHev.

  intros. rewrite H in Hdn. discriminate.

  intros. discriminate.
Qed.

Lemma dnthBody_trans n t brs :
  dnthBody n brs = Some t -> 
    dnthBody n (trans_fixes brs) = Some (trans t).
Proof.
  revert n t; induction brs as [ |na t k ds]; intros *.
  simpl; intros. discriminate.
  
  simpl. destruct n. simpl.
  intros [= <-].
  eexists; split; eauto.
  
  intros. now eapply IHds.
Qed.

Lemma pre_whFixStep_pres_Crct:
  forall (dts:Defs) p n a m x,
    crctDs p (n + dlength dts) dts -> crctTerm p n a ->
    dnthBody m dts = Some x ->
    crctTerm p n (pre_whFixStep x dts a).
Proof.
  intros.
  unfold pre_whFixStep.
  pose (whFixStep_pres_Crct n H m).
  unfold whFixStep in c. rewrite H1 in c.
  specialize (c _ eq_refl).
  constructor. apply c. apply H0.
Qed.

Lemma L3C_pre_whFixStep_pres_Crct:
  forall (dts:Defs) p n a m x,
    L3C.crctDs p (n + dlength dts) dts -> L3C.crctTerm p n a ->
    dnthBody m dts = Some x ->
    L3C.crctTerm p n (pre_whFixStep x dts a).
Proof.
  intros.
  unfold pre_whFixStep.
  pose (L3C.whFixStep_pres_Crct n H m).
  unfold whFixStep in c. rewrite H1 in c.
  specialize (c _ eq_refl).
  constructor. apply c. apply H0.
Qed.

(** Evaluated constructors have their arguments evaluated *)

Lemma trans_wcbvEval_construct e mch i n args :
  L3C.crctEnv e -> L3C.crctTerm e 0 mch ->
  WcbvEval e mch (TConstruct i n args) ->
  WcbvEvals e args args.
Proof.
  intros.
  dependent induction H1.
  - now eapply WcbvEval_no_further in H1.
  - eapply IHWcbvEval; eauto. eapply L3C.LookupDfn_pres_Crct in H2; eauto.
  - eapply IHWcbvEval3; eauto.
    eapply L3C.Crct_invrt_App in H0 as [H1 H2].
    eapply L3C.WcbvEval_pres_Crct in H1_; eauto 2.
    eapply L3C.WcbvEval_pres_Crct in H1_0; eauto 2.
    eapply L3C.Crct_invrt_Lam in H1_.
    eapply L3C.whBetaStep_pres_Crct; eauto.
  - eapply IHWcbvEval2; eauto.
    eapply L3C.Crct_invrt_LetIn in H0 as [Hdfn Hbod].
    eapply L3C.WcbvEval_pres_Crct in H1_; eauto.
    eapply L3C.instantiate_pres_Crct; eauto.
  - eapply IHWcbvEval2; eauto.
    apply L3C.Crct_invrt_App in H0 as [Hfn Harg].
    eapply L3C.WcbvEval_pres_Crct in H1_; eauto.
    eapply L3C.Crct_invrt_Fix in H1_.
    eapply L3C_pre_whFixStep_pres_Crct; eauto.
  - eapply IHWcbvEval2; eauto.
    apply L3C_Crct_invrt_Case in H0 as (Hmch & Hbrs & Hann & Hts). 
    eapply L3C.WcbvEval_pres_Crct in H1_; eauto.
    eapply L3C.whCaseStep_pres_Crct in H1; eauto.
    destruct i0; now eapply L3C.Crct_invrt_Construct in H1_ as [Hargs0 _].
Qed.

Theorem translate_correct_subst (e : environ Term) (t t' : Term) :
  crctEnv e -> crctTerm e 0 t ->
  WcbvEval e t t' -> 
  WcbvEval (transEnv e) (trans t) (trans t').
Proof.
  assert ((forall t t' : Term,
  WcbvEval e t t' -> 
  crctEnv e -> crctTerm e 0 t ->
  WcbvEval (transEnv e) (trans t) (trans t')) /\
          (forall t t' : Terms,
   WcbvEvals e t t' ->
   crctEnv e -> crctTerms e 0 t ->
   WcbvEvals (transEnv e) (trans_terms t) (trans_terms t'))).
  clear; apply WcbvEvalEvals_ind; simpl; auto.

  - intros i r args args' evargs evtras crcte crctc.
    destruct i as [ipkg inum]. 
    apply Crct_invrt_Construct in crctc.
    intuition.

  - intros nm t s Ht evalt IHt crcte crctt.
    econstructor; [ | eapply IHt]; eauto.
    apply Lookup_trans_env; auto.
    eapply Crct_LookupDfn_Crct; eauto.

  - intros * evfn IHfn evat IHa1 eva1' IHa1' crcte crctc.
    apply Crct_invrt_App in crctc as [crctfn crcta1].
    econstructor; eauto 2.

    assert(trans (whBetaStep bod a1') = whBetaStep (trans bod) (trans a1')).
    unfold whBetaStep. erewrite trans_instantiate_any; eauto.
    + eapply L3C.Crct_WFTrm. apply trans_pres_Crct. 
      eapply wcbvEval_pres_Crct; eauto.
    + rewrite <- H. apply IHa1'; auto.
      eapply whBetaStep_pres_Crct.
      apply wcbvEval_pres_Crct in evfn; auto.
      now apply Crct_invrt_Lam in evfn.
      apply wcbvEval_pres_Crct in evat; auto.

  - intros * evdfn IHdfn evbod IHbod crcte crctt.
    apply Crct_invrt_LetIn in crctt as [crctdn crctbod].
    econstructor; eauto 3.
    forward IHbod; auto. forward IHbod.
    erewrite <- trans_instantiate_any; eauto. 
    { eapply L3C.Crct_WFTrm. eapply trans_pres_Crct.
      eapply wcbvEval_pres_Crct in evdfn; eauto. }
    apply instantiate_pres_Crct; eauto.
    eapply WcbvEval_pres_Crct; eauto.

  - intros * evfix IHfix Hfix evapp IHapp crcte crcta.
    specialize (IHapp crcte).
    apply Crct_invrt_App in crcta as [crctfn crctarg].
    eapply wAppFix with (s := trans s). forward IHfix; auto.
    apply (dnthBody_trans _ _) in Hfix.
    apply Hfix.
    eapply WcbvEval_pres_Crct in evfix; eauto.
    apply Crct_invrt_Fix in evfix. simpl in evfix.
    eapply pre_whFixStep_pres_Crct in Hfix; eauto; simpl; eauto.
    specialize (IHapp Hfix).
    rewrite trans_instantiate_fix. apply IHapp.
    eapply L3C.Crct_WFTrm.
    eapply trans_pres_Crct; eauto.

  - intros fn arg evprf IHev crcte crctt.
    intros.
    apply Crct_invrt_App in H1 as [Hfn Harg].
    eapply wAppProof; eauto 4.

  - intros * evmch IHmch Hcase evcs IHcs crcte crctc.
    apply Crct_invrt_Case in crctc as [crctmch [crctbrs [crctann H']]].
    specialize (IHmch crcte crctmch).
    pose (whCase_step e i n args brs cs s crcte crctbrs crctann).
    forward e0. forward e0. specialize (e0 Hcase evcs).
    forward e0. forward e0. destruct e0 as [cs' [whtrans evtrans]].
    econstructor; eauto.
    eapply IHcs; eauto.
    eapply whCaseStep_pres_Crct in Hcase; eauto.
    apply trans_wcbvEval_construct in IHmch; eauto;
    eapply trans_pres_Crct; eauto.
    eapply WcbvEval_pres_Crct in evmch; eauto.
    now apply Crct_construct in evmch.
    eapply WcbvEval_pres_Crct in evmch; eauto.
    destruct i. now eapply Crct_invrt_Construct in evmch as [Hargs _].
    
  - intros * evmch IHmch. intros.
    inv H1.
    constructor; auto. 
  - intros. apply H; auto.
Qed.
Print Assumptions translate_correct_subst.