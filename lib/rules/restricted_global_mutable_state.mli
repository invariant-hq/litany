(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Toplevel mutable state in library code.

    Reports every variable bound by an item of the unit's root structure whose
    type's head is structurally mutable — [Stdlib.ref], [Stdlib.Hashtbl.t], or a
    record type declared at the unit's root with a [mutable] field — in units
    whose roster kind is [Library]. Executables and tests own their process and
    never fire; kindless units are silent — a metadata-gated rule degrades to
    silence, never to guessing.

    Local bindings, [lazy] thunks, pure records, and state-returning functions
    do not fire. Arrays are out of scope in v1: the array type does not
    distinguish a buffer from state. Abbreviation heads are never expanded,
    mutable-record heads the unit does not declare at its own root stay clean,
    and destructuring or wildcard bindings stay clean — recorded false negatives
    in the safe direction. Memo tables, interning pools, and caches are the
    named false-positive shapes; [[\@litany.allow]] with a reason is the
    designed outlet. House policy ([Restriction]: deliberate globals are
    legitimate in the field — off even under [all], cherry-picked). No fix:
    moving state into the caller is an API redesign. *)

val rule : Litany.Rule.t
(** [rule] is [restricted-global-mutable-state]. *)
