(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Comparison with [None] spelling an [Option] predicate.

    Reports every [=] or [<>] resolved to its [Stdlib] declaration with exactly
    one operand the predefined [None] constructor: [o = None] is
    [Option.is_none o] and [o <> None] is [Option.is_some o], and the named
    predicate states the intent while keeping the comparison monomorphic.

    Comparisons against [Some e] (payload equality — a meaningful program),
    [None = None], orderings and [compare], physical equality, user-defined
    [None] lookalikes, and shadowed operators deliberately do not fire. The fix
    replaces the comparison with the predicate applied to the other operand —
    behavior-identical, because structural comparison against the immediate
    [None] decides on the tag without traversing the payload; it ships when the
    operand's source slices cleanly.

    The reporting unit is the boolean chain: two or more such comparisons that
    are direct operands of one [Stdlib] [&&]/[||] chain are one finding,
    anchored at the whole chain, its fix rewriting every comparison at once. In
    preprocessed units the collapse is off and every comparison reports
    individually. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-option-comparison]. *)
