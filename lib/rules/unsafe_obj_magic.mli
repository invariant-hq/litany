(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Uses of [Obj.magic].

    Reports every identifier expression whose resolved declaration is
    [Stdlib.Obj.magic] — direct calls, opened uses, and first-class references,
    at the identifier itself. Shadowed same-spelling definitions, later uses of
    an alias bound to it, other [Obj] members, and unresolved identities stay
    clean. House policy ([Restriction]: trusted low-level boundaries use
    [Obj.magic] deliberately — a ban is a workspace's call, off even under
    [all], cherry-picked). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [unsafe-obj-magic]. *)
