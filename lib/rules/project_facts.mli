(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Shared fact shape and per-unit collection for the cross-module rules.

    [unused-export] and [dead-code] read the same per-unit evidence —
    [Litany.Unit.exports], [Litany.Unit.deps] with [Litany.Unit.unit_refs], the
    [uses]/[implementations] internal-use join, and the roster metadata root
    policy — so one private module owns the fact type and the [collect] phase;
    each rule's [report] interprets the facts by its own semantics
    (non-transitive vs. reachability). Support module of [litany_rules], not a
    rule and not re-exported.

    Every payload is plain data — strings, [Shape.Uid.t] (variants of
    string/int), [Location.t] records — so facts are Marshal-safe as
    [Litany.Rule.project] requires; the suites round-trip them. *)

type decl = {
  path : string;
      (** The owning unit's adapter-supplied source path — the solver's owner
          key. *)
  unit_name : string;  (** The recorded compilation unit name. *)
  uid : Shape.Uid.t;  (** The export's declaration UID — the join key. *)
  name : string;  (** Dotted path from the unit's top level. *)
  loc : Location.t;
      (** The declaration's location, [pos_fname] rewritten to an
          adapter-supplied path when the recorded name matches the unit's
          interface source or editable source by basename — the finding anchor.
          A loc whose recorded name matches neither (a preprocessed unit's pp
          file) is carried as recorded and renders location-only. *)
  root : bool;
      (** Explicit root: a public (or unknown-visibility) library export under
          the open-world default, or a [[\@litany.root]]-annotated declaration.
      *)
  used_internally : bool;
      (** The unit's own implementation references the declaration ([uses]
          joined through [implementations] for interface UIDs). *)
}
(** The type for one exported value declaration. Value rows only: type and
    module exports have no always-on cross-unit use signal (the use index is
    value-shaped; occurrence recording is build-flag-dependent), so 1.0 keeps
    them out of the universe rather than guess. *)

type t =
  | Decl of decl  (** One exported value declaration. *)
  | Unit_node of {
      path : string;
      unit_name : string;
      root : bool;
          (** The unit's top level runs when its product does: executables and
              tests. *)
    }  (** One fact per collected unit — the universe stays complete. *)
  | Use_item of { user : string; uid : Shape.Uid.t }
      (** [user] (a unit name) references the foreign declaration [uid] —
          [deps]' item-level rows. *)
  | Use_unit of { user : string; target : string }
      (** [user] references compilation unit [target] without a pinned
          declaration — [deps]' unit-level rows. [target] may be a wrapper
          module; consumers match it against unit names and their
          [target ^ "__"] extensions. *)

val collect : closed_world:bool -> Litany.Unit.t -> t list
(** [collect ~closed_world u] is [u]'s facts: one {!Unit_node}, a {!Decl} per
    exported value, and one use fact per [deps] row. [closed_world] drops the
    public-library-exports-are-roots default ([@litany.root] still roots).
    Deterministic: exports are signature-ordered, deps sorted, per
    [Litany.Unit]. *)

val projects_into : target:string -> string -> bool
(** [projects_into ~target unit_name] is [true] iff a unit-level reference to
    [target] can reach [unit_name]'s declarations: the names are equal, or
    [target] is a wrapper [unit_name] is mangled under ([target ^ "__" ^ ...]).
*)

val shield_targets : string -> string list
(** [shield_targets unit_name] is every [target] for which
    [projects_into ~target unit_name] holds — the name itself plus each of its
    wrapper prefixes, a handful of strings. The report phases key their
    unit-reference joins by these so each row answers by table lookup instead of
    a scan over all units: the joins stay linear in the fact universe. *)
