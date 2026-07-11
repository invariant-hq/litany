(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Console printing entrypoints referenced in library code.

    Reports each identifier resolving to [Stdlib.print_endline], [print_string],
    [Printf.printf], [Printf.eprintf], or [prerr_endline] in units whose roster
    kind is [Library] — debugging leftovers or layering violations; executables
    and tests print by right.

    Identity is the resolved declaration: aliases fire, a shadowing local
    [print_endline] does not. Units without kind metadata are silent — a
    metadata-gated rule degrades to silence, never to guessing. House policy
    ([Restriction]: a console-ownership boundary some projects reject — off even
    under [all], cherry-picked); no fix, the remedy is a design decision. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-print-debugging]. *)
