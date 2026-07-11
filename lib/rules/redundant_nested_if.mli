(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Else-less [if] directly nested in an else-less [if].

    Reports [if c1 then if c2 then e] — both [if]s else-less, the inner one the
    entire then-branch — as longhand for [if c1 && c2 then e]: [(&&)]'s
    short-circuit evaluates [c2] exactly when the nested form does, so the
    collapse preserves behavior by construction. Deeper nests report once per
    level.

    Any [else], outer or inner, refuses; so do literal conditions
    (suspicious-literal-condition's finding), [else if] chains, and an inner
    [if] under a [let] or sequence. The fix rewrites the head to [c1 && c2] with
    each condition parenthesized unless atomic, and ships only when both
    conditions slice cleanly and the bytes between them are exactly [then] [if]
    with whitespace. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-nested-if]. *)
