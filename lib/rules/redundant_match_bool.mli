(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Boolean matches interrupting an if/else chain.

    Reports [match e with true -> a | false -> b] and the [function] form —
    exactly two guard-less cases whose patterns are the boolean literals
    (predefined-constructor identity) in either order — only in the cascade
    positions: the match sits as the [else] branch of an enclosing [if], or an
    arm's body is itself an [if]/[else] (the [function] form fires on the arm
    shape alone). There [if]/[else] keeps the cascade in one shape; the
    standalone two-case boolean match is a deliberate house style in wide use
    and never fires.

    Guards, extra or wildcard cases, [exception] cases, user-defined
    two-constructor variants, and matches carrying effect handlers deliberately
    do not fire. The fix rewrites the match form to [if]/[else] when the
    scrutinee's and both arms' source slices cleanly; the [function] form has no
    scrutinee to build the condition from and ships none. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-match-bool]. *)
