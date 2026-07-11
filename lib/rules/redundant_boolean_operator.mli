(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Boolean operators with a constant operand.

    Reports applications of [Stdlib.(&&)] or [Stdlib.(||)] to exactly two
    unlabeled arguments where exactly one operand is a literal [true] or [false]
    and dropping the operator preserves what the program evaluates: any
    left-side constant, a neutral right-side constant ([&& true], [|| false]),
    or an absorbing right-side constant ([&& false], [|| true]) only when the
    discarded operand is a bare identifier or constant. Shadowed operators,
    two-constant operations, and absorbing cases whose discarded operand could
    have effects stay clean. No automatic fix in this release — the promise
    flips to [Sometimes] when the simplification fix lands. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-boolean-operator]. *)
