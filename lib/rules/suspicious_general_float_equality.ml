(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-general-float-equality" ~group:Rule.Pedantic
    ~since:"1.0" ~fix:Rule.Never ~summary:"bit-exact equality on floats"
    ~doc:
      {|`=` and `<>` on floats ask for bit-exact equality of values that
arithmetic rarely reproduces bit-exactly: `0.1 +. 0.2 <> 0.3`.

    (* bad *)  weight = 0.1
    (* good *) Float.abs (weight -. 0.1) < epsilon

Fires when `=` or `<>` resolves to its `Stdlib` declaration and at
least one operand's type head is the predefined `float`. Comparisons
against exactly representable anchors are excluded: a float literal
denoting zero (`0.`, `-0.0`, `0x0p0`) and the `infinity` and
`neg_infinity` constants. A `nan` constant operand is
invalid-nan-comparison's finding, never this rule's — the two rules
partition float `=`/`<>` exactly. Orderings are meaningful on floats
and out of scope; type abbreviations over `float` are conservatively
clean (no expansion); shadowed operators do not fire. Code that means
bit-exact equality writes `Float.equal x y` — a distinct declaration
this rule never matches — or carries `[@litany.allow
"suspicious-general-float-equality: exact comparison intended"]` where
the operator form must stay. No fix: a margin-of-error rewrite is
domain-specific.|}
    ()

let message =
  "float equality is bit-exact — compare within a margin, or write Float.equal \
   (or annotate) if exact comparison is intended"

let comparison =
  Pat.(apply (idents [ "Stdlib.(=)"; "Stdlib.(<>)" ]) (__ ^:: __ ^:: nil))

(* The carve-outs, each an exactly-representable anchor or another
   rule's operand: the nan refusal makes invalid-nan-comparison and this
   rule an exact partition of float `=`/`<>`. *)
let nan_constant = Pat.idents [ "Stdlib.nan"; "Stdlib.Float.nan" ]

let infinity_constant =
  Pat.idents
    [
      "Stdlib.infinity";
      "Stdlib.neg_infinity";
      "Stdlib.Float.infinity";
      "Stdlib.Float.neg_infinity";
    ]

let zero_literal (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_constant (Asttypes.Const_float s) -> (
      match float_of_string_opt s with Some f -> f = 0.0 | None -> false)
  | _ -> false

let excluded u e =
  Pat.run nan_constant u e () <> None
  || Pat.run infinity_constant u e () <> None
  || zero_literal e

(* Head-of-type test without abbreviation expansion — the
   suspicious-physical-equality conservatism: a `type celsius = float`
   operand stays clean, a recorded false negative. *)
let float_head (e : Typedtree.expression) =
  match Types.get_desc e.exp_type with
  | Types.Tconstr (p, _, _) -> Path.same p Predef.path_float
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run comparison u e (fun l r -> (l, r)) with
  | None -> []
  | Some (l, r) ->
      if
        (float_head l || float_head r)
        && (not (excluded u l))
        && not (excluded u r)
      then [ Finding.v ~loc:e.exp_loc message ]
      else []
