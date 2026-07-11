(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Two-case matches that re-implement [Option.map].

    Reports [match o with Some x -> Some E | None -> None] and the [function]
    form — exactly two guard-less cases, bare-variable [Some] payload, both
    constructors by predefined identity, in either order.
    [Option.map (fun x -> E) o] states the same computation directly; the
    degenerate [Some x -> Some x] rebuild is the scrutinee itself and gets its
    own message.

    Guards, wildcard arms, deeper payload patterns, aliases, [exception] arms,
    user-defined [Some]/[None] constructors, and [Some] arms that do not rebuild
    [Some] deliberately do not fire. The fix rewrites the match form when the
    sources slice cleanly; the [function] form has no scrutinee to name and
    ships none. *)

val rule : Litany.Rule.t
(** [rule] is [manual-option-map]. *)
