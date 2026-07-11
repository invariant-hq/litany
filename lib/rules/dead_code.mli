(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Exported values unreachable from any root.

    A cross-module ([Litany.Rule.project]) rule: per unit it collects the
    export/dependency facts ([Project_facts]); once, over the whole workspace,
    it runs the pure reachability solver ([Dead_code_solver]) — forward closure
    from the explicit roots — and reports every exported value outside the
    closure, dead islands (mutually recursive included) whole. Roots: public (or
    unknown-visibility) library exports unless [closed-world], the top level of
    executables and tests, [[\@litany.root]] annotations. Value rows only;
    intra-unit granularity is conservative (a live unit keeps its
    internally-referenced exports alive — recorded false-negative direction).
    Withheld (with the blockers named) whenever any roster unit is a fact-skip,
    and blocked by the engine (the duplicates named) when two distinct units
    share one compilation unit name — unit names key cross-module identity, and
    they are not workspace-unique ([Litany.Engine.Report.Ambiguous]). *)

val rule : Litany.Rule.t
(** [rule] is [dead-code], open-world. *)

val v : closed_world:bool -> Litany.Rule.t
(** [v ~closed_world] is the rule under the given world assumption — the driver
    substitutes the closed-world variant when the config file says
    [(closed-world true)]. *)
