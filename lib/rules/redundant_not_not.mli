(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Double boolean negation.

    Reports every application of [Stdlib.not] or [Stdlib.Bool.not] whose
    argument is itself such an application, in any combination: [not (not e)] is
    [e], with identical effects and evaluation. Collapsed [@@] and [|>]
    spellings fire too; a quadruple negation reports at two nested nodes.

    Single negations, shadowed or rebound [not], [lnot], and rhyming functions
    deliberately do not fire. The fix replaces the application with the operand
    (parenthesized unless atomic), shipping when the operand's source slices
    cleanly. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-not-not]. *)
