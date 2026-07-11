(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The [Scope.matches_type] local-alias hop, proved against a compiled
   fixture: a unit-local functor instance and a plain module alias resolve
   to their canonical types under a scope carrying the unit's own
   signature as [local] ([Scope.v]); an ascription resolves exactly as its
   written signature does — a named module type carries that module type's
   interface UIDs (a [Map.S]-ascribed instance still matches
   [Stdlib.Map.Make.t], truthfully: [S] is [Make]'s own result signature),
   an inline signature mints unit-local identities that match no canonical
   name; an empty [local] keeps the pre-hop behavior. *)

open Windtrap
module Resolver = Litany.Naming.Resolver
module Scope = Litany.Naming.Scope
module Name = Litany.Naming.Name

let cmt_path = "fixtures/.fix_hop.objs/byte/fix_hop.cmt"
let shadow_cmt_path = "fixtures/.fix_hop.objs/byte/fix_hop__Fix_shadow.cmt"

let name s =
  match Name.of_string s with
  | Ok n -> n
  | Error _ -> failwith ("malformed canonical name " ^ s)

let structure_of path =
  let infos = Cmt_format.read_cmt path in
  match infos.Cmt_format.cmt_annots with
  | Cmt_format.Implementation str -> str
  | _ -> failwith "fixture cmt is not an implementation"

let structure () = structure_of cmt_path

(* [type_head str key] is the head [Tconstr] path of the inferred type of
   the identifier use spelled [key] — the path a type use site carries,
   which [matches_type] consumes. *)
let type_head str key =
  let found = ref None in
  let iter =
    let open Tast_iterator in
    {
      default_iterator with
      expr =
        (fun sub expr ->
          (match expr.Typedtree.exp_desc with
          | Typedtree.Texp_ident (path, _, _)
            when String.equal (Path.name path) key -> (
              match Types.get_desc expr.Typedtree.exp_type with
              | Types.Tconstr (head, _, _) -> found := Some head
              | _ -> ())
          | _ -> ());
          default_iterator.expr sub expr);
    }
  in
  iter.structure iter str;
  match !found with
  | Some head -> head
  | None -> failwith ("no constructor-typed use site for " ^ key)

let scope local =
  let resolver = Resolver.create ~cmi_dirs:[ Config.standard_library ] in
  Scope.v ~resolver ~intra:(fun _ -> []) ~local

let () =
  Windtrap.run "matches_type local-alias hop"
    [
      test "a unit-local functor instance resolves through the hop" (fun () ->
          let str = structure () in
          let sc = scope str.Typedtree.str_type in
          let sm = type_head str "SM.empty" in
          is_true ~msg:"SM.t is Stdlib.Map.Make.t under the hop"
            (Scope.matches_type sc (name "Stdlib.Map.Make.t") sm);
          is_false ~msg:"SM.t is not Stdlib.Set.Make.t"
            (Scope.matches_type sc (name "Stdlib.Set.Make.t") sm);
          is_false ~msg:"under an empty [local] the head stays unresolved"
            (Scope.matches_type (scope []) (name "Stdlib.Map.Make.t") sm);
          let is_head = type_head str "IS.empty" in
          is_true ~msg:"IS.t is Stdlib.Set.Make.t under the hop"
            (Scope.matches_type sc (name "Stdlib.Set.Make.t") is_head));
      test "a plain module alias resolves through the hop" (fun () ->
          let str = structure () in
          let sc = scope str.Typedtree.str_type in
          let h = type_head str "h_probe" in
          is_true ~msg:"H.t is Stdlib.Hashtbl.t under the hop"
            (Scope.matches_type sc (name "Stdlib.Hashtbl.t") h));
      test "an ascription resolves as its written signature" (fun () ->
          let str = structure () in
          let sc = scope str.Typedtree.str_type in
          let am = type_head str "AM.empty" in
          is_true
            ~msg:
              "a Map.S-ascribed instance carries S's interface UIDs and matches"
            (Scope.matches_type sc (name "Stdlib.Map.Make.t") am);
          let opaque = type_head str "Opaque.empty" in
          is_false ~msg:"an inline-signature ascription stays unmatched"
            (Scope.matches_type sc (name "Stdlib.Map.Make.t") opaque);
          is_false ~msg:"nor is it any other canonical type"
            (Scope.matches_type sc (name "Stdlib.Hashtbl.t") opaque));
      test "same-name shadowed bindings resolve by ident, not name" (fun () ->
          (* [include] keeps both an included [M = Hashtbl] and a
             later explicit [M = Set.Make (Int)] in [str_type]. A first-hit
             name lookup read the shadowed binding's identity — the second
             M's use matched [Stdlib.Hashtbl.t] (FP) and missed
             [Stdlib.Set.Make.t] (FN). The hop resolves the [Pident] head
             by [Ident.same], so each use matches exactly its binding. *)
          let str = structure_of shadow_cmt_path in
          let sc = scope str.Typedtree.str_type in
          let first = type_head str "first_probe" in
          let second = type_head str "second_probe" in
          is_true ~msg:"the first M's use is Stdlib.Hashtbl.t"
            (Scope.matches_type sc (name "Stdlib.Hashtbl.t") first);
          is_false ~msg:"the first M's use is not Stdlib.Set.Make.t"
            (Scope.matches_type sc (name "Stdlib.Set.Make.t") first);
          is_true ~msg:"the second M's use is Stdlib.Set.Make.t"
            (Scope.matches_type sc (name "Stdlib.Set.Make.t") second);
          is_false ~msg:"the second M's use is NOT Stdlib.Hashtbl.t"
            (Scope.matches_type sc (name "Stdlib.Hashtbl.t") second));
    ]
