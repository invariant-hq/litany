(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Comparisons with a boolean constant.

    Reports applications of [Stdlib.(=)] or [Stdlib.(<>)] to exactly two
    unlabeled arguments where exactly one operand is a literal [true] or [false]
    of the predefined [bool], in either operand order — [x = true] is [x],
    [x = false] is [not x]. Shadowed operators, two-constant comparisons, other
    operators, and same-spelling constructors of another type stay clean. The
    fix drops the constant — the operand itself ([use the operand]) or its
    negation ([negate the operand]) — and ships when the operand's source slices
    cleanly. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-boolean-comparison]. *)
