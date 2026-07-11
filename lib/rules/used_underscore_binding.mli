(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Bindings whose leading underscore declares them unused, yet are used.

    Reports, once per binding and anchored at the declaration, a variable or
    alias pattern binding a name that begins with exactly one underscore when
    the unit uses that declaration anywhere — bare or qualified through a module
    path; the prefix promises the binding is unused and silences the compiler's
    unused warnings, so a use makes the name lie.

    The wildcard [_], names beginning with two underscores, unused underscore
    bindings, ordinary names, and uses through a signature ascription (a
    distinct minted identity) stay clean — as do tool-minted names even when
    used: an underscore followed by digits only (menhir semantic values) and
    names ending in a double underscore, digits, and a final underscore
    (ppx-internal shapes). Renaming is a refactor, not a mechanical edit, so the
    rule offers no fix. *)

val rule : Litany.Rule.t
(** [rule] is [used-underscore-binding]. *)
