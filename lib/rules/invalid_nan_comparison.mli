(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Comparisons with [nan], whose result is a compile-time constant.

    Reports two-argument applications of [Stdlib]'s [=], [<>], [<], [>], [<=],
    and [>=] with [Stdlib.nan] or [Stdlib.Float.nan] as an operand. IEEE 754
    leaves [nan] unordered with every value including itself, so the orderings
    and [=] are always [false] and [<>] always [true] — the test the code means
    is [Float.is_nan]. Verified, OCaml 5.5.0 arm64 non-flambda: [-w +a] is
    silent even on literal [nan = nan], and cmm shows a live float compare — the
    compiler folds nothing; this rule is the only diagnostic.

    Shadowed operators or [nan] names, [nan] through an alias, [compare] and its
    kin, physical equality, and other float constants stay clean. The
    [Float.is_nan] rewrite is unsafe by policy and has no automatic fix in this
    release — the promise flips to [Sometimes] when it lands. *)

val rule : Litany.Rule.t
(** [rule] is [invalid-nan-comparison]. *)
