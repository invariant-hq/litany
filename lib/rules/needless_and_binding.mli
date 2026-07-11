(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [let rec] bindings riding an [and]-chain they do not need.

    Reports each binding of a recursive multi-binding group that is mutually
    reachable with no sibling over the identity-resolved reference graph:
    self-recursive-only bindings extract as their own [let rec], inert bindings
    as a plain [let]. Members of a genuine cycle never fire.

    Exact partition with [suspicious-rec-without-recursion]: a group no binding
    of which references the group at all is that rule's finding and never this
    one's. Edges come from the unit's use index by declaration identity — a
    same-spelled inner rebinding contributes no edge — and an unplaceable use or
    non-variable pattern refuses the group. Warning 39 is silent on every
    positive (it needs the whole group inert). No fix: extraction reorders
    bindings. *)

val rule : Litany.Rule.t
(** [rule] is [needless-and-binding]. *)
