(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Bit-exact equality on floats.

    Reports every [=] or [<>] resolved to its [Stdlib] declaration with at least
    one operand whose type head is the predefined [float] — floating arithmetic
    rarely reproduces values bit-exactly, so the comparison is usually a
    margin-of-error bug.

    Comparisons against exactly representable anchors — a float literal denoting
    zero, the infinity constants — are excluded; a [nan] constant operand is
    invalid-nan-comparison's, making the two rules an exact partition of float
    [=]/[<>]. Orderings, [Float.equal] (the blessed exact-comparison spelling),
    abbreviation-typed operands, and shadowed operators deliberately do not
    fire. No fix: the margin is domain-specific. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-general-float-equality]. *)
