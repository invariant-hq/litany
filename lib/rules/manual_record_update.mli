(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Records rebuilt field by field from one base.

    Reports each extension-less record expression in which some identifier base
    has two or more fields copied verbatim ([l = b.l], same label by declaration
    identity) — [{ b with ... }] written longhand, or, when every field is a
    copy of an immutable record, the base itself. A full rebuild of a record
    with a mutable label is the deliberate copy idiom and stays silent; a
    non-identifier base never counts (re-evaluation under [with] would change
    effects). Label identity — equal name, [Path.same] record head — makes a
    cross-type suggestion structurally impossible. No fix: the rewrite deletes
    and reorders fields. *)

val rule : Litany.Rule.t
(** [rule] is [manual-record-update]. *)
