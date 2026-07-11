(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** List append folded with the accumulator on the left of [( @ )].

    [( @ )] copies its left operand, so a fold accumulating on the left copies
    the whole accumulator per element — quadratic where [List.concat] and
    [List.concat_map] are linear. Reports [Stdlib]'s [fold_left] family applied
    to [( @ )]/[List.append] or to a lambda appending with the accumulator
    parameter on the left, and the [fold_right] family applied to a lambda with
    its accumulator on the left (a quadratic reversal). Measured, OCaml 5.5.0
    arm64 non-flambda: n=10k takes 0.18 s and n=20k 1.26 s (7x on doubling);
    [List.fold_right ( @ ) xss []] at n=20k: 0.0004 s.

    [List.fold_right ( @ ) xss []] is linear — it is [List.concat] itself — and
    stays clean, as do element-on-the-left lambdas, consing, rebound operators,
    and labeled folds. The recursive naive-append spelling is a recorded false
    negative: it needs a second rule kind on one rule, which the engine does not
    yet allow. No fix: the rewrites restructure the expression. *)

val rule : Litany.Rule.t
(** [rule] is [quadratic-list-append]. *)
