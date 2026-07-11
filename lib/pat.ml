(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* A pattern is a CPS matcher over a typed capture stack: feed it the unit
   (for identity scope), the node, and the captures collected so far; it
   returns the stack extended with its own captures, or backtracks by
   raising [Fail]. The continuation is applied exactly once, by [run], at
   commit — after the whole pattern has matched — so an arm that ultimately
   fails never applies it; its abandoned [Snoc]s are garbage, not calls.
   [Fail] never escapes this module — [run] fences it, nested [run]s fence
   their own, and rule code cannot name it — so [ ||| ]'s handler can only
   ever catch a combinator's own refusal.

   [('b, 'j) stack] is the typed snoc-list: applying a continuation of
   type ['b] to the captures in order (oldest first) yields ['j]. A
   pattern [('m, 'k, 'r) t] extends a [('b, 'k) stack] to a
   [('b, 'r) stack] — the same continuation-type bookkeeping the eager
   encoding did by partial application, without running ['k]. The base
   type ['b] is no business of any pattern, hence the polymorphic
   [exec] field. *)

type ('b, 'j) stack =
  | Nil : ('b, 'b) stack
  | Snoc : ('b, 'a -> 'j) stack * 'a -> ('b, 'j) stack

type ('m, 'k, 'r) t = {
  exec : 'b. Unit.t -> 'm -> ('b, 'k) stack -> ('b, 'r) stack;
}

exception Fail

let fail () = raise_notrace Fail

(* [apply k s] is [k c1 ... cn] for the captures of [s], oldest first —
   the one commit point. *)
let rec apply : type b j. b -> (b, j) stack -> j =
 fun k -> function Nil -> k | Snoc (s, x) -> (apply k s) x

let run p u x k =
  match p.exec u x Nil with s -> Some (apply k s) | exception Fail -> None

let __ = { exec = (fun _ x s -> Snoc (s, x)) }
let drop = { exec = (fun _ _ s -> s) }
let as__ p = { exec = (fun u x s -> p.exec u x (Snoc (s, x))) }

let ( ||| ) p p' =
  { exec = (fun u x s -> try p.exec u x s with Fail -> p'.exec u x s) }

(* Creation-time literal registry (the rule harness's audit substrate):
   every name the raising literal combinators accept — [ident]/[idents]
   in the value namespace, [typ] in the type namespace — is recorded at
   combinator construction, deduplicated by rendering. [reference]-built
   patterns are configuration, not literals, and stay out. Under the
   hoisting discipline recording happens at module initialization,
   before any parallelism. *)
module Registry = struct
  let values : (string, Naming.Name.t) Hashtbl.t = Hashtbl.create 64
  let types : (string, Naming.Name.t) Hashtbl.t = Hashtbl.create 16

  let record tbl n =
    let key = Naming.Name.to_string n in
    if not (Hashtbl.mem tbl key) then Hashtbl.add tbl key n

  let sorted tbl =
    List.sort Naming.Name.compare
      (Hashtbl.fold (fun _ n acc -> n :: acc) tbl [])

  let names () = sorted values
  let type_names () = sorted types
end

(* The name is parsed at combinator construction, once per hoisted pattern;
   per node the test is [Scope.matches] — a UID equality against a 1-2
   element set after the run's first resolution. *)
let ident_of_name n =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_ident (_, _, vd)
          when Naming.Scope.matches (Unit.scope u) n vd.Types.val_uid ->
            s
        | _ -> fail ());
  }

let ident name =
  match Naming.Name.of_string name with
  | Error e ->
      invalid_arg (Format.asprintf "Pat.ident: %a" Naming.Name.pp_error e)
  | Ok n ->
      Registry.record Registry.values n;
      ident_of_name n

let idents = function
  | [] -> invalid_arg "Pat.idents: empty name list"
  | first :: rest ->
      List.fold_left (fun p name -> p ||| ident name) (ident first) rest

(* [Apply_arg.unlabeled_all]/[unlabeled_opt_all] are the version
   seam over [Texp_apply]'s argument shape (see dune); both apply
   combinators refuse any labeled or omitted-unlabeled argument. The
   callee pattern runs before the argument view so the common failing
   path — an application whose callee is not the sought identity —
   allocates nothing; the argument list is built only after the callee
   matched. *)

let apply pf pargs =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_apply (callee, args) -> (
            let s = pf.exec u callee s in
            match Apply_arg.unlabeled_all args with
            | Some xs -> pargs.exec u xs s
            | None -> fail ())
        | _ -> fail ());
  }

(* [apply_opt]'s argument view skips optional arguments — omitted or
   evaluated — so a saturated call to a function with [?opt] parameters
   (whose omission the compiler records in the argument list) still
   matches on its positionals. Labeled arguments, and omitted unlabeled
   ones, refuse. *)
let apply_opt pf pargs =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_apply (callee, args) -> (
            let s = pf.exec u callee s in
            match Apply_arg.unlabeled_opt_all args with
            | Some xs -> pargs.exec u xs s
            | None -> fail ())
        | _ -> fail ());
  }

(* Like [ident], the name is parsed once per hoisted pattern; per node the
   test is [Scope.matches_type] — a predefined-ident equality or a
   memoized-signature walk of the head path. The unit's scope carries its
   own signature as the local-alias context, so a head module the unit
   itself binds by alias or functor application resolves too. *)
let typ name =
  match Naming.Name.of_string name with
  | Error e ->
      invalid_arg (Format.asprintf "Pat.typ: %a" Naming.Name.pp_error e)
  | Ok n ->
      Registry.record Registry.types n;
      {
        exec =
          (fun u (ty : Types.type_expr) s ->
            match Types.get_desc ty with
            | Types.Tconstr (p, _, _)
              when Naming.Scope.matches_type (Unit.scope u) n p ->
                s
            | _ -> fail ());
      }

let bound_var (p : Typedtree.pattern) =
  match p.pat_desc with
  | Typedtree.Tpat_var (_, name, uid) -> Some (name, uid)
  | _ -> Pat_alias.bound_alias p

(* Literal views, payload-pattern shape (the simplification pass): the
   view matches the literal node and delegates its value to a payload
   pattern — [cst v] for a known value, [__] to capture — so every
   literal kind has one export, not a test form and a capture form. *)

let cst v = { exec = (fun _ x s -> if x = v then s else fail ()) }

let eint p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_constant (Asttypes.Const_int m) -> p.exec u m s
        | _ -> fail ());
  }

let estring p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_constant (Asttypes.Const_string (v, _, _)) ->
            p.exec u v s
        | _ -> fail ());
  }

