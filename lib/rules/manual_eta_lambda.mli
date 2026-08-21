(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Anonymous functions that only forward their parameters.

    Reports a [fun] expression, in any position, whose parameters are unlabeled
    plain variables and whose body is one application of an identifier callee to
    exactly those parameters, in order — [fun x -> parse x] is [parse] in a
    closure. Forwarding is proved by positional [Ident.same] identity, and the
    gate makes the reduction exact: the callee is a plain identifier or module
    path, not a parameter, not an operator; the application is total over the
    parameters with no extra, labeled, optional, coerced, or annotated argument;
    the callee's arrow spine is unlabeled over the forwarded prefix; nothing
    annotated is dropped. Closure identity does change ([f == f] where two
    wrappers were distinct), which only a function comparison — itself flagged —
    can observe. A lambda that is a [let] binding's whole right-hand side is
    [eta-reducible-forwarding]'s and never fires here; a tail-position lambda in
    a [let rec] right-hand side forwarding to a recursively bound name does not
    fire (the reduction is rejected by the recursive-definition check). Style
    and off. The fix replaces the lambda with the callee's spelling, the
    author's parentheses restored ([Unit.delimited]); Safe under the gate. *)

val rule : Litany.Rule.t
(** [rule] is [manual-eta-lambda]. *)
