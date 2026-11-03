(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Structure-item [open]s of a module that is not made to be opened.

    Reports an [open] at a unit's root or in a nested structure through which
    the unit takes anything but binding operators, or nothing. Holds Hypha's
    [OCAML.md], {i No [open] of an ordinary module}. House policy
    ([Restriction], Nursery). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [open-of-ordinary-module]. *)