(* ------------------------------------------------------------------ *)
(* Constructor and literal views. Representation, refusal, and        *)
(* hoisting contracts are those of the core combinators above.        *)
(* ------------------------------------------------------------------ *)

(* Predefined-constructor identity: the description's result-type head is
   compared with [Path.same] against the [Predef] path, plus a name
   equality — never the spelled [Longident], and never predef [cstr_uid]s
   (their cross-session stability is undocumented; [Predef] paths are the
   contract). [Cstr] is the churn seam over the description's module home
   ([Types] in 5.3, [Data_types] from 5.4). *)
let predef_cstr cd path name =
  String.equal (Cstr.name cd) name
  && match Cstr.res_head cd with Some p -> Path.same p path | None -> false

(* Global-path identity for constructors of non-predef stdlib types
   ([Stdlib.result], [CamlinternalFormatBasics.format6]): the result-type
   head must be a [Pdot] rooted at a persistent ident of the expected
   name. Persistent unit names are link-unique, so this is identity, not
   spelling. *)
let global_cstr cd ~unit_name ~type_name ~name =
  String.equal (Cstr.name cd) name
  &&
  match Cstr.res_head cd with
  | Some (Path.Pdot (Path.Pident id, ty)) ->
      String.equal ty type_name && Ident.persistent id
      && String.equal (Ident.name id) unit_name
  | Some _ | None -> false

(* Generic views. *)

let nil = { exec = (fun _ x s -> match x with [] -> s | _ :: _ -> fail ()) }

let ( ^:: ) p ps =
  {
    exec =
      (fun u x s ->
        match x with h :: t -> ps.exec u t (p.exec u h s) | [] -> fail ());
  }

let last p =
  {
    exec =
      (fun u x s ->
        let rec go = function
          | [] -> fail ()
          | [ v ] -> p.exec u v s
          | _ :: t -> go t
        in
        go x);
  }

