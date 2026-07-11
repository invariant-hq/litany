(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [if] whose two branches are written identically.

    Reports every [if c then A else B] of a non-preprocessed unit where the
    branches' source slices are byte-identical after whitespace normalization:
    the conditional decides nothing, and one branch was likely meant to differ.

    Equality is normalized source text, nothing deeper: comment-only differences
    and spelling differences ([L.map] vs [List.map]) deliberately do not fire —
    false negatives by contract, never false positives. Boolean-literal
    conditions (suspicious-literal-condition's finding), else-less [if]s, and
    preprocessed units deliberately do not fire. No fix: collapsing the
    conditional would bless the suspected copy-paste bug. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-if-same-branches]. *)
