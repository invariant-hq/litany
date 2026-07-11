(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** References to the stdlib's partial eliminators.

    Reports every reference resolving to [Stdlib]'s [List.hd], [List.tl],
    [List.nth], [Option.get], [Result.get_ok], or [Result.get_error] — the
    eliminators that raise on the case their type admits but their contract
    excludes. Reference-level: saturated calls, partial applications, and
    first-class uses fire alike, through aliases and [open].

    Shadowed modules, same-named local values, the total [_opt]/[value]
    siblings, and the [Not_found] retrieval protocol stay clean. House policy
    ([Restriction]: partiality is legitimate in general and a finding only where
    the workspace bans it — off even under [all], cherry-picked); no fix — each
    remedy restructures control flow. *)

val rule : Litany.Rule.t
(** [rule] is [unsafe-partial-stdlib]. *)
