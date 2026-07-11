(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [let rec] groups that never recurse.

    Reports a [let rec] group — structure-level items and expression-level
    [let … in] alike — none of whose bindings references any binding of the
    group: warning 39's whole-group judgment, proved by declaration identity
    from the unit's use index, made config-independent and paired with the
    mechanical fix (delete [rec]) the compiler cannot offer.

    Identity-exact: a self- or cross-reference at any nesting depth inside a
    group body blocks the finding; a same-spelled inner rebinding never counts;
    uses after the group do not block. Partially recursive groups never fire —
    dropping [rec] is not their remedy. Class-body groups are a recorded false
    negative (the group dispatch does not see them); the fix is refused when
    anything but whitespace separates [let], [rec], and the first pattern. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-rec-without-recursion]. *)
