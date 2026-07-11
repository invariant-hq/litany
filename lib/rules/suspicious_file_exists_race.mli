(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Check-then-act on the filesystem.

    Reports, in non-preprocessed units, an [if] whose condition is a
    [Sys.file_exists] probe — bare, under [not], or with a [Sys.is_directory]
    refinement conjunct — when either arm applies [Sys.remove], [Sys.mkdir],
    [Sys.rename], [Unix.unlink], [Unix.mkdir], or [Unix.rmdir] to a path whose
    source slice equals the probed expression's after whitespace normalization,
    the probed expression itself syntactically pure. Anchored at the condition,
    one finding per [if].

    An operation under a [try] (or a [match] with an [exception] case on its
    scrutinee) is the remedy and never fires; guarded reads, computed or impure
    paths, operations on a different path, operations deferred inside a function
    or [lazy], and nested exists-guards are recorded false negatives in the safe
    direction. House policy ([Restriction]: the race is real but widely
    tolerated in test scaffolding — off even under [all], cherry-picked). No
    fix: the remedy restructures control flow around the operation's exception.
*)

val rule : Litany.Rule.t
(** [rule] is [suspicious-file-exists-race]. *)
