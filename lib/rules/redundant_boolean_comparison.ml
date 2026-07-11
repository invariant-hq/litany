(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-boolean-comparison" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"comparison with a boolean constant"
    ~doc:
      {|Comparing a boolean with `true` or `false` restates the operand:
`x = true` is `x`, `x = false` is `not x`. The comparison adds noise and
often signals a leftover simplification.

    (* bad *)  if flag = true then …
    (* good *) if flag then …

Fires when `=` or `<>` resolves to its `Stdlib` declaration, is applied to
exactly two unlabeled arguments, and exactly one operand is a literal
`true` or `false` of the predefined `bool` type, in either operand order.
Shadowed or rebound operators, comparisons of two constants, other
operators (`==`, `<`, `Bool.equal`), and same-spelling constructors of
another type deliberately do not fire. The fix drops the constant: the
comparison becomes the operand itself (`x = true` → `x`, safe) or its
negation (`x = false` → `not x`, `x <> true` → `not x`) — the negation
splices a `not` the rule never resolved, so a fix-site scope shadowing
`not` would change the value: that cell's fix is unsafe, applied only
under `--fix --unsafe`. Either fix ships only when the operand's source
slices cleanly (`Unit.splice`).|}
    ()

let eq = Pat.(apply (ident "Stdlib.(=)") (__ ^:: __ ^:: nil))
let ne = Pat.(apply (ident "Stdlib.(<>)") (__ ^:: __ ^:: nil))

(* The value of a literally written [true]/[false] at the predefined
   [bool] — [None] otherwise ([Pat.ebool]'s predefined-constructor
   identity: a same-spelling constructor of another type,
   [type fake = true | false], stays clean). *)
let bool_literal u e = Pat.run Pat.(ebool __) u e Fun.id

(* Exactly one constant operand: two constants are a different smell (a
   constant expression), and zero leave nothing to drop. *)
let split u l r =
  match (bool_literal u l, bool_literal u r) with
  | Some lit, None -> Some (r, lit)
  | None, Some lit -> Some (l, lit)
  | Some _, Some _ | None, None -> None

let rule =
  Rule.expr meta @@ fun u e ->
  (* [negate]: [x = false] and [x <> true] are the operand's negation; the
     other two are the operand itself. *)
  let found =
    match Pat.run eq u e (split u) with
    | Some (Some (x, lit)) -> Some (x, not lit)
    | Some None | None -> (
        match Pat.run ne u e (split u) with
        | Some (Some (x, lit)) -> Some (x, lit)
        | Some None | None -> None)
  in
  match found with
  | None -> []
  | Some (x, negate) ->
      let fix =
        Option.map
          (fun src ->
            if negate then
              (* The spliced [not] resolves in the fix site's scope, which
                 this rule never checked — Unsafe. *)
              Fix.unsafe_replace e.exp_loc
                (Unit.delimited u e ("not " ^ src))
                ~title:"negate the operand"
            else Fix.safe_replace e.exp_loc src ~title:"use the operand")
          (Unit.splice u x)
      in
      [
        Finding.v ?fix ~loc:e.exp_loc
          "comparison with a boolean constant is redundant";
      ]
