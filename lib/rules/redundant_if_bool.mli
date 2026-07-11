(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [if]-then-else whose both branches are boolean literals.

    Reports every [if c then t else e] whose branches are the two differing
    boolean literals (predefined-constructor identity): the conditional restates
    its own condition — [if c then true else false] is [c],
    [then false else true] is [not c] — and the message names the equivalent
    form. Both rewrites preserve evaluation order and effects.

    Literal conditions (suspicious-literal-condition's finding), non-boolean
    literal branches, two equal literal branches, and user-defined
    [True]/[False] constructors deliberately do not fire; the one-literal family
    ([then true else e] and kin) is [manual-boolean-operator]'s, split out on
    field evidence. The fix rewrites from the condition's source slice,
    parenthesized when non-atomic, shipping when the slice is clean. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-if-bool]. *)
