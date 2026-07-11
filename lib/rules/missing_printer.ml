(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"missing-printer" ~group:Rule.Pedantic
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"comparable abstract type whose interface exposes no printer"
    ~doc:
      {|An interface that already exposes `equal`, `compare`, or
`to_string` for its abstract type has declared it a
comparable/serializable value — and a value you can compare but not
print is a debugging dead end. Handle and machine types without that
value evidence are left alone: reasonable maintainers disagree there,
which is why this rule is Pedantic.

    (* bad *)  type t  val equal : t -> t -> bool             (* no pp *)
    (* good *) type t  val equal : t -> t -> bool  val pp : Format.formatter -> t -> unit

Fires once per abstract type — no manifest, no representation — in the
unit's interface whose same signature level exposes an
`equal : t -> t -> bool`, `compare : t -> t -> int`, or
`to_string : t -> string` (shapes checked against that type's own
identity, never by name alone) and no `pp` (or `pp_<name>`) of type
`Format.formatter -> t -> unit`, anchored at the implementation's
matching toplevel type declaration — the emit contract owns findings to
the editable source, so the `.mli` declaration itself cannot anchor.
Units without an interface, abstract types without value evidence,
manifest and represented types, and printers for other types that
happen to be named `pp` deliberately do not fire. Recorded false
negatives: types declared in submodule signatures (the toplevel join
is what the `type_decl` seam supports today) and interface types
satisfied by an `include` in the implementation. An `equal` that
exists only to feed a container functor is the accepted Pedantic
price — `[@litany.expect]` covers it. No fix: naming and placing a
printer is authorship.|}
    ()

let message =
  "this abstract type is comparable in its interface but has no printer"

(* The dispatched group is toplevel iff it is an item of the root
   structure's own item list — physical identity, the engine dispatches
   the tree's own payloads. *)
let toplevel_group u (decls : Typedtree.type_declaration list) =
  List.exists
    (fun (item : Typedtree.structure_item) ->
      match item.Typedtree.str_desc with
      | Typedtree.Tstr_type (_, ds) -> ds == decls
      | _ -> false)
    (Unit.implementation u).Typedtree.str_items

let head_is_ident tid ty =
  match Types.get_desc ty with
  | Types.Tconstr (Path.Pident id, [], _) -> Ident.same id tid
  | _ -> false

let head_is_path p ty =
  match Types.get_desc ty with
  | Types.Tconstr (q, [], _) -> Path.same q p
  | _ -> false

(* Arrow arguments are inspected through [arg_body]: since OCaml 5.5 every
   [Tarrow] argument type is a [Tpoly] node (trivial for ordinary
   arguments — types.mli pins the invariant); earlier compilers in the
   support window record the plain type. *)
let arg_body ty =
  match Types.get_desc ty with Types.Tpoly (body, _) -> body | _ -> ty

let arrow ty =
  match Types.get_desc ty with
  | Types.Tarrow (Asttypes.Nolabel, a, b, _) -> Some (arg_body a, b)
  | _ -> None

let arrow2 ty =
  match arrow ty with
  | Some (a, rest) -> (
      match arrow rest with Some (b, r) -> Some (a, b, r) | None -> None)
  | None -> None

(* Value evidence: the three shapes, checked structurally against the
   interface type's own ident — never by name alone. *)
let is_evidence tid name ty =
  match name with
  | "equal" -> (
      match arrow2 ty with
      | Some (a, b, r) ->
          head_is_ident tid a && head_is_ident tid b
          && head_is_path Predef.path_bool r
      | None -> false)
  | "compare" -> (
      match arrow2 ty with
      | Some (a, b, r) ->
          head_is_ident tid a && head_is_ident tid b
          && head_is_path Predef.path_int r
      | None -> false)
  | "to_string" -> (
      match arrow ty with
      | Some (a, r) -> head_is_ident tid a && head_is_path Predef.path_string r
      | None -> false)
  | _ -> false

let formatter = Pat.(typ "Stdlib.Format.formatter")

(* [Format.formatter -> t -> unit] exactly — a printer for another type
   that happens to be named [pp] must not count. *)
let is_printer u tid ty =
  match arrow2 ty with
  | Some (f, a, r) ->
      Pat.run formatter u f () <> None
      && head_is_ident tid a
      && head_is_path Predef.path_unit r
  | None -> false

let check u items (d : Typedtree.type_declaration) =
  let name = d.Typedtree.typ_name.Location.txt in
  let abstract_row =
    List.find_map
      (function
        | Types.Sig_type (tid, td, _, Types.Exported)
          when String.equal (Ident.name tid) name -> (
            match (td.Types.type_manifest, td.Types.type_kind) with
            | None, Types.Type_abstract _ -> Some tid
            | (None | Some _), _ -> None)
        | _ -> None)
      items
  in
  match abstract_row with
  | None -> None
  | Some tid ->
      let printer_names = [ "pp"; "pp_" ^ name ] in
      let has_evidence =
        List.exists
          (function
            | Types.Sig_value (vid, vd, Types.Exported) ->
                is_evidence tid (Ident.name vid) vd.Types.val_type
            | _ -> false)
          items
      and has_printer =
        List.exists
          (function
            | Types.Sig_value (vid, vd, Types.Exported) ->
                List.mem (Ident.name vid) printer_names
                && is_printer u tid vd.Types.val_type
            | _ -> false)
          items
      in
      if has_evidence && not has_printer then
        Some (Finding.v ~loc:d.Typedtree.typ_name.Location.loc message)
      else None

let rule =
  Rule.type_decl meta @@ fun u decls ->
  match Unit.interface u with
  | None -> []
  | Some sg ->
      if toplevel_group u decls then
        List.filter_map (check u sg.Typedtree.sig_type) decls
      else []
