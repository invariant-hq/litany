(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-list-map" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"recursive function that hand-rolls a list map"
    ~doc:
      {|A recursive function whose body is exactly the two-case list
recursion `[] -> []` / `x :: xs -> E :: self … xs` re-implements
`List.map (fun x -> E)`: more code, no TRMC, and a reader must
re-verify that the recursion is structural.

    (* bad *)  let rec map1 f = function
                 | [] -> []
                 | h :: tl -> f h :: map1 f tl
    (* good *) let map1 f = List.map f

Fires when the whole shape is proved: the binding is a variable, every
parameter an unlabeled variable, the two cases guard-less with
predefined `[]`/`(::)` identity, every parameter passed through the
recursion unchanged with the bound tail in the list position (any
parameter position), and the head expression using neither the tail, the
function itself, nor — in the match form — the scrutinized list
parameter, which is rebound at every recursive call and so denotes a
different list per iteration. Guarded or extra cases, alias patterns,
heads that read the tail or the scrutinized list, arguments other than
the bound tail, user-defined
`(::)`/`[]` constructors, and same-named outer functions (identity, not
spelling) deliberately do not fire. No fix: the rewrite restructures
the whole binding; the message names the replacement.|}
    ()

let message = "manual list recursion hand-rolls List.map"

(* Case classification: `[] -> []` and `_ :: tl -> E_h :: R`, captured
   raw as a two-case list and classified per case so both orders share
   one shape. Value cases serve the `function` form, computation cases
   the `match` form. *)
let nil_case_v = Pat.(case pnil none enil)
let nil_case_c = Pat.(case (pvalue pnil) none enil)
let cons_case_v = Pat.(case (pcons drop pvar) none (econs __ __))
let cons_case_c = Pat.(case (pvalue (pcons drop pvar)) none (econs __ __))

let classify_v u c1 c2 =
  let is_nil c = Option.is_some (Pat.run nil_case_v u c ()) in
  let cons c = Pat.run cons_case_v u c (fun tl head call -> (tl, head, call)) in
  if is_nil c1 then cons c2 else if is_nil c2 then cons c1 else None

let classify_c u c1 c2 =
  let is_nil c = Option.is_some (Pat.run nil_case_c u c ()) in
  let cons c = Pat.run cons_case_c u c (fun tl head call -> (tl, head, call)) in
  if is_nil c1 then cons c2 else if is_nil c2 then cons c1 else None

(* The two body forms, by explicit arity — the self-call is checked
   through the arity-bounded apply views, so shapes whose self-call
   takes four or more arguments are recorded false negatives. In the
   cases form the list is the
   implicit final argument; in the match form it is the scrutinized
   parameter. *)

(* The recursive call: callee resolving to the bound function itself —
   identity, so a same-named outer function refuses — applied to exactly
   the expected idents. *)

(* [subst_scrut params scrut tl] is the scrutinized parameter and the
   expected argument list of the match form — each parameter's own ident
   with the scrutinized position replaced by the bound tail — when the
   scrutinee is one of [params]. The scrutinized parameter comes back
   because the head must not read it: it is rebound at each recursive
   call, so a head using it is not the mapped expression and the map
   form would compute a different value. *)
let subst_scrut params scrut tl =
  let rec go = function
    | [] -> None
    | p :: rest ->
        if Path.same scrut (Path.Pident p) then Some (p, tl :: rest)
        else Option.map (fun (sp, r) -> (sp, p :: r)) (go rest)
  in
  go params

let rule =
  Rule.binding meta @@ fun u vb ->
  match Pat.run Pat.pvar u vb.vb_pat Fun.id with
  | None -> []
  | Some self -> (
      let shape =
        match List_recursion.cases_shape u vb.vb_expr with
        | Some (params, c1, c2) ->
            Option.map
              (fun (tl, head, call) -> (params @ [ tl ], None, tl, head, call))
              (classify_v u c1 c2)
        | None -> (
            match List_recursion.match_shape u vb.vb_expr with
            | Some (params, scrut, c1, c2) -> (
                match classify_c u c1 c2 with
                | Some (tl, head, call) ->
                    Option.map
                      (fun (sp, expected) ->
                        (expected, Some sp, tl, head, call))
                      (subst_scrut params scrut tl)
                | None -> None)
            | None -> None)
      in
      match shape with
      | Some (expected, scrut_param, tl, head, call)
        when List_recursion.is_selfcall u ~self ~expected call
             && (not (Pat.occurs self head))
             && (not (Pat.occurs tl head))
             && not
                  (match scrut_param with
                  | Some sp -> Pat.occurs sp head
                  | None -> false) ->
          [ Finding.v ~loc:vb.vb_pat.pat_loc message ]
      | Some _ | None -> [])
