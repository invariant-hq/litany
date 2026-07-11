(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

type decl = {
  path : string;
  unit_name : string;
  uid : Shape.Uid.t;
  name : string;
  loc : Location.t;
  root : bool;
  used_internally : bool;
}

type t =
  | Decl of decl
  | Unit_node of { path : string; unit_name : string; root : bool }
  | Use_item of { user : string; uid : Shape.Uid.t }
  | Use_unit of { user : string; target : string }

let projects_into ~target unit_name =
  String.equal target unit_name
  ||
  let prefix = target ^ "__" in
  String.length unit_name > String.length prefix
  && String.equal (String.sub unit_name 0 (String.length prefix)) prefix

(* [shield_targets unit_name] enumerates every [target] with
   [projects_into ~target unit_name]: the name itself plus each wrapper
   prefix — [p] with [unit_name = p ^ "__" ^ rest], [rest] nonempty —
   found by scanning for ["__"] occurrences (overlapping included:
   ["A___B"] yields ["A"] and ["A_"]), exactly the substring law
   [projects_into] states. A handful of strings per name, so a
   [Hashtbl]-keyed join over them answers each row in O(1) where the
   naive scan is O(units) — the report phases must stay linear in the
   fact universe. *)
let shield_targets unit_name =
  let n = String.length unit_name in
  let acc = ref [ unit_name ] in
  for i = n - 3 downto 0 do
    if unit_name.[i] = '_' && unit_name.[i + 1] = '_' then
      acc := String.sub unit_name 0 i :: !acc
  done;
  !acc

(* {1 The [@litany.root] scan}

   Spans of declarations carrying a [[@litany.root]] attribute, from the
   substrate the export rows were sourced from — the interface typedtree when
   {!Litany.Unit.exports} read the interface, the implementation otherwise —
   so containment joins export locs against the same coordinate space.
   Literal sub-signatures/-structures recurse, matching the exports'
   [Mty_signature]-only recursion; an annotated module roots its members by
   containment. *)

let is_root_attr (a : Parsetree.attribute) =
  String.equal a.Parsetree.attr_name.Location.txt "litany.root"

let has_root attrs = List.exists is_root_attr attrs

let rec rooted_of_signature acc (sg : Typedtree.signature) =
  List.fold_left rooted_of_sig_item acc sg.Typedtree.sig_items

and rooted_of_sig_item acc (item : Typedtree.signature_item) =
  match item.Typedtree.sig_desc with
  | Typedtree.Tsig_value vd ->
      if has_root vd.Typedtree.val_attributes then vd.Typedtree.val_loc :: acc
      else acc
  | Typedtree.Tsig_module md ->
      let acc =
        if has_root md.Typedtree.md_attributes then md.Typedtree.md_loc :: acc
        else acc
      in
      rooted_of_module_type acc md.Typedtree.md_type
  | _ -> acc

and rooted_of_module_type acc (mty : Typedtree.module_type) =
  match mty.Typedtree.mty_desc with
  | Typedtree.Tmty_signature sg -> rooted_of_signature acc sg
  | _ -> acc

let rec rooted_of_structure acc (str : Typedtree.structure) =
  List.fold_left rooted_of_str_item acc str.Typedtree.str_items

and rooted_of_str_item acc (item : Typedtree.structure_item) =
  match item.Typedtree.str_desc with
  | Typedtree.Tstr_value (_, vbs) ->
      List.fold_left
        (fun acc (vb : Typedtree.value_binding) ->
          if has_root vb.Typedtree.vb_attributes then vb.Typedtree.vb_loc :: acc
          else acc)
        acc vbs
  | Typedtree.Tstr_primitive vd ->
      if has_root vd.Typedtree.val_attributes then vd.Typedtree.val_loc :: acc
      else acc
  | Typedtree.Tstr_module mb ->
      let acc =
        if has_root mb.Typedtree.mb_attributes then mb.Typedtree.mb_loc :: acc
        else acc
      in
      rooted_of_module_expr acc mb.Typedtree.mb_expr
  | _ -> acc

and rooted_of_module_expr acc (me : Typedtree.module_expr) =
  match me.Typedtree.mod_desc with
  | Typedtree.Tmod_structure str -> rooted_of_structure acc str
  | _ -> acc

let covered rooted (l : Location.t) =
  List.exists
    (fun (r : Location.t) ->
      String.equal r.loc_start.pos_fname l.loc_start.pos_fname
      && r.loc_start.pos_cnum <= l.loc_start.pos_cnum
      && l.loc_end.pos_cnum <= r.loc_end.pos_cnum)
    rooted

(* {1 Collection} *)

let collect ~closed_world u =
  let path = Unit.path u in
  let unit_name = Unit.name u in
  let unit_root =
    match Unit.kind u with
    | Some Unit.Executable | Some Unit.Test -> true
    | Some Unit.Library | None -> false
  in
  let policy_root =
    (* Public-library exports are roots, never candidates — external
       consumers exist outside every universe litany can enumerate;
       [closed-world] opts the workspace out. Unknown visibility
       means public. *)
    (not closed_world)
    && (match Unit.kind u with Some Unit.Library -> true | _ -> false)
    &&
    match Unit.visibility u with
    | Unit.Public | Unit.Unknown -> true
    | Unit.Private -> false
  in
  let rooted =
    match Unit.interface u with
    | Some sg -> rooted_of_signature [] sg
    | None -> rooted_of_structure [] (Unit.implementation u)
  in
  (* Anchor rewriting: recorded names are not adapter paths. A loc naming
     the interface source (by basename) anchors there — an unused export is
     an [.mli] line; one naming the editable source anchors at the unit's
     path. Anything else — a preprocessed unit's pp file — is carried as
     recorded and renders location-only, honestly. *)
  let intf_path = Option.map Source.path (Unit.interface_source u) in
  let rewrite_to target (l : Location.t) =
    {
      l with
      loc_start = { l.loc_start with pos_fname = target };
      loc_end = { l.loc_end with pos_fname = target };
    }
  in
  let anchor (l : Location.t) =
    let base = Filename.basename l.loc_start.pos_fname in
    match intf_path with
    | Some ip when String.equal base (Filename.basename ip) -> rewrite_to ip l
    | _ ->
        if String.equal base (Filename.basename path) then rewrite_to path l
        else l
  in
  let decls =
    List.filter_map
      (fun x ->
        match Unit.Export.kind x with
        | Unit.Export.Type | Unit.Export.Module | Unit.Export.Exception ->
            (* Value rows only: types, modules, and exceptions have no
               always-on cross-unit use signal (the use index is
               value-shaped, occurrence recording is build-flag-dependent),
               so 1.0 keeps them out rather than guess. *)
            None
        | Unit.Export.Value ->
            let uid = Unit.Export.uid x in
            let loc = Unit.Export.loc x in
            let used_internally =
              Unit.uses u uid <> []
              || List.exists
                   (fun d -> Unit.uses u d <> [])
                   (Unit.implementations u uid)
            in
            Some
              (Decl
                 {
                   path;
                   unit_name;
                   uid;
                   name = Unit.Export.name x;
                   loc = anchor loc;
                   root = policy_root || covered rooted loc;
                   used_internally;
                 }))
      (Unit.exports u)
  in
  let uses =
    List.map
      (fun d -> Use_item { user = unit_name; uid = Unit.Dep.uid d })
      (Unit.deps u)
    @ List.map
        (fun target -> Use_unit { user = unit_name; target })
        (Unit.unit_refs u)
  in
  (Unit_node { path; unit_name; root = unit_root } :: decls) @ uses
