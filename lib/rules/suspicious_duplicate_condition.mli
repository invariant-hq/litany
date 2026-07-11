(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [else if] condition that duplicates the previous arm's.

    Reports the second condition of every adjacent [if … else if …] pair of a
    non-preprocessed unit whose two conditions are byte-identical after
    whitespace normalization and syntactically pure — built only of identifiers,
    constants, constructors, and [Stdlib] boolean and comparison operators.
    Nothing runs between the two evaluations but the first (pure) condition, so
    the second arm can never run.

    Conditions containing any other application, dereference, or field or array
    read refuse (the value could change between evaluations), as do
    boolean-literal conditions (suspicious-literal-condition's) and
    comment-carrying or otherwise differing slices. Non-adjacent duplicates are
    recorded false negatives. No fix. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-duplicate-condition]. *)
