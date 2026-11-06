(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Uses of [ignore] on a value with no type constraint.

    House policy ([Restriction]). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [untyped-ignore]. *)
