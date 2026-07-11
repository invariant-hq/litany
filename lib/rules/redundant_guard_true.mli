(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [when] guards that are literally [true] or [false].

    Reports every case of a [match], [function], or [try] whose guard is the
    boolean literal itself, by predefined-constructor identity: an always-[true]
    guard never fails (the [when] is noise that degrades exhaustiveness
    analysis), an always-[false] guard never succeeds (the arm is dead). Each
    carries its own message, anchored at the guard.

    Real guards, named flags ([when debug]), and compound guards
    ([when true && debug] — redundant-boolean-operator's node) deliberately do
    not fire; matches carrying effect-handler cases are refused (recorded false
    negative). The fix deletes an always-true guard only on the final arm and
    only when the bytes after the pattern are exactly [when] [true] with
    whitespace; always-false guards never carry a fix. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-guard-true]. *)
