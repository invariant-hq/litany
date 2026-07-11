(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The run's progress meter: one rewritten line on standard error.

    A long check is silent otherwise — the dune build, the workspace describe,
    then one pass over every unit — and silence reads as a hang. This domain
    draws dune's shape:

    {v Done: 36% (4/11, 7 left) (jobs: 8) | [1.4s] [2.9/s] v}

    Advisory and terminal-only. The meter draws nothing unless standard error is
    a terminal and [LITANY_NO_PROGRESS] is unset — a pipe, a cram sandbox, or a
    CI log sees byte-identical output with and without it, so no report, golden,
    or exit code can depend on progress. The report page is standard output's;
    this line never touches it, and {!clear} takes it off the screen before
    anything else prints.

    The meter is the driver's, like the clock it reads: engine-side code takes a
    [progress] callback and calls it, never this module. *)

type t
(** The type for one run's meter. Carries the run clock, the phase label, the
    count, and the redraw throttle. *)

val v : enabled:bool -> jobs:int -> t
(** [v ~enabled ~jobs] is a meter whose clock starts now. It draws iff [enabled]
    (the caller's [--no-progress] and format decisions), standard error is a
    terminal, and [LITANY_NO_PROGRESS] is unset; a meter that does not draw
    still answers every call, doing nothing. [jobs] is the worker count the line
    reports. *)

val drawing : t -> bool
(** [drawing t] is [true] iff [t] draws — for a caller that would otherwise
    compute something only the line would show. *)

val phase : t -> string -> unit
(** [phase t label] shows [label] and the elapsed clock, with no count:
    [{v building… [3.2s] v}]. For the run's uncounted stretches — the dune
    build, the workspace describe. Redraws immediately. *)

val counting : t -> label:string -> total:int -> unit
(** [counting t ~label ~total] starts a counted phase of [total] items at zero
    done. [label] prefixes the line ([""] for the plain [Done: …] shape).
    Redraws immediately. *)

val add : t -> int -> unit
(** [add t n] counts [n] more items done and redraws, throttled. *)

val tick : t -> unit
(** [tick t] is [add t 1]. *)

val refresh : t -> unit
(** [refresh t] redraws the current line, throttled — the elapsed clock keeps
    moving through a stretch that reports no items (a spawned child's output
    loop calls this). *)

val clear : t -> unit
(** [clear t] erases the line if one is on screen, so the next thing printed
    starts at column zero on a clean line. Idempotent. Every path out of a run —
    page, refusal, or exception — passes through this. *)

val jobs : t -> int -> unit
(** [jobs t n] sets the worker count the line reports — the driver's effective
    count, resolved after defaulting and the [--fix] serial clamp, not the
    number the caller asked for. *)
