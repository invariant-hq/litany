(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

(* The manual-list-recursion scaffold shared by the five manual-list-* rules
   — one home for machinery they would otherwise copy verbatim. Each rule
   keeps its own case patterns and classification captures. *)

(* The two body forms, by explicit arity — the self-call is checked through
   the arity-bounded apply views, so shapes whose self-call takes four or
   more arguments are recorded false negatives. In the cases form the list is the implicit final argument; in
   the match form it is the scrutinized parameter. *)
(* Two spellings of the two-case list view: the value/computation case
   categories give the applications different (weak) types, exactly as the
   per-rule copies had it. *)
let cases_v = Pat.(__ ^:: __ ^:: nil)
let cases_c = Pat.(__ ^:: __ ^:: nil)
let cf0 = Pat.(fun_cases nil cases_v)
let cf1 = Pat.(fun_cases (param pvar ^:: nil) cases_v)
let cf2 = Pat.(fun_cases (param pvar ^:: param pvar ^:: nil) cases_v)
let mf1 = Pat.(fun_body (param pvar ^:: nil) (match_ var cases_c))

let mf2 =
  Pat.(fun_body (param pvar ^:: param pvar ^:: nil) (match_ var cases_c))

let mf3 =
  Pat.(
    fun_body
      (param pvar ^:: param pvar ^:: param pvar ^:: nil)
      (match_ var cases_c))

let cases_shape u body =
  match Pat.run cf0 u body (fun c1 c2 -> ([], c1, c2)) with
  | Some _ as r -> r
  | None -> (
      match Pat.run cf1 u body (fun p c1 c2 -> ([ p ], c1, c2)) with
      | Some _ as r -> r
      | None -> Pat.run cf2 u body (fun p q c1 c2 -> ([ p; q ], c1, c2)))

let match_shape u body =
  match Pat.run mf1 u body (fun p s c1 c2 -> ([ p ], s, c1, c2)) with
  | Some _ as r -> r
  | None -> (
      match Pat.run mf2 u body (fun p q s c1 c2 -> ([ p; q ], s, c1, c2)) with
      | Some _ as r -> r
      | None ->
          Pat.run mf3 u body (fun p q r s c1 c2 -> ([ p; q; r ], s, c1, c2)))

let app1 = Pat.(apply __ (__ ^:: nil))
let app2 = Pat.(apply __ (__ ^:: __ ^:: nil))
let app3 = Pat.(apply __ (__ ^:: __ ^:: __ ^:: nil))

let split_apply u e =
  match Pat.run app1 u e (fun f a -> (f, [ a ])) with
  | Some _ as r -> r
  | None -> (
      match Pat.run app2 u e (fun f a b -> (f, [ a; b ])) with
      | Some _ as r -> r
      | None -> Pat.run app3 u e (fun f a b c -> (f, [ a; b; c ])))

let is_id u id e =
  match Pat.run Pat.var u e Fun.id with
  | Some p -> Path.same p (Path.Pident id)
  | None -> false

(* The recursive call: callee resolving to the bound function itself —
   identity, so a same-named outer function refuses — applied to exactly
   the expected idents. *)
let is_selfcall u ~self ~expected e =
  match split_apply u e with
  | Some (callee, args) ->
      is_id u self callee
      && List.length args = List.length expected
      && List.for_all2 (fun id a -> is_id u id a) expected args
  | None -> false

let index_of params path =
  let rec go i = function
    | [] -> None
    | p :: rest ->
        if Path.same path (Path.Pident p) then Some i else go (i + 1) rest
  in
  go 0 params

let classify ~nil ~cons u c1 c2 =
  let is_nil c = Pat.run nil u c () in
  let cons c = Pat.run cons u c (fun tl rhs -> (tl, rhs)) in
  match is_nil c1 with
  | Some () -> cons c2
  | None -> ( match is_nil c2 with Some () -> cons c1 | None -> None)
