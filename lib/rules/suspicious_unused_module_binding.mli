(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Module bindings the unit never uses and never exports.

    Reports a named module binding no reference in the unit's implementation
    mentions — by resolved identity over every stored path
    ({!Litany.Unit.module_uses}) — when nothing outside the unit can reach it
    either: a [let module M = … in e] whose body never mentions [M], or a
    toplevel [module M = …] whose own interface exists and does not export [M].
    Warning 60's sound judgment, made config-independent (it ships disabled in
    every mainstream default).

    A unit without an [.mli] exports everything and stays silent; [module _] is
    the sanctioned effect-only spelling and refuses by construction; module
    bindings nested inside sub-structures and [Pstr_recmodule] groups are
    recorded non-goals. The interface substrate is not witness-checked in 1.0: a
    stale [.cmti] can misreport export and skew the gate — a named
    graduation-review risk. No fix: module bodies can perform effects at
    initialization, so deletion is never mechanical. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-unused-module-binding]. *)
