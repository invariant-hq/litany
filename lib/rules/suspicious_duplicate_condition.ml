(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-duplicate-condition" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"else-if condition that duplicates the previous arm's"
    ~doc:
      {|`if c then … else if c then e2 …` evaluates the second `c` with
nothing between the two evaluations except the first `c` itself: when
`c` is pure the second arm can never run, and the chain is almost
certainly an unedited paste.

    (* bad *)  if x = 1 then a else if x = 1 then b else c
    (* good *) if x = 1 then a else if x = 2 then b else c

Fires when, in a non-preprocessed unit, an `if`'s else branch is
directly another `if`, the two conditions' source slices are
byte-identical after whitespace normalization, and the condition is
syntactically pure — built only of identifiers, constants, constructors,
and applications of the `Stdlib` boolean and comparison operators.
Conditions with any other call (it may be effectful), dereferences,
field or array reads (another domain could write between evaluations),
and boolean-literal conditions (suspicious-literal-condition's) refuse.
Only adjacent arms are compared: `if a … else if b … else if a` is a
recorded false negative. No fix: which arm was meant is the author's
call.|}
    ()

let message =
  "this condition duplicates the previous arm's — the arm can never run"

let shape = Pat.(if_ __ drop (some (if_ __ drop drop)))
let literal_bool u e = Pat.run Pat.(ebool __) u e (fun _ -> ()) <> None

(* The syntactic-purity predicate:
   identifiers, constants, constructors and tuples of pure parts, and
   applications of these `Stdlib` operators with pure arguments. Any
   other application refuses (a call may be effectful, so a repeated
   call is not a repeated condition), as do `!`, field and array reads — mutable state
   another domain could write between the two evaluations. Tuple parts
   are refused too (the payload's shape churns across supported compiler
   minors and rule code carries no version seam) — a recorded false
   negative. *)
let pure_ops =
  [
    "Stdlib.(&&)";
    "Stdlib.(||)";
    "Stdlib.not";
    "Stdlib.(=)";
    "Stdlib.(<>)";
    "Stdlib.(<)";
    "Stdlib.(>)";
    "Stdlib.(<=)";
    "Stdlib.(>=)";
  ]

let op2 = Pat.(apply (idents pure_ops) (__ ^:: __ ^:: nil))
let op1 = Pat.(apply (idents pure_ops) (__ ^:: nil))

let rec pure u (e : Typedtree.expression) =
  match Pat.run op2 u e (fun a b -> (a, b)) with
  | Some (a, b) -> pure u a && pure u b
  | None -> (
      match Pat.run op1 u e Fun.id with
      | Some a -> pure u a
      | None -> (
          match e.exp_desc with
          | Typedtree.Texp_ident _ | Typedtree.Texp_constant _ -> true
          | Typedtree.Texp_construct (_, _, args) -> List.for_all (pure u) args
          | _ -> false))

(* Normalized source-slice equality — the shared technique, from its one
   home. *)
let normalize = Normalized_slice.normalize
let slice = Normalized_slice.slice

let rule =
  Rule.expr meta @@ fun u e ->
  if Unit.preprocessed u then []
  else
    match
      Pat.run shape u e (fun c1 (c2 : Typedtree.expression) -> (c1, c2))
    with
    | None -> []
    | Some (c1, c2) -> (
        if literal_bool u c1 then []
        else
          match (slice u c1.exp_loc, slice u c2.exp_loc) with
          | Some a, Some b
            when String.equal (normalize a) (normalize b) && pure u c1 ->
              (* Identical slices make checking one side's purity
                 sufficient; anchoring at the second condition keeps a
                 triple chain's two findings — one per adjacent pair, from
                 two nodes — at distinct duplicates without dedup. *)
              [ Finding.v ~loc:c2.exp_loc message ]
          | _ -> [])
