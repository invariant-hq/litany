(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-match-bool" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes ~summary:"boolean match interrupting an if/else chain"
    ~doc:
      {|A two-case match on a boolean — `match e with true -> a | false ->
b`, or the `function` form — is `if`/`else` in longhand. Standalone,
that longhand is a deliberate house style in wide use (cmdliner's
whole surface, sexplib0's parsers, ppxlib's printers) and is left
alone. What this rule reports is the boolean match that interrupts an
if/else cascade: one sitting as the `else` continuation of an
enclosing `if`, or whose own arms continue into `if`/`else` — there
the switch of form buries one branch of a multi-way decision, and
`if` keeps the cascade in one shape.

    (* bad *)  if p then x else match c with true -> a | false -> b
    (* good *) if p then x else if c then a else b

Fires on exactly two guard-less cases whose patterns are the boolean
literals (predefined-constructor identity) covering `true` and `false`
in either order, in both the `match` and the `function` form — and
only in the cascade positions: the match is an `else` branch, or an
arm's body is itself an `if`/`else` (the `function` form, never a
branch of an enclosing `if`, fires on the arm shape alone). A
standalone two-case boolean match never fires: the house styles are
recorded negatives. Guards, extra or wildcard cases, `exception` cases
(the `if` rewrite would change semantics), user-defined two-constructor
variants, and matches carrying effect handlers deliberately do not
fire. The fix rewrites the match form to `if`/`else` (the `function`
form has no scrutinee to build the condition from and ships none); it
applies only when the scrutinee's and both arms' source slices cleanly
(`Unit.splice`).|}
    ()

let message = "two-case match on a boolean is an if-then-else in longhand"

(* Two run-separate patterns rather than one [|||]: the capture order is
   positional, so the false-first form must reorder its arms in its own
   continuation. *)
let match_true_first =
  Pat.(
    match_ __
      (case (pvalue (pbool true)) none __
      ^:: case (pvalue (pbool false)) none __
      ^:: nil))

let match_false_first =
  Pat.(
    match_ __
      (case (pvalue (pbool false)) none __
      ^:: case (pvalue (pbool true)) none __
      ^:: nil))

(* A hit is (scrutinee, true-arm, false-arm) — positionally normalized. *)
let bool_match u e =
  match Pat.run match_true_first u e (fun c t f -> (c, t, f)) with
  | Some _ as h -> h
  | None -> Pat.run match_false_first u e (fun c f t -> (c, t, f))

let is_if (e : Typedtree.expression) =
  match e.Typedtree.exp_desc with
  | Typedtree.Texp_ifthenelse _ -> true
  | _ -> false

(* The cascade gate's arm half: an arm that is itself an [if]/[else]
   continues the chain through the match. *)
let arms_continue (_, t, f) = is_if t || is_if f

(* The cascade gate's position half: any [if] with an [else] branch —
   when that branch is a bool match, the match interrupts the chain. *)
let else_arm = Pat.(if_ drop drop (some __))

(* The function form captures its first case's pattern: when the merged
   `let f x = function …` sugar leaves the function expression with a
   ghost location (the parser's choice), the finding anchors there
   instead. Arm results are captured for the cascade gate. *)
let function_form =
  Pat.(
    fun_cases drop
      (case (as__ (pbool true)) none __ ^:: case (pbool false) none __ ^:: nil
      ||| case (as__ (pbool false)) none __
          ^:: case (pbool true) none __
          ^:: nil))

let report u (m : Typedtree.expression) (c, t, f) =
  let fix =
    match (Unit.splice u c, Unit.splice u t, Unit.splice u f) with
    | Some c, Some t, Some f ->
        Some
          (Fix.safe_replace m.Typedtree.exp_loc
             (Unit.delimited u m
                (String.concat "" [ "if "; c; " then "; t; " else "; f ]))
             ~title:"rewrite as if-then-else")
    | _ -> None
  in
  [ Finding.v ?fix ~loc:m.Typedtree.exp_loc message ]

(* Each visited expression fires through exactly one door: a bool match
   with cascading arms fires at its own visit; a plain bool match fires
   at its enclosing [if]'s visit when it is the [else] branch (the
   [arms_continue] re-check keeps the two doors disjoint); the function
   form fires on its arm shape alone. *)
let rule =
  Rule.expr meta @@ fun u e ->
  match bool_match u e with
  | Some hit when arms_continue hit -> report u e hit
  | Some _ -> []
  | None -> (
      match Pat.run else_arm u e Fun.id with
      | Some else_e -> (
          match bool_match u else_e with
          | Some hit when not (arms_continue hit) -> report u else_e hit
          | _ -> [])
      | None -> (
          match Pat.run function_form u e (fun p t f -> (p, t, f)) with
          | Some (first, t, f) when is_if t || is_if f ->
              let loc =
                if e.Typedtree.exp_loc.Location.loc_ghost then
                  first.Typedtree.pat_loc
                else e.Typedtree.exp_loc
              in
              [ Finding.v ~loc message ]
          | _ -> []))