let some p =
  {
    exec =
      (fun u x s -> match x with Some v -> p.exec u v s | None -> fail ());
  }

let none =
  { exec = (fun _ x s -> match x with None -> s | Some _ -> fail ()) }

(* Further expression patterns. *)

let var =
  {
    exec =
      (fun _ (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_ident (p, _, _) -> Snoc (s, p)
        | _ -> fail ());
  }

(* The per-node test is [Scope.matches_module] — UID and unit-name
   equalities against the boundary memoized at the run's first resolution
   of the path. *)
let from_module_path p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_ident (_, _, vd)
          when Naming.Scope.matches_module (Unit.scope u) p vd.Types.val_uid ->
            s
        | _ -> fail ());
  }

(* Sugar over the single-component module-path boundary
   ([matches_module]'s unit case — no cmi read): a unit name is the
   [Module_path] grammar's one-component form, and the dot guard keeps
   [from_unit] a unit-name form, never a path form. *)
let from_unit unit_name =
  let malformed () =
    invalid_arg
      (Format.asprintf "Pat.from_unit: %S is not a module name" unit_name)
  in
  if String.contains unit_name '.' then malformed ()
  else
    match Naming.Module_path.of_string unit_name with
    | Error _ -> malformed ()
    | Ok p -> from_module_path p

(* Data is total: a reference is well-formed by construction, and each
   arm is exactly the relation its grammar half denotes. *)
let of_ref = function
  | Naming.Ref.Value n -> ident_of_name n
  | Naming.Ref.Module p -> from_module_path p

(* Sugar over the data pair: [Naming.Ref.of_string] classifies and
   parses — the char-level classifier lives in the grammar module — and
   [of_ref] is the pattern. The error stays a rendered string because
   its consumers are configuration surfaces mid-refusal;
   [Ref.pp_error] names the classified grammar. *)
let reference path =
  match Naming.Ref.of_string path with
  | Ok r -> Ok (of_ref r)
  | Error e -> Error (Format.asprintf "%a" Naming.Ref.pp_error e)

(* The boolean literal view: either literal, by predefined-bool identity,
   value to the payload pattern — [ebool (cst true)] is the known-literal
   test, [ebool __] the either-literal capture. *)
let ebool p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [])
          when predef_cstr cd Predef.path_bool "true" ->
            p.exec u true s
        | Typedtree.Texp_construct (_, cd, [])
          when predef_cstr cd Predef.path_bool "false" ->
            p.exec u false s
        | _ -> fail ());
  }

let enil =
  {
    exec =
      (fun _ (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [])
          when predef_cstr cd Predef.path_list "[]" ->
            s
        | _ -> fail ());
  }

let econs ph pt =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [ h; t ])
          when predef_cstr cd Predef.path_list "::" ->
            pt.exec u t (ph.exec u h s)
        | _ -> fail ());
  }

let esome p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [ v ])
          when predef_cstr cd Predef.path_option "Some" ->
            p.exec u v s
        | _ -> fail ());
  }

let enone =
  {
    exec =
      (fun _ (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [])
          when predef_cstr cd Predef.path_option "None" ->
            s
        | _ -> fail ());
  }

let eok p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [ v ])
          when global_cstr cd ~unit_name:"Stdlib" ~type_name:"result" ~name:"Ok"
          ->
            p.exec u v s
        | _ -> fail ());
  }

let eerror p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [ v ])
          when global_cstr cd ~unit_name:"Stdlib" ~type_name:"result"
                 ~name:"Error" ->
            p.exec u v s
        | _ -> fail ());
  }

let if_ pc pt pe =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_ifthenelse (c, t, els) ->
            pe.exec u els (pt.exec u t (pc.exec u c s))
        | _ -> fail ());
  }

(* [match_] refuses effect-handler cases; [try_] tolerates them. The
   asymmetry is the mli's contract: a match's cases are the object of
   study and a handler must not be misread as one, while a try's
   exception cases mean what they always mean. *)

let match_ ps pcs =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_match (scrut, ccases, [], _) ->
            pcs.exec u ccases (ps.exec u scrut s)
        | _ -> fail ());
  }

