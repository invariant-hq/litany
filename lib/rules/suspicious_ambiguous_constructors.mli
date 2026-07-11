(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Constructors that shadow standard constructors.

    Reports every constructor of a variant declaration named [Some], [None],
    [Ok], [Error], [::], or [[]] — each shadows a predefined or stdlib
    constructor for the rest of the scope, rewiring unannotated uses below the
    declaration. Warnings 41/42 make the complementary use-site judgment and are
    off in every mainstream default; the declaration is dark everywhere.

    Re-exports ([type 'a maybe = 'a option = None | Some of 'a]) are exempt: a
    variant kind with a manifest redeclares constructors that already exist.
    Extension constructors ([exception Error of string]) are a recorded false
    negative. No fix — the remedy is a design decision. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-ambiguous-constructors]. *)
