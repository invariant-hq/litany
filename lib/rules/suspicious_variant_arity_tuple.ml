(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-variant-arity-tuple" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"constructor whose one argument is a parenthesized tuple"
    ~doc:
      {|`C of int * int` declares a two-field constructor — one block,
fields inline. `C of (int * int)` declares a one-field constructor
whose field is a boxed tuple — an extra allocation and an extra
indirection on every construction and every match, invisible at most
use sites because the pattern `C (x, y)` happens to typecheck against
both.

    (* bad *)  type t = Pair of (int * int)
    (* good *) type t = Pair of int * int
    (* good *) type point = int * int
               type t = Pair of point

Fires once per constructor whose argument list is exactly one
parenthesized tuple type, at that type — GADT constructors included:
`B : (int * int) -> t` draws the same representation line as
`D of (int * int)`. Declarations under `[@@unboxed]` are exempt (the
attribute requires the single-argument form, so the boxing complaint
is void), as is a tuple among several fields (`C of (int * int) *
string` has no flat spelling — the parentheses are load-bearing) and a
named tuple type (`C of point` — the sanctioned spelling when the
tuple-as-one-value is the choice). No fix: flattening changes the
runtime representation and breaks every `C p`-as-value use site; the
remedy is a decision, stated in the message.|}
    ()

let message name =
  Printf.sprintf
    "%s of (a * b) declares one boxed tuple field — %s of a * b declares two \
     inline fields; name the tuple type if the boxing is deliberate"
    name name

let unboxed (attrs : Parsetree.attributes) =
  List.exists
    (fun (a : Parsetree.attribute) ->
      String.equal a.attr_name.txt "unboxed"
      || String.equal a.attr_name.txt "ocaml.unboxed")
    attrs

(* The tuple payload is wildcarded: the component list is labeled from
   5.4 and this rule never reads it, so the match is source-stable
   across the window. *)
let decl_findings (d : Typedtree.type_declaration) =
  match d.typ_kind with
  | Typedtree.Ttype_variant cds when not (unboxed d.typ_attributes) ->
      List.filter_map
        (fun (cd : Typedtree.constructor_declaration) ->
          match cd.cd_args with
          | Typedtree.Cstr_tuple [ ct ] -> (
              match ct.ctyp_desc with
              | Typedtree.Ttyp_tuple _ ->
                  Some (Finding.v ~loc:ct.ctyp_loc (message cd.cd_name.txt))
              | _ -> None)
          | _ -> None)
        cds
  | _ -> []

let rule = Rule.type_decl meta @@ fun _u ds -> List.concat_map decl_findings ds
