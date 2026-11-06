(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Wildcard arms over a variant the code owns.

    Reports a guard-less [_] value arm of a [match] whose other arms name a
    constructor of a variant declared in the same unit, the same wrapped
    library, or a library its [(owned <library> ...)] option names. House policy
    ([Restriction]). No fix. *)

val rule : Litany.Rule.t
(** [rule] is [wildcard-over-owned-variant]. *)
