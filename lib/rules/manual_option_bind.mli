(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Two-case option match that re-implements [Option.bind].

    Reports every guard-less two-case match — or bare [function] — whose [Some]
    case binds a variable and whose [None] case returns the predefined [None]:
    the expression is [Option.bind o (fun y -> E)] spelled by hand.

    A [Some]-arm right-hand side that is itself a [Some _] construction refuses
    — [Some (g y)] is manual [Option.map] and [Some y] the identity roundtrip,
    owned elsewhere; the partition is exact. Guards, exception arms,
    non-variable payload patterns, [None] arms returning anything else, and
    user-defined option lookalikes deliberately do not fire. No fix: the rewrite
    restructures the whole expression. *)

val rule : Litany.Rule.t
(** [rule] is [manual-option-bind]. *)
