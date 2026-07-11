(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** References to [Stdlib.exit] in library code.

    Reports each identifier resolving to [Stdlib.exit] in units whose roster
    kind is [Library]: a library that exits the process usurps a decision that
    belongs to the application. Executables and tests are clean by kind, and
    units without kind metadata are silent — a metadata-gated rule degrades to
    silence, never to guessing.

    Identity is the resolved declaration: qualified spellings and aliases fire;
    [raise Exit] (an exception constructor), [at_exit], and a shadowing local
    [exit] do not. No fix: the replacement error path is a design decision. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-exit-in-library]. *)
