(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Case bodies that are immediately an if-then-else.

    Reports each guard-less [match]/[function] case whose right-hand side is
    exactly [if c then a else b], anchored at the [if]: a [when] guard could
    split the case and let each outcome carry its own pattern.

    Cases that already guard, else-less [if]s, [if]s that are only a
    subexpression of the body, [exception] arms, and [try] handlers — where a
    failing guard would fall through to re-raise — deliberately do not fire. *)

val rule : Litany.Rule.t
(** [rule] is [manual-case-guard]. *)
