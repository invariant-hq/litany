(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The did-you-mean metric.

    One home for the edit-distance suggestion behind every refusal that names a
    near-miss — rule selection ([Rule.suggest]), the suppression attribute names
    ([Suppress]), and configuration validation ([Config_file]). Those callers
    must use this module, never a local copy; the domain has no dependencies, so
    even the lightest leaves can afford this edge. *)

val suggest : candidates:string list -> string -> string option
(** [suggest ~candidates s] is the nearest candidate within edit distance 2 of
    [s], or [None] when nothing is near. The metric is Levenshtein distance —
    insertions, deletions, and substitutions, each costing 1. Ties resolve to
    the lexicographically least candidate, so the suggestion is deterministic
    under any candidate order. *)
