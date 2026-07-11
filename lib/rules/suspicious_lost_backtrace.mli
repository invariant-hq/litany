(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Handlers that work before re-raising their exception.

    Reports [try]/[match … with exception] cases that bind their exception to a
    bare variable without a guard, do at least one statement of work (a sequence
    or [let] spine), and end in [raise] of exactly that variable — anchored at
    the final reraise. The reraise preserves the {e current} backtrace buffer,
    and any raise inside the interposed work, even a caught one, rewrites it;
    the remedy is capturing [Printexc.get_raw_backtrace] first and finishing
    with [Printexc.raise_with_backtrace]. Verified, OCaml 5.5.0 arm64
    non-flambda: the flagged form's trace names only the handler line — the
    origin frame vanishes — while bare [raise e] compiles to the preserving
    [%reraise].

    The bare [with e -> raise e] (already a preserving reraise), guards,
    [raise_notrace], [raise_with_backtrace], re-raises of a different or wrapped
    exception, and specific exception patterns deliberately do not fire. No fix:
    the rewrite introduces a binding and reorders the handler. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-lost-backtrace]. *)
