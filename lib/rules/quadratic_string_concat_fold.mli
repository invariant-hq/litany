(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** String concatenation folded through [( ^ )].

    Reports applications of [Stdlib]'s [List.fold_left], [List.fold_right],
    [Array.fold_left], [Array.fold_right], and [Seq.fold_left] whose first
    unlabeled argument resolves to [Stdlib.( ^ )] — the quadratic join
    [String.concat] performs linearly. Measured, OCaml 5.5.0 arm64 non-flambda:
    over 4-byte words, 20k take 0.48 s and 40k take 1.64 s; [String.concat] at
    40k: 0.0005 s (~3500x).

    Rebound operators, eta-expanded lambdas, labeled folds, other operators, and
    Buffer accumulation stay clean; the fully saturated three-argument call is
    not yet matched. No automatic fix in this release — the promise flips to
    [Sometimes] when the [String.concat ""] rewrite lands. *)

val rule : Litany.Rule.t
(** [rule] is [quadratic-string-concat-fold]. *)
