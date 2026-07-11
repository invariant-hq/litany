(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"invalid-nan-comparison" ~group:Rule.Correctness ~since:"1.0"
    ~fix:Rule.Never ~summary:"comparison with nan is a compile-time constant"
    ~doc:
      {|IEEE 754 makes `nan` unordered with everything, itself included: `=`,
`<`, `>`, `<=`, and `>=` against `nan` are always `false` and `<>` is
always `true`, so the comparison never tests what it spells.

    (* bad *)  x = nan
    (* good *) Float.is_nan x

Fires when `=`, `<>`, `<`, `>`, `<=`, or `>=` resolves to its `Stdlib`
declaration with `Stdlib.nan` or `Stdlib.Float.nan` as an operand.
Shadowed operators or `nan` names, `nan` reached through an alias
(`let m = nan in x = m` — identity, not dataflow), `compare` and its kin
(a defined total order), physical equality (not constant: the same box
compares true), and other float constants deliberately do not fire. The
rewrite to `Float.is_nan` changes a constant answer into the intended
test — unsafe by policy. No automatic fix in this release — the promise
flips to `Sometimes` when that rewrite lands.|}
    ()

let operators =
  Pat.idents
    [
      "Stdlib.(=)";
      "Stdlib.(<>)";
      "Stdlib.(<)";
      "Stdlib.(>)";
      "Stdlib.(<=)";
      "Stdlib.(>=)";
    ]

let nan_literal = Pat.idents [ "Stdlib.nan"; "Stdlib.Float.nan" ]

let comparison =
  Pat.(
    apply operators (nan_literal ^:: drop ^:: nil)
    ||| apply operators (drop ^:: nan_literal ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run comparison u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "nan is unordered, so this comparison is constant; use Float.is_nan";
      ]
