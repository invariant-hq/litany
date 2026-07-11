(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Total handlers that swallow Eio fiber cancellation.

    Reports a [try] handler (or the [exception] cases of a [match]) whose
    guard-less total arm — bare variable or wildcard — converts to a value
    rather than re-raising its binder, when no sibling arm passes the exception
    through (the alias-re-raise discipline,
    [| Eio.Cancel.Cancelled _ as e -> raise e]) and the guarded region applies a
    function declared in an [Eio]-family compilation unit. The pass-through
    condition is meant to be Cancelled-constructor identity by UID; pattern-side
    exception-constructor identity has not landed, so the alias-re-raise shape
    stands in — a recorded gap. The fix inserts the guard arm before the total
    one — behavior-changing by design, so [Unsafe]. Verified against Eio (opam
    OCaml 5.4 switch): a catch-all retry loop under a cancelled switch hangs —
    [Cancelled] re-raised and swallowed on every [sleep] until a 3 s watchdog
    kills the probe — while the alias-re-raise arm exits promptly with the real
    exception. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-swallowed-cancellation]. *)
