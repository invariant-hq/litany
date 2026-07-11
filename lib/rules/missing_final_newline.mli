(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Non-empty files that do not end with LF.

    Reports a zero-width finding at the end-of-file insertion point when the
    final byte of a non-empty source is not LF. Line-oriented tools miscount or
    concatenate such files, and appending a line churns the previous one.

    Empty files stay clean, and CRLF endings are accepted because their final
    byte is LF. Every finding carries the insertion fix ([add a final newline]),
    in the file's own ending style — CRLF when the last line break is CRLF, LF
    otherwise. *)

val rule : Litany.Rule.t
(** [rule] is [missing-final-newline]. *)
