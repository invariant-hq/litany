(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-transposable-arguments" ~group:Rule.Pedantic
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"three adjacent same-typed unlabeled parameters"
    ~doc:
      {|Two adjacent same-typed unlabeled parameters include the symmetric
operations — `equal`, `compare`, `append`, `levenshtein` — where labels
would be noise. Three or more have no symmetric reading: every call
site is a silent transposition bug waiting, type-correct and wrong.

    (* bad *)  val invalid_arg' : string -> string -> string -> 'a
    (* good *) val invalid_arg' : m:string -> fn:string -> string -> 'a

Fires once per exported structure-level value binding of a
Library-kind unit whose arrow spine contains three or more consecutive
unlabeled parameters of equal type, anchored at the binding's name in
the implementation. Units without kind metadata degrade to silence;
labels break adjacency, which is exactly the remedy the rule teaches.
No fix: labeling is an API change.

Narrowings, each in the false-negative-safe direction: the spine is
read from the implementation binding's type rather than the interface
val (there is no signature dispatch kind yet, and findings anchor only
in the editable source) — the interface type is always at least as
specific, so an implementation hit implies an interface hit, never the
reverse; type equality is syntactic (`Path.same` heads with equal
arguments, or the same type variable) without abbreviation expansion,
so `t -> string -> t` with `type t = string` stays silent; and for
mli-backed units the export gate joins the interface's value names at
the unit's root (module-level linking is nominal by name), so values
of nested modules are not reported. Variadic-ish combinator
signatures where order is conventional are the recorded false-positive
risk and what Pedantic/off absorbs.|}
    ~kind_gated:true ()

let message =
  "three adjacent same-typed unlabeled parameters invite silent transposition; \
   label them"

(* Syntactic type equality: same head by [Path.same] with equal
   arguments, or the same type variable. No abbreviation expansion —
   there is no scope-level two-type equality yet (recorded gap); the
   refusal direction is a false negative, never a false positive. *)
let rec same_ty a b =
  match (Types.get_desc a, Types.get_desc b) with
  | Types.Tconstr (p, args, _), Types.Tconstr (q, brgs, _) ->
      Path.same p q
      && List.length args = List.length brgs
      && List.for_all2 same_ty args brgs
  | Types.Tvar _, Types.Tvar _ -> Types.get_id a = Types.get_id b
  | _, _ -> false

(* Arrow arguments are inspected through [arg_body]: since OCaml 5.5 every
   [Tarrow] argument type is a [Tpoly] node (trivial for ordinary
   arguments — types.mli pins the invariant); earlier compilers in the
   support window record the plain type. *)
let arg_body ty =
  match Types.get_desc ty with Types.Tpoly (body, _) -> body | _ -> ty

let rec spine acc ty =
  match Types.get_desc ty with
  | Types.Tarrow (lbl, arg, ret, _) -> spine ((lbl, arg_body arg) :: acc) ret
  | _ -> List.rev acc

let rec transposable = function
  | (Asttypes.Nolabel, a)
    :: ((Asttypes.Nolabel, b) :: (Asttypes.Nolabel, c) :: _ as rest) ->
      (same_ty a b && same_ty b c) || transposable rest
  | _ :: rest -> transposable rest
  | [] -> false

(* Structure-level bindings only: the dispatched binding must be a
   member of a root [Tstr_value] group — local helpers are outside the
   rule's claim (exported values). Physical membership is exact: the
   engine dispatches the implementation tree's own nodes. *)
let structure_level u (vb : Typedtree.value_binding) =
  List.exists
    (fun (it : Typedtree.structure_item) ->
      match it.str_desc with
      | Typedtree.Tstr_value (_, vbs) -> List.memq vb vbs
      | _ -> false)
    (Unit.implementation u).str_items

(* The export gate. Derived exports (no decoded interface) carry the
   definition UIDs bound_var reports — an exact join. Interface-sourced
   exports carry interface UIDs, so the join is the interface's value
   names at the unit's root — module-level linking's own nominal rule. *)
let exported u name uid =
  let value_named x =
    Unit.Export.kind x = Unit.Export.Value
    && String.equal (Unit.Export.name x) name
  in
  match Unit.interface u with
  | None ->
      List.exists
        (fun x ->
          Unit.Export.kind x = Unit.Export.Value
          && Shape.Uid.equal (Unit.Export.uid x) uid)
        (Unit.exports u)
  | Some _ -> List.exists value_named (Unit.exports u)

let rule =
  Rule.binding meta @@ fun u vb ->
  if Unit.kind u <> Some Unit.Library then []
  else
    match Pat.bound_var vb.Typedtree.vb_pat with
    | None -> []
    | Some (name, uid) ->
        if
          transposable (spine [] vb.Typedtree.vb_pat.pat_type)
          && structure_level u vb
          && exported u name.Location.txt uid
        then [ Finding.v ~loc:name.Location.loc message ]
        else []
