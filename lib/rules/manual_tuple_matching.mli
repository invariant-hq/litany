(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Single irrefutable tuple cases that could be [let] bindings.

    Reports a [match] with exactly one guard-less case whose pattern is an
    irrefutable unlabeled tuple — no branching happens, so
    [let (a, b) = p in ...] says what the match does. Irrefutability is proved
    (variables, wildcards, nested unlabeled tuples); refutable components,
    guards, multi-case and [exception]/effect forms, and [function]-spelled
    cases refuse. Alias and constraint components refuse conservatively —
    recorded false negatives. The Safe fix rewrites to [let] under the
    keyword-gap grammar gates; a comment in a gap refuses the fix, never the
    finding. *)

val rule : Litany.Rule.t
(** [rule] is [manual-tuple-matching]. *)
