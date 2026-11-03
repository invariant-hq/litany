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
one of binding operators and nothing else (`open Spindle.Syntax`).
Holds Hypha's `OCAML.md`, *No `open` of an ordinary module*.

    (* bad *)  open Store
    (* good *) module S = Store

Why restrict this? `open` is idiomatic OCaml in many houses; aliasing
every module instead is a discipline a house adopts.

Fires at an `open` that is a structure item, at the root of a unit or
in a nested structure, through which the unit takes anything but
binding operators (`let*`, `and+`, ...) -- a value, a type or a
constructor -- or takes nothing at all. An `open` of a module of binding
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

(* The names the unit takes through [path]: an opened module's values,
   types and constructors are elaborated in the typed tree to their full
   paths, [M.name], and a [.cmt] holds no signature to read instead. *)
let names_through path (str : Typedtree.structure) =
  let names = ref [] in
  let through p =
    match p with
    | Path.Pdot (prefix, name) when Path.same prefix path ->
        names := name :: !names
    | _ -> ()
  in
  let rec type_path (ty : Types.type_expr) =
    match Types.get_desc ty with
    | Tconstr (p, _, _) -> through p
    | Tarrow (_, a, b, _) ->
        type_path a;
        type_path b
    | _ -> ()
  in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      expr =
        (fun sub (e : Typedtree.expression) ->
          (match e.exp_desc with
          | Texp_ident (p, _, _) -> through p
          | Texp_construct (_, cd, _) -> type_path cd.cstr_res
          | Texp_letop { let_; ands; _ } ->
              List.iter
                (fun (b : Typedtree.binding_op) -> through b.bop_op_path)
                (let_ :: ands)
          | _ -> ());
          default.expr sub e);
      typ =
        (fun sub (t : Typedtree.core_type) ->
          (match t.ctyp_desc with
          | Ttyp_constr (p, _, _) -> through p
          | _ -> ());
          default.typ sub t);
    }
  in
  iterator.structure iterator str;
  !names

let made_to_be_opened u (od : Typedtree.open_declaration) =
  match od.open_expr.mod_desc with
  | Tmod_ident (path, _) -> (
      match names_through path (Unit.implementation u) with
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
