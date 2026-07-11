(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Polymorphic [Hashtbl] operations keyed by a value proved functional.

    Reports exact-arity applications of [Stdlib.Hashtbl]'s polymorphic
    operations ([find], [find_opt], [find_all], [mem], [remove], [seeded_hash],
    [hash]) whose hashed argument's type proves a function — an arrow, or a
    predefined container ([list], [array], [option]) holding one. Such keys are
    broken at runtime, but not by hashing: [Hashtbl.hash] on a closure returns a
    value — different on every run — and a lookup raises [Invalid_argument] only
    when a distinct functional key shares its bucket, misses silently otherwise,
    and succeeds only on physical identity.

    The type proof expands nothing: abbreviations and type variables stay clean,
    as do shadowed [Hashtbl] modules, partial applications, and [Hashtbl.Make]
    instances (their own identities, and the remedy). No fix: picking a hashable
    key needs domain intent. *)

val rule : Litany.Rule.t
(** [rule] is [invalid-hashtable-key]. *)
