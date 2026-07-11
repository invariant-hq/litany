(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-list-filter-map" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"recursive function that re-implements List.filter or filter_map"
    ~doc:
      {|The cons-or-skip list recursion — keep a (possibly transformed)
element in one branch, recurse past it in the other — re-implements
`List.filter_map`, or plain `List.filter` when the kept element is the
head unchanged.

    (* bad *)  let rec evens = function
                 | [] -> []
                 | x :: xs -> if x mod 2 = 0 then x :: evens xs
                              else evens xs
    (* good *) let evens = List.filter (fun x -> x mod 2 = 0)

Fires when the shape is proved: the two-case recursion of
manual-list-map's scaffold whose cons case is either
`if C then E :: SELF else SELF` (or mirrored) or
`match G with Some y -> y :: SELF | None -> SELF` — both branches the
identical recursion with only the bound tail advanced, the condition or
scrutinee and the kept head using neither the tail, the function, nor —
in the match form — the scrutinized list parameter (rebound at every
recursive call);
predefined `Some`/`None` identity. The message names `List.filter` when
the kept head is exactly the bound element, `List.filter_map`
otherwise. Else-branches that are not the bare recursion (take-while
shapes), match-form kept heads other than the bound option payload,
guards, user-defined constructors, and same-named outer functions
deliberately do not fire. No fix: the rewrite restructures the whole
binding.|}
    ()

let filter_message = "manual list recursion re-implements List.filter"
let filter_map_message = "manual list recursion re-implements List.filter_map"

(* Case classification as manual-list-map, additionally capturing the
   cons case's head pattern — the filter/filter_map distinction needs
   it. *)
let nil_case_v = Pat.(case pnil none enil)
let nil_case_c = Pat.(case (pvalue pnil) none enil)
let cons_case_v = Pat.(case (pcons (as__ drop) pvar) none __)
let cons_case_c = Pat.(case (pvalue (pcons (as__ drop) pvar)) none __)

let classify_v u c1 c2 =
  let is_nil c = Option.is_some (Pat.run nil_case_v u c ()) in
  let cons c = Pat.run cons_case_v u c (fun hp tl rhs -> (hp, tl, rhs)) in
  if is_nil c1 then cons c2 else if is_nil c2 then cons c1 else None

let classify_c u c1 c2 =
  let is_nil c = Option.is_some (Pat.run nil_case_c u c ()) in
  let cons c = Pat.run cons_case_c u c (fun hp tl rhs -> (hp, tl, rhs)) in
  if is_nil c1 then cons c2 else if is_nil c2 then cons c1 else None

(* The two body forms, by explicit arity — the self-call is checked
   through the arity-bounded apply views, so shapes whose self-call takes
   four or more arguments are recorded false negatives. *)

(* [subst_scrut] also returns the scrutinized parameter: the condition,
   scrutinee, and kept head must not read it — it is rebound at each
   recursive call, so a reader would compute a different value under the
   rewrite. *)
let subst_scrut params scrut tl =
  let rec go = function
    | [] -> None
    | p :: rest ->
        if Path.same scrut (Path.Pident p) then Some (Some p, tl :: rest)
        else Option.map (fun (sp, r) -> (sp, p :: r)) (go rest)
  in
  go params

(* The cons-or-skip right-hand side: an if whose one branch conses onto
   the recursion and whose other branch is the bare recursion (either
   order), or a two-case option match keeping exactly the bound payload.
   Yields the replacement's name. *)
let if_shape = Pat.(if_ __ __ (some __))
let econs_shape = Pat.(econs __ __)
let inner_match = Pat.(match_ __ (__ ^:: __ ^:: nil))
let some_case = Pat.(case (pvalue (psome pvar)) none (econs __ __))
let none_case = Pat.(case (pvalue pnone) none __)

let cons_form u ~self ~expected ~scrut_param ~tl ~head_pat rhs =
  let selfcall e = List_recursion.is_selfcall u ~self ~expected e in
  let clean e =
    (not (Pat.occurs self e))
    && (not (Pat.occurs tl e))
    && match scrut_param with Some sp -> not (Pat.occurs sp e) | None -> true
  in
  let head_is_var e =
    match Pat.run Pat.pvar u head_pat Fun.id with
    | Some x -> List_recursion.is_id u x e
    | None -> false
  in
  match Pat.run if_shape u rhs (fun c t els -> (c, t, els)) with
  | Some (c, t, els) when clean c -> (
      let kept branch other =
        match Pat.run econs_shape u branch (fun h s -> (h, s)) with
        | Some (h, s) when selfcall s && selfcall other && clean h ->
            Some (if head_is_var h then filter_message else filter_map_message)
        | Some _ | None -> None
      in
      match kept t els with Some _ as r -> r | None -> kept els t)
  | Some _ | None -> (
      match Pat.run inner_match u rhs (fun g ic1 ic2 -> (g, ic1, ic2)) with
      | Some (g, ic1, ic2) when clean g -> (
          let some_arm c = Pat.run some_case u c (fun y ey s -> (y, ey, s)) in
          let none_arm c = Pat.run none_case u c Fun.id in
          let arms =
            match (some_arm ic1, none_arm ic2) with
            | Some sa, Some na -> Some (sa, na)
            | _ -> (
                match (some_arm ic2, none_arm ic1) with
                | Some sa, Some na -> Some (sa, na)
                | _ -> None)
          in
          match arms with
          | Some ((y, ey, s), s')
            when List_recursion.is_id u y ey && selfcall s && selfcall s' ->
              Some filter_map_message
          | Some _ | None -> None)
      | Some _ | None -> None)

let rule =
  Rule.binding meta @@ fun u vb ->
  match Pat.run Pat.pvar u vb.vb_pat Fun.id with
  | None -> []
  | Some self -> (
      let shape =
        match List_recursion.cases_shape u vb.vb_expr with
        | Some (params, c1, c2) ->
            Option.map
              (fun (hp, tl, rhs) -> (Some (None, params @ [ tl ]), hp, tl, rhs))
              (classify_v u c1 c2)
        | None -> (
            match List_recursion.match_shape u vb.vb_expr with
            | Some (params, scrut, c1, c2) ->
                Option.map
                  (fun (hp, tl, rhs) ->
                    (subst_scrut params scrut tl, hp, tl, rhs))
                  (classify_c u c1 c2)
            | None -> None)
      in
      match shape with
      | Some (Some (scrut_param, expected), head_pat, tl, rhs) -> (
          match cons_form u ~self ~expected ~scrut_param ~tl ~head_pat rhs with
          | Some message -> [ Finding.v ~loc:vb.vb_pat.pat_loc message ]
          | None -> [])
      | Some (None, _, _, _) | None -> [])
