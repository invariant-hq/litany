(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Recursive functions that re-implement [List.for_all].

    Reports bindings whose body is the two-case list recursion returning the
    literal [true] on [[]] and [E && self … tl] on cons — [List.for_all] with
    the same left-to-right evaluation, the same short-circuit on the first
    [false], and the same effect order.

    A self-call left of [(&&)], a [false] nil case, a same-named outer function
    without [rec], a recursion argument other than the bound tail, guards, extra
    cases, and user-defined [(::)]/[[]] deliberately do not fire; the
    [if p x then self xs else false] spelling is redundant-if-bool's inner [if].
    Self-calls of arity four or more are recorded false negatives. No fix: the
    rewrite restructures the whole binding. *)

val rule : Litany.Rule.t
(** [rule] is [manual-list-forall]. *)
