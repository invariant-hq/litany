(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Bindings that only forward their arguments.

    Reports a variable binding of an n-parameter function whose body is one
    application forwarding exactly those parameters, in order, to a single
    identifier callee — [let f x y = g x y] is [let f = g] with ceremony.
    Forwarding is proved by positional [Ident.same] identity; the reduction must
    be legal and type-preserving: the callee is neither the binding nor a
    parameter, and its arrow spine is unlabeled over the forwarded prefix (the
    probe-pinned optional-argument erasure gate). The value restriction is not a
    hazard — the callee is a syntactic value, so [let f = g] generalizes
    identically. Pedantic and off: deliberate wrappers are true positives and
    defensible. No fix, ever. *)

val rule : Litany.Rule.t
(** [rule] is [eta-reducible-forwarding]. *)
