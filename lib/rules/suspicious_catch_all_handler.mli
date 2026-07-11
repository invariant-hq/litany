(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Wildcard exception handlers that swallow every exception.

    Reports each guard-less wildcard case of a [try] handler and each guard-less
    [exception _] arm of a [match], anchored at the wildcard pattern itself. A
    catch-all handles [Out_of_memory], [Assert_failure], and every exception the
    author never anticipated indistinguishably from the one it meant to catch.

    Named binders (even unused — warning 27's business), guarded wildcards,
    wildcards inside deeper patterns, or-patterns, and wildcard value cases
    deliberately do not fire. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-catch-all-handler]. *)
