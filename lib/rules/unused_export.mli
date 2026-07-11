(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Exported values no other unit uses.

    A cross-module ([Litany.Rule.project]) rule: per unit it collects the
    export/dependency facts ([Project_facts]); once, over the whole workspace,
    it reports each non-root exported value whose declaration UID appears in no
    {e other} unit's item-level references and whose owner no other unit
    references at unit level. Deliberately non-transitive — whether the users
    are themselves alive is [dead-code]'s judgment. Public-library exports and
    [[\@litany.root]]-annotated declarations are roots, never candidates;
    [closed-world] in the config drops the public-export default; executables
    and tests have no interface surface and contribute no candidates. Value
    declarations only, per the recorded 1.0 scope. Withheld (with the blockers
    named) whenever any roster unit is a fact-skip, and blocked by the engine
    (the duplicates named) when two distinct units share one compilation unit
    name — unit names key cross-module identity, and they are not
    workspace-unique ([Litany.Engine.Report.Ambiguous]). *)

val rule : Litany.Rule.t
(** [rule] is [unused-export], open-world. *)

val v : closed_world:bool -> Litany.Rule.t
(** [v ~closed_world] is the rule under the given world assumption — the driver
    substitutes the closed-world variant when the config file says
    [(closed-world true)]. *)