let try_ pb pcs =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_try (body, exn_cases, _) ->
            pcs.exec u exn_cases (pb.exec u body s)
        | _ -> fail ());
  }

(* Statement-spine views: the spine strippers care only where a
   sequence or let ends; bindings and left legs stay unexamined until a
   rule needs them. *)
let seq_ p1 p2 =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_sequence (l, r) -> p2.exec u r (p1.exec u l s)
        | _ -> fail ());
  }

let let_body p =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_let (_, _, body) -> p.exec u body s
        | _ -> fail ());
  }

let fun_body pps pb =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_function (params, Tfunction_body b) ->
            pb.exec u b (pps.exec u params s)
        | _ -> fail ());
  }

let fun_cases pps pcs =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_function (params, Tfunction_cases fc) ->
            pcs.exec u fc.cases (pps.exec u params s)
        | _ -> fail ());
  }

let format =
  {
    exec =
      (fun _ (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_construct (_, cd, [ _fmt; lit ])
          when global_cstr cd ~unit_name:"CamlinternalFormatBasics"
                 ~type_name:"format6" ~name:"Format" -> (
            match lit.exp_desc with
            | Typedtree.Texp_constant (Asttypes.Const_string (str, _, _)) ->
                Snoc (s, str)
            | _ -> fail ())
        | _ -> fail ());
  }

(* Parameter and case patterns. *)

let param pp =
  {
    exec =
      (fun u (fp : Typedtree.function_param) s ->
        match (fp.fp_arg_label, fp.fp_kind) with
        | Asttypes.Nolabel, Typedtree.Tparam_pat p -> pp.exec u p s
        | _ -> fail ());
  }

let case pp pg pr =
  {
    exec =
      (fun u (c : _ Typedtree.case) s ->
        pr.exec u c.Typedtree.c_rhs
          (pg.exec u c.Typedtree.c_guard (pp.exec u c.Typedtree.c_lhs s)));
  }

(* Typed-pattern patterns. None match through [Tpat_alias] or [Tpat_or]:
   an aliased or or-composed pattern is a different shape and refuses. *)

let pany =
  {
    exec =
      (fun _ (p : Typedtree.pattern) s ->
        match p.pat_desc with Typedtree.Tpat_any -> s | _ -> fail ());
  }

let pvar =
  {
    exec =
      (fun _ (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_var (id, _, _) -> Snoc (s, id)
        | _ -> fail ());
  }

let pnil =
  {
    exec =
      (fun _ (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [], _)
          when predef_cstr cd Predef.path_list "[]" ->
            s
        | _ -> fail ());
  }

let pcons ph pt =
  {
    exec =
      (fun u (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [ h; t ], _)
          when predef_cstr cd Predef.path_list "::" ->
            pt.exec u t (ph.exec u h s)
        | _ -> fail ());
  }

let pbool b =
  let name = if b then "true" else "false" in
  {
    exec =
      (fun _ (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [], _)
          when predef_cstr cd Predef.path_bool name ->
            s
        | _ -> fail ());
  }

let psome pp =
  {
    exec =
      (fun u (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [ v ], _)
          when predef_cstr cd Predef.path_option "Some" ->
            pp.exec u v s
        | _ -> fail ());
  }

let pnone =
  {
    exec =
      (fun _ (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [], _)
          when predef_cstr cd Predef.path_option "None" ->
            s
        | _ -> fail ());
  }

(* Pattern-side [Stdlib.result] constructors: global-path identity as
   [eok]/[eerror]. *)
let pok pp =
  {
    exec =
      (fun u (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [ v ], _)
          when global_cstr cd ~unit_name:"Stdlib" ~type_name:"result" ~name:"Ok"
          ->
            pp.exec u v s
        | _ -> fail ());
  }

let perror pp =
  {
    exec =
      (fun u (p : Typedtree.pattern) s ->
        match p.pat_desc with
        | Typedtree.Tpat_construct (_, cd, [ v ], _)
          when global_cstr cd ~unit_name:"Stdlib" ~type_name:"result"
                 ~name:"Error" ->
            pp.exec u v s
        | _ -> fail ());
  }

let pvalue pp =
  {
    exec =
      (fun u (cp : Typedtree.computation Typedtree.general_pattern) s ->
        match cp.pat_desc with
        | Typedtree.Tpat_value arg -> pp.exec u (arg :> Typedtree.pattern) s
        | _ -> fail ());
  }

(* Tuple views. [Tuple] is the version seam over the payload shape
   (labeled components from 5.4, see dune); both legs deliver unlabeled
   components only, so one labeled component refuses here without this
   module naming the 5.4 shape. The expression side ([etuple]) ships with its
   first consuming rule, not before; [Tuple.expr_components] stays
   in the seam for its return. *)

let ptuple pps =
  {
    exec =
      (fun u (p : Typedtree.pattern) s ->
        match Tuple.pat_components p with
        | Some ps -> pps.exec u ps s
        | None -> fail ());
  }

(* Record views. The [label_description] module home churns with [constructor_description]
   (Types in 5.3, Data_types from 5.4), so [Lbl] rides the [Cstr] seam;
   [Field.t] is a thin pair so the fields-array shape and the
   [record_label_definition] payloads ([Kept] gained a field mid-window)
   never reach rule code. *)

module Lbl = struct
  type t = Cstr.lbl

  let name = Cstr.lbl_name
  let res_head = Cstr.lbl_res_head
  let is_mutable = Cstr.lbl_mutable
end

module Field = struct
  type t = Lbl.t * Typedtree.expression option

  let label ((l, _) : t) = l
  let definition ((_, d) : t) = d
end

let erecord pext =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_record { fields; extended_expression; _ } ->
            (* Declaration order — the typedtree does not record source order.
               [Kept _] matches both payload arities of the mid-window churn. *)
            let fs =
              Array.to_list
                (Array.map
                   (fun (l, def) ->
                     ( l,
                       match def with
                       | Typedtree.Overridden (_, d) -> Some d
                       | Typedtree.Kept _ -> None ))
                   fields)
            in
            pext.exec u extended_expression (Snoc (s, fs))
        | _ -> fail ());
  }

