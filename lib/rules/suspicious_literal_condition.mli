(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [if] over a literal boolean condition.

    Reports every [if] whose condition is the literal [true] or [false] (by
    predefined-constructor identity): one branch is dead and the conditional is
    a debugging leftover or an unfinished edit.

    Named flags ([let debug = true … if debug]), runtime conditions,
    [while true] (structurally not an [if]), and boolean matches deliberately do
    not fire. No automatic fix in this release — the promise flips to
    [Sometimes] when the collapse-to-live-branch rewrite lands. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-literal-condition]. *)
