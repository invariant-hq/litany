(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"quadratic-list-append" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"list append folded with the accumulator on the left"
    ~doc:
      {|`(@)` copies its left operand and shares its right. A fold whose
accumulator sits on the left of `(@)` therefore copies everything
accumulated so far at every step — quadratic in the total length where
`List.concat` and `List.concat_map` are linear.

    (* bad *)  List.fold_left (fun acc x -> acc @ [f x]) [] xs
    (* good *) List.concat_map (fun x -> [f x]) xs

Fires when `List.fold_left`, `Array.fold_left`, or `Seq.fold_left`
resolves to its `Stdlib` declaration with `Stdlib.(@)`/`List.append` —
or a two-parameter lambda appending with its accumulator (first)
parameter on the left — as the first unlabeled argument, at any
saturation up to three; and when `List.fold_right`/`Array.fold_right`
takes a lambda with its accumulator (second) parameter on the left, the
quadratic reversal. `List.fold_right (@) xss []` is **linear** — each
element is copied once; it is `List.concat` itself — and deliberately
does not fire, and neither do element-on-the-left lambdas, consing,
rebound operators, or labeled folds. The recursive spelling
(`rev xs @ [x]`) is a recorded false negative: it needs a second rule
kind on one rule, which the engine does not yet allow. No fix: the
rewrites restructure the expression; the message names them.|}
    ()

let append_names = [ "Stdlib.(@)"; "Stdlib.List.append" ]
let append_operator = Pat.idents append_names

let left_folds =
  Pat.idents
    [
      "Stdlib.List.fold_left"; "Stdlib.Array.fold_left"; "Stdlib.Seq.fold_left";
    ]

let right_folds =
  Pat.idents [ "Stdlib.List.fold_right"; "Stdlib.Array.fold_right" ]

(* The fold's first unlabeled argument, at saturations one to three —
   the quadratic-string-concat-fold shape. *)
let fold_arg folds =
  Pat.(
    apply folds (__ ^:: nil)
    ||| apply folds (__ ^:: drop ^:: nil)
    ||| apply folds (__ ^:: drop ^:: drop ^:: nil))

let left_fold_arg = fold_arg left_folds
let right_fold_arg = fold_arg right_folds

(* A two-parameter lambda whose body appends with a bare variable on the
   left: [fun acc x -> acc @ E]. Which parameter that variable must be is
   the fold direction's accumulator — checked in rule code. *)
let appending_lambda =
  Pat.(
    fun_body
      (param pvar ^:: param pvar ^:: nil)
      (apply (idents append_names) (var ^:: drop ^:: nil)))

let is_append_operator u f = Option.is_some (Pat.run append_operator u f ())

let lambda_accumulates ~acc_first u f =
  match
    Pat.run appending_lambda u f (fun p q left ->
        Path.same left (Path.Pident (if acc_first then p else q)))
  with
  | Some fires -> fires
  | None -> false

let rule =
  Rule.expr meta @@ fun u e ->
  let quadratic =
    match Pat.run left_fold_arg u e Fun.id with
    | Some f -> is_append_operator u f || lambda_accumulates ~acc_first:true u f
    | None -> (
        match Pat.run right_fold_arg u e Fun.id with
        | Some f -> lambda_accumulates ~acc_first:false u f
        | None -> false)
  in
  if quadratic then
    [
      Finding.v ~loc:e.exp_loc
        "(@) copies its left operand, making this fold quadratic; use \
         List.concat, List.concat_map, or :: with List.rev";
    ]
  else []