let efield pe =
  {
    exec =
      (fun u (e : Typedtree.expression) s ->
        match e.exp_desc with
        | Typedtree.Texp_field (subject, _, l) ->
            pe.exec u subject (Snoc (s, l))
        | _ -> fail ());
  }

let pexception pp =
  {
    exec =
      (fun u (cp : Typedtree.computation Typedtree.general_pattern) s ->
        match cp.pat_desc with
        | Typedtree.Tpat_exception p -> pp.exec u p s
        | _ -> fail ());
  }

(* Queries: bounded [Tast_iterator] sub-walks of the given node, default
   iterator coverage, [Ident.same] identity — a same-spelled rebinding is
   a different ident and does not count as an occurrence. *)

let occurs id e =
  let found = ref false in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub (ex : Typedtree.expression) ->
          (match ex.exp_desc with
          | Typedtree.Texp_ident (Path.Pident id', _, _) when Ident.same id id'
            ->
              found := true
          | _ -> ());
          if not !found then default.expr sub ex);
    }
  in
  iterator.expr iterator e;
  !found

let case_occurs id (c : _ Typedtree.case) =
  (match c.Typedtree.c_guard with Some g -> occurs id g | None -> false)
  || occurs id c.Typedtree.c_rhs

(* The declaration-wide reference query. The default iterator's
   [type_declaration] coverage is the version
   seam for the constraints field's mid-window rename ([typ_cstrs] →
   [typ_constraints]): this module never names the field. *)
let type_refs (d : Typedtree.type_declaration) =
  let acc = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.typ =
        (fun sub (ct : Typedtree.core_type) ->
          (match ct.ctyp_desc with
          | Typedtree.Ttyp_constr (p, _, _) -> acc := p :: !acc
          | _ -> ());
          default.typ sub ct);
    }
  in
  iterator.type_declaration iterator d;
  List.rev !acc

let payload_string = function
  | Parsetree.PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ( {
                  pexp_desc =
                    Pexp_constant { pconst_desc = Pconst_string (s, loc, _); _ };
                  _;
                },
                _ );
          _;
        };
      ] ->
      Some (s, loc)
  | Parsetree.PStr _ | Parsetree.PSig _ | Parsetree.PTyp _ | Parsetree.PPat _ ->
      None
