(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"invalid-function-comparison" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"structural comparison with a function operand"
    ~doc:
      {|Structural comparison of functions is meaningless: `compare` raises
`Invalid_argument` on distinct closures, and `=` either raises or answers
by physical identity.

    (* bad *)  f = g
    (* good *) compare by a key the functions carry, or track identity
               explicitly

Fires when `=`, `<>`, `<`, `>`, `<=`, `>=`, `compare`, `min`, or `max`
resolves to its `Stdlib` declaration, is applied to exactly two unlabeled
arguments, and an operand's type is a function arrow. Shadowed or rebound
comparisons, physical equality, partial applications, and operands whose
arrow type hides behind an abbreviation deliberately do not fire. No fix:
a meaningful comparison needs domain-specific intent.|}
    ()

let structural =
  Pat.idents
    [
      "Stdlib.(=)";
      "Stdlib.(<>)";
      "Stdlib.(<)";
      "Stdlib.(>)";
      "Stdlib.(<=)";
      "Stdlib.(>=)";
      "Stdlib.compare";
      "Stdlib.min";
      "Stdlib.max";
    ]

let comparison = Pat.(apply structural (__ ^:: __ ^:: nil))

let is_function (e : Typedtree.expression) =
  match Types.get_desc e.exp_type with Types.Tarrow _ -> true | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run comparison u e (fun l r -> is_function l || is_function r) with
  | Some true ->
      [
        Finding.v ~loc:e.exp_loc "structural comparison has a function operand";
      ]
  | Some false | None -> []
