(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Recursive functions that re-implement [List.fold_left] or [List.fold_right].

    Reports bindings whose body is the two-case list recursion returning one of
    the parameters — the accumulator — on [[]], with the cons case either the
    tail call transforming only the accumulator position (fold_left) or exactly
    one self-call keeping every parameter unchanged inside a step expression
    (fold_right). The step may be any expression, an operator included. The
    message names the replacement.

    Nil cases returning a literal, changed-and-wrapped accumulators, two
    self-calls, guarded or extra cases, user-defined [(::)]/[[]], and same-named
    outer functions deliberately do not fire. Self-calls of arity four or more,
    and fold_right steps nesting the self-call deeper than one application, are
    recorded false negatives. *)

val rule : Litany.Rule.t
(** [rule] is [manual-list-fold]. *)
