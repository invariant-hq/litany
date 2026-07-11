(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Structural comparisons with a function operand.

    Reports two-argument applications of the canonical [Stdlib] comparisons —
    [=], [<>], [<], [>], [<=], [>=], [compare], [min], [max] — when a direct
    operand's type is a function arrow. Structural comparison of functions
    raises [Invalid_argument] on distinct closures or answers by physical
    identity; neither is a meaningful order.

    Shadowed or rebound comparisons, physical equality, partial applications,
    and arrow types hidden behind abbreviations stay clean. No fix: a meaningful
    comparison needs domain-specific intent. *)

val rule : Litany.Rule.t
(** [rule] is [invalid-function-comparison]. *)
