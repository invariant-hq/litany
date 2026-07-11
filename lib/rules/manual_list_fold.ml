(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-list-fold" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"recursive function that re-implements a List fold"
    ~doc:
      {|A recursive function with an accumulator whose body is the two-case
list recursion returning the accumulator on `[]` re-implements
`List.fold_left` (accumulator transformed, tail call in tail position)
or `List.fold_right` (result rebuilt around the recursive call,
accumulator threaded unchanged).

    (* bad *)  let rec sum acc = function
                 | [] -> acc
                 | x :: xs -> sum (acc + x) xs
    (* good *) let sum acc = List.fold_left ( + ) acc

Fires when either shape is proved — the nil case returning one of the
parameters (that parameter is the accumulator), and the cons case
either the tail call with only the accumulator position transformed
(fold_left) or one self-call with every parameter unchanged inside a
step that touches neither the function nor the tail (fold_right); in
the match form the step must not read the scrutinized list parameter
either — it is rebound at every recursive call, so no fold callback
can see it. The message names the replacement. The step may be any
expression — an operator, not just an applied parameter. Nil cases
returning a literal
(no accumulator parameter to keep the signature), changed-and-wrapped
accumulators, two self-calls, guarded or extra cases, user-defined
`(::)`/`[]`, and same-named outer functions deliberately do not fire.
No fix: the rewrite restructures the whole binding.|}
    ()

let fold_left_message = "manual list recursion re-implements List.fold_left"
let fold_right_message = "manual list recursion re-implements List.fold_right"

(* Case classification: `[] -> acc` (the nil right-hand side must be a
   bare identifier — its path designates the accumulator) and
   `_ :: tl -> RHS`, captured raw and classified per case so both orders
   share one shape. *)
let nil_case_v = Pat.(case pnil none var)
let nil_case_c = Pat.(case (pvalue pnil) none var)
let cons_case_v = Pat.(case (pcons drop pvar) none __)
let cons_case_c = Pat.(case (pvalue (pcons drop pvar)) none __)

let classify_v u c1 c2 =
  let nil c = Pat.run nil_case_v u c Fun.id in
  let cons c = Pat.run cons_case_v u c (fun tl rhs -> (tl, rhs)) in
  match nil c1 with
  | Some acc -> Option.map (fun (tl, rhs) -> (acc, tl, rhs)) (cons c2)
  | None -> (
      match nil c2 with
      | Some acc -> Option.map (fun (tl, rhs) -> (acc, tl, rhs)) (cons c1)
      | None -> None)

let classify_c u c1 c2 =
  let nil c = Pat.run nil_case_c u c Fun.id in
  let cons c = Pat.run cons_case_c u c (fun tl rhs -> (tl, rhs)) in
  match nil c1 with
  | Some acc -> Option.map (fun (tl, rhs) -> (acc, tl, rhs)) (cons c2)
  | None -> (
      match nil c2 with
      | Some acc -> Option.map (fun (tl, rhs) -> (acc, tl, rhs)) (cons c1)
      | None -> None)

(* The two body forms, by explicit arity — the self-call is checked
   through the arity-bounded apply views, so shapes whose self-call takes
   four or more arguments are recorded false negatives. *)

(* [clean] — the step expression must read neither the function nor the
   bound tail, nor (match form) the scrutinized list parameter, which is
   rebound at each recursive call — a step reading it would compute a
   different value under the fold form. *)
let clean ~self ~tl ~scrut_param e =
  (not (Pat.occurs self e))
  && (not (Pat.occurs tl e))
  && match scrut_param with Some sp -> not (Pat.occurs sp e) | None -> true

(* [List_recursion.index_of params path] is the position [path] designates among the
   explicit parameters, if any. *)

(* fold_left: the self-call in tail position — every parameter its own
   ident except the accumulator position, which holds the step; the list
   position (scrutinized parameter, or the appended final argument in the
   cases form) holds the bound tail. The step may be any expression using
   neither the function nor the tail. *)
let fold_left_ok u ~self ~params ~acc_idx ~list_idx ~scrut_param ~tl rhs =
  match List_recursion.split_apply u rhs with
  | Some (callee, args) when List_recursion.is_id u self callee ->
      let n = List.length params in
      let expected_len = match list_idx with None -> n + 1 | Some _ -> n in
      List.length args = expected_len
      && List.for_all
           (fun (i, a) ->
             if list_idx = Some i || i >= n then List_recursion.is_id u tl a
             else if i = acc_idx then clean ~self ~tl ~scrut_param a
             else List_recursion.is_id u (List.nth params i) a)
           (List.mapi (fun i a -> (i, a)) args)
  | Some _ | None -> false

(* fold_right: the right-hand side is one application whose exactly-one
   self-call argument keeps every parameter — accumulator included — and
   steps only the list; the callee and sibling arguments touch neither
   the function nor the tail. Matched one application deep: a self-call
   nested further inside the step is a recorded false negative. *)
let fold_right_ok u ~self ~expected ~scrut_param ~tl rhs =
  match List_recursion.split_apply u rhs with
  | Some (callee, args) when clean ~self ~tl ~scrut_param callee ->
      let selfcalls, others =
        List.partition (List_recursion.is_selfcall u ~self ~expected) args
      in
      List.length selfcalls = 1
      && List.for_all (clean ~self ~tl ~scrut_param) others
  | Some _ | None -> false

let rule =
  Rule.binding meta @@ fun u vb ->
  match Pat.run Pat.pvar u vb.vb_pat Fun.id with
  | None -> []
  | Some self -> (
      let shape =
        match List_recursion.cases_shape u vb.vb_expr with
        | Some (params, c1, c2) ->
            Option.map
              (fun (acc, tl, rhs) -> (params, None, acc, tl, rhs))
              (classify_v u c1 c2)
        | None -> (
            match List_recursion.match_shape u vb.vb_expr with
            | Some (params, scrut, c1, c2) ->
                Option.map
                  (fun (acc, tl, rhs) -> (params, Some scrut, acc, tl, rhs))
                  (classify_c u c1 c2)
            | None -> None)
      in
      match shape with
      | None -> []
      | Some (params, scrut, acc_path, tl, rhs) -> (
          (* The nil case must return a parameter (the accumulator), and
             in the match form the scrutinized list must be a distinct
             parameter — an accumulator that is also the list has no
             faithful fold rewrite. *)
          match List_recursion.index_of params acc_path with
          | None -> []
          | Some acc_idx -> (
              let list_idx =
                match scrut with
                | None -> Some None
                | Some s -> (
                    match List_recursion.index_of params s with
                    | Some k when k <> acc_idx -> Some (Some k)
                    | Some _ | None -> None)
              in
              match list_idx with
              | None -> []
              | Some list_idx ->
                  let scrut_param =
                    Option.map (fun k -> List.nth params k) list_idx
                  in
                  if
                    fold_left_ok u ~self ~params ~acc_idx ~list_idx ~scrut_param
                      ~tl rhs
                  then [ Finding.v ~loc:vb.vb_pat.pat_loc fold_left_message ]
                  else
                    let expected =
                      match list_idx with
                      | None -> params @ [ tl ]
                      | Some k ->
                          List.mapi (fun i p -> if i = k then tl else p) params
                    in
                    if fold_right_ok u ~self ~expected ~scrut_param ~tl rhs then
                      [ Finding.v ~loc:vb.vb_pat.pat_loc fold_right_message ]
                    else [])))
