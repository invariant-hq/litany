(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-nested-if" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"else-less if directly nested in an else-less if"
    ~doc:
      {|An else-less `if` whose then-branch is directly another else-less
`if` is one condition spelled as two: `&&`'s short-circuit evaluates
the inner condition exactly when the nested form does, so the collapse
is behavior-preserving by construction.

    (* bad *)  if ok then if ready then launch ()
    (* good *) if ok && ready then launch ()

Fires when both `if`s are else-less and the inner one is the entire
then-branch (`begin end` and parentheses are transparent), at the outer
`if`. Any `else` — outer or inner — refuses: collapsing would change
what runs when the conditions split. Literal conditions are
suspicious-literal-condition's finding, `else if` chains are the idiom
and are never looked into, and a nested `if` under a `let` or sequence
deliberately does not fire. Deeper nests report once per level. The
fix rewrites the head to `c1 && c2`, parenthesizing each condition
unless atomic; it ships only when the text between the conditions is
exactly `then` `if` with whitespace — a parenthesis, `begin`, or
comment in the gap withholds the fix, not the finding.|}
    ()

let message = "if c1 then if c2 then e is longhand for if c1 && c2 then e"
let nested = Pat.(if_ __ (if_ __ drop none) none)
let is_literal u e = Pat.run Pat.(ebool __) u e (fun _ -> ()) <> None

(* [gap_ok s] holds when [s] is exactly optional-whitespace [then]
   whitespace [if] optional-whitespace — the only shape whose bytes the
   fix may replace with [" && "]. Any parenthesis, [begin], comment, or
   attribute fails the walk. *)
let gap_ok s =
  let n = String.length s in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let rec skip_ws i = if i < n && is_ws s.[i] then skip_ws (i + 1) else i in
  let word w i =
    let m = String.length w in
    if i + m <= n && String.equal (String.sub s i m) w then Some (i + m)
    else None
  in
  match word "then" (skip_ws 0) with
  | None -> false
  | Some i -> (
      let j = skip_ws i in
      if j = i then false
      else match word "if" j with None -> false | Some k -> skip_ws k = n)

let fix u (c1 : Typedtree.expression) (c2 : Typedtree.expression) =
  if Unit.preprocessed u then None
  else
    match (Unit.splice u c1, Unit.splice u c2) with
    | Some a1, Some a2 ->
        let s1 = Span.of_location c1.exp_loc
        and s2 = Span.of_location c2.exp_loc in
        let gap = Span.v ~start:(Span.stop s1) ~stop:(Span.start s2) in
        Option.bind
          (Source.slice (Unit.source u) gap)
          (fun bytes ->
            if gap_ok bytes then
              Some
                (Fix.v ~applicability:Fix.Safe ~title:"collapse to c1 && c2"
                   [
                     { Fix.span = s1; text = a1 };
                     { Fix.span = gap; text = " && " };
                     { Fix.span = s2; text = a2 };
                   ])
            else None)
    | (Some _ | None), _ -> None

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run nested u e (fun c1 c2 -> (c1, c2)) with
  | None -> []
  | Some (c1, c2) ->
      if is_literal u c1 || is_literal u c2 then []
      else [ Finding.v ?fix:(fix u c1 c2) ~loc:e.exp_loc message ]
