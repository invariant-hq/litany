(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Two-case matches that re-implement [Option.value].

    Reports [match o with Some x -> x | None -> D] and the [function] form —
    exactly two guard-less cases, bare-variable [Some] payload returned
    unchanged, in either order, by predefined-constructor identity — when [D] is
    provably trivial: a literal, an identifier, or a nullary constructor.
    [Option.value o ~default:D] states the same intent directly; the triviality
    proof matters because [Option.value] evaluates its default always while the
    match evaluates [D] only on [None].

    Effectful or raising defaults, transforming [Some] arms, guards, unused
    payloads, and user-defined [Some]/[None] constructors deliberately do not
    fire. The fix rewrites the match form when the sources slice cleanly; the
    [function] form has no scrutinee to name and ships none. *)

val rule : Litany.Rule.t
(** [rule] is [manual-option-value]. *)
