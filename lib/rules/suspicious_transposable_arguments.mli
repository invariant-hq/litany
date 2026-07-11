(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Three adjacent same-typed unlabeled parameters.

    Reports each exported structure-level value binding of a Library-kind unit
    whose arrow spine carries three or more consecutive unlabeled parameters of
    equal type: two adjacent cover the symmetric operations, three have no
    symmetric reading and make every call site a silent transposition hazard.
    Labels break adjacency — the remedy itself. Anchored at the binding's name
    in the implementation; units without kind metadata degrade to silence; no
    fix (labeling is an API change). Implemented on the implementation binding's
    type with syntactic type equality and a derived-UID / interface-name export
    gate — recorded narrowings of the rule's interface-wide claim, each
    false-negative-safe. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-transposable-arguments]. *)
