(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-guard-true" ~group:Rule.Suspicious ~since:"1.0"
    ~fix:Rule.Sometimes ~summary:"when guard that is literally true or false"
    ~doc:
      {|A guard that is literally `true` never fails: the case behaves as
if unguarded, but the `when` costs the reader a double-take and costs
the compiler its exhaustiveness analysis. A guard that is literally
`false` never succeeds: the arm is dead. Both are almost always a
leftover or an unfinished edit — suspicious-literal-condition's
rationale, relocated to guards.

    (* bad *)  match x with n when true -> n | _ -> 0
    (* good *) match x with n -> n

Fires on every case of a `match`, `function`, or `try` whose guard is
the boolean literal itself, by predefined-constructor identity, at the
guard. Real guards and named flags (`when debug`) deliberately do not
fire — there is no constant propagation — and `when true && debug` is
redundant-boolean-operator's node inside the guard. Matches carrying
effect-handler cases are refused (recorded false negative). The fix
deletes an always-true guard only on the final arm — dropping an
earlier arm's guard can render later arms warning-11 dead under
`-warn-error` — and only when the bytes after the pattern are exactly
`when` `true` with whitespace; an always-false guard never carries a
fix (deleting a dead arm is an intent decision).|}
    ()

let always_true = "this guard is always true — drop it"
let always_false = "this guard is always false: the case never matches"
let function_cases = Pat.(fun_cases drop __)
let match_cases = Pat.(match_ drop __)
let try_cases = Pat.(try_ drop __)
let lit_true = Pat.(ebool (cst true))
let lit_false = Pat.(ebool (cst false))

(* [slice_ok s] holds when [s] is exactly optional-whitespace [when]
   whitespace [true] — the guard's own last byte ends the span, so
   nothing may follow. A comment anywhere fails the walk. *)
let slice_ok s =
  let n = String.length s in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let rec skip_ws i = if i < n && is_ws s.[i] then skip_ws (i + 1) else i in
  let word w i =
    let m = String.length w in
    if i + m <= n && String.equal (String.sub s i m) w then Some (i + m)
    else None
  in
  match word "when" (skip_ws 0) with
  | None -> false
  | Some i -> (
      let j = skip_ws i in
      if j = i then false
      else match word "true" j with None -> false | Some k -> k = n)

(* The delete spans `[pattern end, guard end)`: `| p when true -> r`
   becomes `| p -> r`. Final arm only — see the rule doc. *)
let fix (type cat) u ~final (c : cat Typedtree.case) (g : Typedtree.expression)
    =
  if (not final) || Unit.preprocessed u then None
  else
    let pat_end = c.Typedtree.c_lhs.pat_loc.Location.loc_end in
    let guard_end = g.exp_loc.Location.loc_end in
    if
      c.Typedtree.c_lhs.pat_loc.Location.loc_ghost
      || g.exp_loc.Location.loc_ghost
      || pat_end.Lexing.pos_cnum < 0
      || guard_end.Lexing.pos_cnum < pat_end.Lexing.pos_cnum
    then None
    else
      let span =
        Span.v ~start:pat_end.Lexing.pos_cnum ~stop:guard_end.Lexing.pos_cnum
      in
      match Source.slice (Unit.source u) span with
      | Some bytes when slice_ok bytes ->
          Some
            (Fix.v ~applicability:Fix.Safe ~title:"drop the always-true guard"
               [ { Fix.span; text = "" } ])
      | Some _ | None -> None

let check : type cat. Unit.t -> cat Typedtree.case list -> Finding.t list =
 fun u cases ->
  let n = List.length cases in
  List.concat
    (List.mapi
       (fun i (c : cat Typedtree.case) ->
         match c.Typedtree.c_guard with
         | None -> []
         | Some g ->
             if Pat.run lit_true u g () <> None then
               [
                 Finding.v
                   ?fix:(fix u ~final:(i = n - 1) c g)
                   ~loc:g.exp_loc always_true;
               ]
             else if Pat.run lit_false u g () <> None then
               [ Finding.v ~loc:g.exp_loc always_false ]
             else [])
       cases)

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run function_cases u e Fun.id with
  | Some cs -> check u cs
  | None -> (
      match Pat.run match_cases u e Fun.id with
      | Some cs -> check u cs
      | None -> (
          match Pat.run try_cases u e Fun.id with
          | Some cs -> check u cs
          | None -> []))
