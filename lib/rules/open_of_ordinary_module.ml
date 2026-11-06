(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"open-of-ordinary-module" ~group:Rule.Restriction
    ~stability:Rule.Stability.Nursery ~since:"1.1" ~fix:Rule.Never
    ~summary:"an open of a module that is not made to be opened"
    ~doc:
      {|An `open` of an ordinary module makes every name of the file a
question -- where did it come from? -- and a name the module gains later
silently shadows one of the file's own. A module made to be opened is
one of binding operators and nothing else (`open Result.Syntax`).

    (* bad *)  open Store
    (* good *) module S = Store

Why restrict this? `open` is idiomatic OCaml in many houses; aliasing
every module instead is a discipline a house adopts.

Fires at an `open` that is a structure item, at the root of a unit or
in a nested structure, through which the unit takes anything but
binding operators (`let*`, `and+`, ...) -- a value, a type, a constructor,
a record field or a member of a submodule -- or takes nothing at all. A
name written out in full is not taken through the open. An `open` of a module of binding
operators alone, and an `open` local to an expression -- `let open M in
e` or `M.(e)`, where a library of combinators or operators is opened
around the expression that uses it -- deliberately do not fire. No fix:
an alias names the module, and every use changes with it.|}
    ()

(* A binding operator's name: [let] or [and], then an operator's
   characters. *)
let binding_operator name =
  let operator = function
    | '$' | '&' | '*' | '+' | '-' | '/' | '<' | '=' | '>' | '@' | '^' | '|'
    | '%' | '!' | '.' | ':' | '?' | '~' ->
        true
    | _ -> false
  in
  let rest prefix =
    String.length name > String.length prefix
    && String.starts_with ~prefix name
    && String.for_all operator
         (String.sub name (String.length prefix)
            (String.length name - String.length prefix))
  in
  rest "let" || rest "and"

(* The module a name is written in: [M] of [M.x], and [None] for a bare [x], a
   name that can only have come through an open. *)
let rec written_module (lid : Longident.t) =
  match lid with
  | Lident _ | Lapply _ -> None
  | Ldot (m, _) -> Some (module_name m.txt)

and module_name (lid : Longident.t) =
  match lid with
  | Lident name -> name
  | Ldot (m, name) -> module_name m.txt ^ "." ^ name.txt
  | Lapply (f, _) -> module_name f.txt

(* The names the unit takes through [path]: an opened module's values,
   types and constructors are elaborated in the typed tree to their full
   paths, [M.name], and a [.cmt] holds no signature to read instead. A use
   spelled in full elaborates alike, so its spelling tells them apart. *)
let names_through path ~spelled (str : Typedtree.structure) =
  let names = ref [] in
  let rec take p =
    match p with
    | Path.Pdot (prefix, name) ->
        if Path.same prefix path then names := name :: !names else take prefix
    | _ -> ()
  in
  let spelled_in_full (lid : Longident.t) =
    match written_module lid with
    | Some written ->
        String.equal written spelled
        || String.starts_with ~prefix:(spelled ^ ".") written
    | None -> false
  in
  let through (lid : Longident.t Location.loc) p =
    if not (spelled_in_full lid.txt) then take p
  in
  let result_path (ty : Types.type_expr) =
    match Types.get_desc ty with Tconstr (p, _, _) -> Some p | _ -> None
  in
  let through_result lid ty = Option.iter (through lid) (result_path ty) in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      expr =
        (fun sub (e : Typedtree.expression) ->
          (match e.exp_desc with
          | Texp_ident (p, lid, _) -> through lid p
          | Texp_construct (lid, cd, _) -> through_result lid cd.cstr_res
          | Texp_field (_, lid, label) | Texp_setfield (_, lid, label, _) ->
              through_result lid label.lbl_res
          | Texp_record { fields; _ } ->
              Array.iter
                (fun ((label : Data_types.label_description), definition) ->
                  match (definition : Typedtree.record_label_definition) with
                  | Overridden (lid, _) -> through_result lid label.lbl_res
                  | Kept _ -> ())
                fields
          | Texp_letop { let_; ands; _ } ->
              List.iter
                (fun (b : Typedtree.binding_op) -> take b.bop_op_path)
                (let_ :: ands)
          | _ -> ());
          default.expr sub e);
      pat =
        (fun (type k) sub (p : k Typedtree.general_pattern) ->
          (match p.pat_desc with
          | Tpat_construct (lid, cd, _, _) -> through_result lid cd.cstr_res
          | Tpat_record (fields, _) ->
              List.iter
                (fun (lid, (label : Data_types.label_description), _) ->
                  through_result lid label.lbl_res)
                fields
          | _ -> ());
          default.pat sub p);
      typ =
        (fun sub (t : Typedtree.core_type) ->
          (match t.ctyp_desc with
          | Ttyp_constr (p, lid, _) -> through lid p
          | _ -> ());
          default.typ sub t);
    }
  in
  iterator.structure iterator str;
  !names

let made_to_be_opened u (od : Typedtree.open_declaration) =
  match od.open_expr.mod_desc with
  | Tmod_ident (path, lid) -> (
      let spelled = module_name lid.txt in
      match names_through path ~spelled (Unit.implementation u) with
      | [] -> false
      | names -> List.for_all binding_operator names)
  | _ -> false

let rule =
  Rule.open_ meta @@ fun u (od : Typedtree.open_declaration) ->
  if made_to_be_opened u od then []
  else
    [
      Finding.v ~loc:od.open_loc
        "an open of a module not made to be opened: alias it, module M = ...";
    ]
