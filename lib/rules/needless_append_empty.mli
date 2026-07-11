(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Append or concatenation with the neutral element.

    Reports every [@]/[List.append] resolved to its [Stdlib] declaration with
    the predefined [[]] as either operand, and every [^]/[String.cat] with the
    literal [""] as either operand: nothing is concatenated, and three of the
    four legs allocate a needless copy. A both-empty operation reports once.

    Singleton appends, shadowed operators, [String.concat], and [Bytes.cat]
    deliberately do not fire. The fix replaces the application with the other
    operand — safe for [[] @ l] (physical identity preserved: append returns its
    second argument), unsafe for the copy-removing legs, whose titles say so.
    Verified, OCaml 5.5.0 arm64 non-flambda: the identity matrix has exactly one
    true cell — [([] @ l) == l]; the other three legs copy, so the fix split is
    the runtime's own behavior. *)

val rule : Litany.Rule.t
(** [rule] is [needless-append-empty]. *)
