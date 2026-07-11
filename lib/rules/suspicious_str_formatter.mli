(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** References to the process-global [Format.str_formatter].

    Reports each identifier resolving to [Stdlib.Format.str_formatter] or
    [Stdlib.Format.flush_str_formatter] in Library-kind units: one
    process-global buffer whose interleaved users corrupt each other and whose
    contents survive exceptions — verified, OCaml 5.5.0 arm64 non-flambda: an
    interleaved writer's flush steals the other writer's prefix, and the
    corruption surfaces in the innocent writer. [Format.asprintf] is the
    replacement. Identity is the declaration UID — aliases and [open]s fire, a
    shadowing local [Format] never does. Units without kind metadata and
    executables stay silent. The declared [Sometimes] pair-rewrite fix is a
    recorded gap in this version. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-str-formatter]. *)
