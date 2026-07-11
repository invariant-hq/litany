(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Exceptions declared in public library interfaces.

    Reports every exception of the export surface — the interface when the unit
    has one, the inferred signature otherwise — of units whose roster kind is
    [Library] and whose visibility is [Public] ([Unknown] is treated as
    [Public], the roster's root convention), anchored at the implementation's
    matching root [exception] declaration. Executables, tests, private
    libraries, and kindless units never fire — a metadata-gated rule degrades to
    silence, never to guessing.

    Exceptions the [.mli] hides, [let exception] inside functions, and
    [type t += …] extension constructors do not fire. Recorded false negatives
    in the safe direction: submodule-signature exceptions (the export surface
    joins interface to implementation at the unit's root only) and interface
    exceptions satisfied by [include] (no root declaration to anchor at). House
    policy ([Restriction]: declared exceptions are legitimate across the
    ecosystem — never Suspicious — and a result-typed error style is adopted,
    cherry-picked, off even under [all]). No fix: replacing an exception with a
    [result] is an API redesign. *)

val rule : Litany.Rule.t
(** [rule] is [restricted-public-exception]. *)
