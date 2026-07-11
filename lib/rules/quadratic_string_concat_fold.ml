(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"quadratic-string-concat-fold" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Never ~summary:"string concatenation folded through (^)"
    ~doc:
      {|Folding `(^)` over a collection copies the whole accumulator for every
element: joining n segments allocates quadratically where `String.concat`
allocates the result once.

    (* bad *)  List.fold_left ( ^ ) ""
    (* good *) String.concat ""

Fires when `List.fold_left`, `List.fold_right`, `Array.fold_left`,
`Array.fold_right`, or `Seq.fold_left` resolves to its `Stdlib`
declaration with `Stdlib.(^)` as the first of one or two unlabeled
arguments — at any saturation, the partially applied `fold ( ^ )` and
`fold ( ^ ) ""` and the fully saturated three-argument call alike. A
rebound `(^)`, the eta-expanded `fun acc s -> acc ^ s`, labeled folds
(`ListLabels.fold_left ~f:( ^ )`), other operators, and Buffer
accumulation deliberately do not fire. The `String.concat ""` rewrite
of the saturated form lands with a later release; no automatic fix
until then — the promise flips to `Sometimes` with it.|}
    ()

let folds =
  Pat.idents
    [
      "Stdlib.List.fold_left";
      "Stdlib.List.fold_right";
      "Stdlib.Array.fold_left";
      "Stdlib.Array.fold_right";
      "Stdlib.Seq.fold_left";
    ]

let concat_operator = Pat.ident "Stdlib.(^)"

let folded_concat =
  Pat.(
    apply folds (concat_operator ^:: nil)
    ||| apply folds (concat_operator ^:: drop ^:: nil)
    ||| apply folds (concat_operator ^:: drop ^:: drop ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run folded_concat u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "folding (^) copies the accumulator per element; use String.concat";
      ]
