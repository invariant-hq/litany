(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-boolean-operator" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"boolean operator with a constant operand"
    ~doc:
      {|A `&&` or `||` with a literal `true` or `false` operand computes
nothing the other operand does not already say: `x && true` is `x`,
`false || x` is `x`, `false && e` is `false` with `e` never evaluated.

    (* bad *)  enabled && true
    (* good *) enabled

Fires when `&&` or `||` resolves to its `Stdlib` declaration, is applied
to exactly two unlabeled arguments, exactly one operand is a literal
`true` or `false`, and dropping the operator preserves what the program
evaluates: any constant on the left (short-circuiting already decided
what runs), a neutral constant on the right (`&& true`, `|| false`), or
an absorbing constant on the right (`&& false`, `|| true`) only when the
discarded left operand is a bare identifier or constant and so provably
pure. Shadowed operators, two-constant operations, and absorbing cases
whose discarded operand could have effects deliberately do not fire. No
automatic fix in this release — the promise flips to `Sometimes` when the
simplification fix lands.|}
    ()

let conjunction = Pat.(apply (ident "Stdlib.(&&)") (__ ^:: __ ^:: nil))
let disjunction = Pat.(apply (ident "Stdlib.(||)") (__ ^:: __ ^:: nil))

(* The value of a literally written [true]/[false] at the predefined
   [bool] — [None] otherwise ([Pat.ebool]'s predefined-constructor
   identity, behind the version seam; rules never destructure
   [constructor_description] themselves). *)
let bool_literal u e = Pat.run Pat.(ebool __) u e Fun.id

(* Purity as this rule can prove it: an identifier or a constant evaluates
   to itself. Anything else — any application in particular — might have
   effects and keeps absorbing-right operations clean. *)
let pure (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_ident _ | Typedtree.Texp_constant _ -> true
  | _ -> false

(* [neutral] is the operator's neutral element: [true] for [&&], [false]
   for [||]. A right-side neutral constant drops without touching what runs;
   a right-side absorbing constant discards the left operand's evaluation
   and needs its purity. A left-side constant always preserves evaluation:
   short-circuiting already decided whether the right operand runs. *)
let redundant u ~neutral l r =
  match (bool_literal u l, bool_literal u r) with
  | Some _, None -> true
  | None, Some c -> Bool.equal c neutral || pure l
  | Some _, Some _ | None, None -> false

let rule =
  Rule.expr meta @@ fun u e ->
  let fires =
    match Pat.run conjunction u e (redundant u ~neutral:true) with
    | Some true -> true
    | Some false | None -> (
        match Pat.run disjunction u e (redundant u ~neutral:false) with
        | Some true -> true
        | Some false | None -> false)
  in
  if fires then
    [
      Finding.v ~loc:e.exp_loc
        "boolean operator has a redundant constant operand";
    ]
  else []
