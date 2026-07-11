(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Recursive functions that re-implement [List.filter] or [List.filter_map].

    Reports bindings whose body is the cons-or-skip list recursion: the two-case
    scaffold of manual-list-map whose cons case is either
    [if C then E :: SELF else SELF] (or mirrored) or
    [match G with Some y -> y :: SELF | None -> SELF] — both branches the
    identical recursion advancing only the bound tail. The message names
    [List.filter] when the kept head is exactly the bound element,
    [List.filter_map] otherwise. Unlike manual-list-map's naive shape, this
    rewrite preserves effect order: the condition or scrutinee evaluates before
    the recursion — exactly the stdlib's left-to-right order (verified OCaml
    5.5.0, both trace [123]).

    Else-branches that are not the bare recursion (take-while shapes),
    match-form kept heads other than the bound payload, guards, user-defined
    constructors, and same-named outer functions deliberately do not fire.
    Self-calls of arity four or more are a recorded false negative. *)

val rule : Litany.Rule.t
(** [rule] is [manual-list-filter-map]. *)
