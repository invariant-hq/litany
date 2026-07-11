(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Trailing ASCII spaces and tabs.

    A text rule: reports each maximal run of ASCII space or tab immediately
    before LF, CRLF, or end of file, spanning exactly the whitespace run. A lone
    CR is ordinary source content, not a line ending. Every finding carries the
    deletion fix ([delete the trailing whitespace]). *)

val rule : Litany.Rule.t
(** [rule] is [trailing-whitespace]. *)
