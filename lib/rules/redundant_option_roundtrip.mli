(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Option-to-list conversions immediately undone by [List.nth_opt _ 0].

    Reports exactly [List.nth_opt (Option.to_list o) 0] when both functions
    resolve to their [Stdlib] declarations and the index is the integer literal
    zero — the expression rebuilds [o] through an intermediate list allocation.

    Shadowed or let-rebound names, other indices, partial applications, operator
    pipelines, and intervening expressions stay clean. The rule offers no fix:
    replacing the roundtrip with its input changes physical identity. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-option-roundtrip]. *)
