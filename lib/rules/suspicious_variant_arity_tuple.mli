(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Constructors declaring one boxed tuple field.

    Reports every variant constructor whose argument list is exactly one
    parenthesized tuple type — [C of (int * int)] declares one field holding a
    boxed tuple where [C of int * int] declares two inline fields: an extra
    allocation and indirection per construction and match, invisible at most use
    sites because [C (x, y)] typechecks against both. GADT syntax draws the same
    line and is covered uniformly. Measured, OCaml 5.5.0 arm64 non-flambda: 5.0
    against 3.0 words per construction (+67% minor-heap) plus one indirection
    per match.

    [[@@unboxed]] declarations are exempt (the attribute requires the
    single-argument form); a tuple among several fields and a named tuple type
    are silent by construction. No fix — flattening changes the runtime
    representation. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-variant-arity-tuple]. *)
