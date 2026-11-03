(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Uses of [ignore] on a value with no type constraint.

    Holds Hypha's [OCAML.md], {i Nothing is discarded unseen}. House policy
    ([Restriction], Nursery). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [untyped-ignore]. *)
