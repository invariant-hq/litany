(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Normalized source-slice equality — the shared technique, in its one home.

    Rules that compare what the author literally wrote slice the editable source
    at two locations and compare the slices after whitespace normalization only:
    a report built on this equality means "the author wrote the same bytes
    twice", never "these expressions are equivalent". Internal to
    [litany_rules]; not rule-author surface. *)

val normalize : string -> string
(** [normalize s] collapses every maximal run of space, tab, CR, or LF in [s] to
    one space and drops leading and trailing runs. Nothing else is touched: no
    comment stripping, no token-level normalization — two slices that normalize
    equal differ at most in whitespace layout. *)

val slice : Litany.Unit.t -> Litany.Location.t -> string option
(** [slice u loc] is the editable-source bytes of [u] under [loc], or [None]
    when [loc] is ghost or outside the source — the refusing answer, never an
    error: a location under a textual preprocessor counts bytes litany does not
    own, and the technique then simply does not apply. *)
