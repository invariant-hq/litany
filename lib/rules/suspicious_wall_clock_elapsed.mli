(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Durations measured on the wall clock.

    Reports float [+.]/[-.] (and [Float.add]/[Float.sub]) applications where
    either argument is directly a [Unix.gettimeofday ()] or [Unix.time ()] call
    — deadline and elapsed arithmetic that jumps with NTP steps and clock
    changes. Clock seams (the function stored as a value), timestamp payloads,
    [*.] scaling, monotonic counters, and [Sys.time] deliberately do not fire; a
    read flowing through a [let] before the arithmetic is a recorded false
    negative. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-wall-clock-elapsed]. *)
