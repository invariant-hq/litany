(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Wildcard bindings [let _ = e] with no type constraint.

    Holds Hypha's [OCAML.md], {i Nothing is discarded unseen}. House policy
    ([Restriction]). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [untyped-wildcard-binding]. *)
