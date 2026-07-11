(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-list-exists" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"recursive function that re-implements List.exists"
    ~doc:
      {|A recursive function whose body is the two-case list recursion
returning `false` on `[]` and `E || self … tl` on cons re-implements
`List.exists (fun x -> E)`: same left-to-right evaluation, same
short-circuit on the first `true`, same effect order when `E` is
effectful — and `List.exists` says what it does.

    (* bad *)  let rec has p = function
                 | [] -> false
                 | x :: xs -> p x || has p xs
    (* good *) let has p = List.exists p

Fires when the shape is proved: exactly two guard-less cases by
predefined-list identity, the nil case the literal `false`, and the
cons case `E || SELFCALL` where the step `E` uses neither the function
nor the bound tail and the self-call passes every parameter unchanged
with the bound tail in list position. A self-call left of `||`
(evaluation order differs), a `true` nil case (constant, not exists),
a same-named outer function without `rec`, a recursion argument other
than the bound tail, guards, extra cases, and user-defined `(::)`/`[]`
deliberately do not fire. The `if p x then true else self xs` spelling
is redundant-if-bool's inner `if`. No fix: the rewrite restructures
the whole binding.|}
    ()

let message = "manual list recursion re-implements List.exists"

(* Case classification: `[] -> false` (the nil right-hand side must be
   the predefined literal) and `_ :: tl -> RHS`, captured raw and
   classified per case so both orders share one shape. *)
let nil_case_v = Pat.(case pnil none (ebool (cst false)))
let nil_case_c = Pat.(case (pvalue pnil) none (ebool (cst false)))
let cons_case_v = Pat.(case (pcons drop pvar) none __)
let cons_case_c = Pat.(case (pvalue (pcons drop pvar)) none __)

let classify_v u c1 c2 =
  List_recursion.classify ~nil:nil_case_v ~cons:cons_case_v u c1 c2

let classify_c u c1 c2 =
  List_recursion.classify ~nil:nil_case_c ~cons:cons_case_c u c1 c2

(* The two body forms, by explicit arity — the self-call is checked
   through the arity-bounded apply views, so shapes whose self-call takes
   four or more arguments are recorded false negatives. *)

(* Cons right-hand side: `E || SELFCALL`, the step strictly left — a
   self-call left of `||` evaluates before the head's test and is a
   recorded false negative, deliberately. *)
let step_or_call = Pat.(apply (ident "Stdlib.(||)") (__ ^:: __ ^:: nil))

(* [List_recursion.index_of params path] is the position [path] designates among the
   explicit parameters, if any. *)

let rule =
  Rule.binding meta @@ fun u vb ->
  match Pat.run Pat.pvar u vb.vb_pat Fun.id with
  | None -> []
  | Some self -> (
      let shape =
        match List_recursion.cases_shape u vb.vb_expr with
        | Some (params, c1, c2) ->
            Option.map
              (fun (tl, rhs) -> (params, None, tl, rhs))
              (classify_v u c1 c2)
        | None -> (
            match List_recursion.match_shape u vb.vb_expr with
            | Some (params, scrut, c1, c2) ->
                Option.map
                  (fun (tl, rhs) -> (params, Some scrut, tl, rhs))
                  (classify_c u c1 c2)
            | None -> None)
      in
      match shape with
      | None -> []
      | Some (params, scrut, tl, rhs) -> (
          (* In the match form the scrutinized list must itself be a
             parameter — its position is where the self-call threads the
             bound tail. The cases form appends the tail as the implicit
             final argument. *)
          let expected =
            match scrut with
            | None -> Some (params @ [ tl ])
            | Some s ->
                Option.map
                  (fun k ->
                    List.mapi (fun i p -> if i = k then tl else p) params)
                  (List_recursion.index_of params s)
          in
          match expected with
          | None -> []
          | Some expected ->
              let ok =
                Pat.run step_or_call u rhs (fun step call ->
                    (not (Pat.occurs self step))
                    && (not (Pat.occurs tl step))
                    && List_recursion.is_selfcall u ~self ~expected call)
              in
              if ok = Some true then
                [ Finding.v ~loc:vb.vb_pat.pat_loc message ]
              else []))
